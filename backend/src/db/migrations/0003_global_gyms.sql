-- Global gym directory, multi-gym membership and worldwide discovery.
--
-- Additive and data-preserving: no existing gym, membership, profile or
-- preference row is deleted. Coordinates are stored for distance queries and
-- are never returned as another member's location; a selected gym is a
-- declared preference, not verified attendance.
--
-- This deployment does not ship PostGIS, so nearby search uses an indexed
-- bounding box followed by a haversine distance filter. pg_trgm backs the
-- normalized text search.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Lowercases and strips punctuation so "Gold's Gym!" and "golds gym" match.
CREATE FUNCTION gym_normalize(p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(regexp_replace(
        regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g'),
        '\s+', ' ', 'g'
    ));
$$;

-- ---------------------------------------------------------------------------
-- Gym directory
-- ---------------------------------------------------------------------------

ALTER TABLE gyms
    ADD COLUMN provider_id text,
    ADD COLUMN provider_name text,
    ADD COLUMN normalized_name text,
    ADD COLUMN country_code text,
    ADD COLUMN postal_code text,
    ADD COLUMN latitude double precision,
    ADD COLUMN longitude double precision,
    ADD COLUMN website text,
    ADD COLUMN phone text,
    ADD COLUMN source text NOT NULL DEFAULT 'forma',
    ADD COLUMN last_verified_at timestamptz,
    ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

UPDATE gyms
   SET normalized_name = gym_normalize(name)
 WHERE normalized_name IS NULL;

ALTER TABLE gyms
    ALTER COLUMN normalized_name SET NOT NULL,
    ALTER COLUMN city DROP NOT NULL,
    ALTER COLUMN country DROP DEFAULT,
    ALTER COLUMN country DROP NOT NULL;

ALTER TABLE gyms
    ADD CONSTRAINT gyms_latitude_range
        CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
    ADD CONSTRAINT gyms_longitude_range
        CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
    ADD CONSTRAINT gyms_coordinates_pair
        CHECK ((latitude IS NULL) = (longitude IS NULL)),
    ADD CONSTRAINT gyms_country_code_format
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    ADD CONSTRAINT gyms_provider_identity
        CHECK ((provider_id IS NULL) = (provider_name IS NULL)),
    ADD CONSTRAINT gyms_source_values
        CHECK (source IN ('forma', 'google', 'osm', 'user'));

ALTER TABLE gyms DROP CONSTRAINT gyms_verification_status_check;
ALTER TABLE gyms
    ADD CONSTRAINT gyms_verification_status_check
        CHECK (verification_status IN ('pending', 'verified', 'rejected', 'imported'));

-- Identity is unchanged for existing rows (case-insensitive name/city/area)
-- and now also includes the country, so two cities named the same in different
-- countries do not collide.
DROP INDEX IF EXISTS gyms_identity_unique;
CREATE UNIQUE INDEX gyms_identity_unique
    ON gyms (
        normalized_name,
        lower(coalesce(city, '')),
        lower(coalesce(country_code, country)),
        lower(coalesce(area, ''))
    );

-- gyms_city_area_idx already exists from 0002 with the same definition.
CREATE INDEX gyms_country_city_idx ON gyms (lower(coalesce(country_code, country)), lower(coalesce(city, '')));
CREATE INDEX gyms_postal_idx ON gyms (lower(coalesce(postal_code, '')));
CREATE INDEX gyms_geo_idx ON gyms (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE UNIQUE INDEX gyms_provider_identity_unique
    ON gyms (provider_name, provider_id)
    WHERE provider_id IS NOT NULL;
CREATE INDEX gyms_search_trgm_idx ON gyms USING gin (
    gym_normalize(
        coalesce(name, '') || ' ' || coalesce(city, '') || ' ' || coalesce(area, '') || ' ' ||
        coalesce(state, '') || ' ' || coalesce(country, '') || ' ' || coalesce(postal_code, '')
    ) gin_trgm_ops
);

-- Provider responses are cached so an external directory is never queried
-- once per keystroke and repeated searches are served from Postgres.
CREATE TABLE gym_provider_cache (
    cache_key text PRIMARY KEY,
    provider text NOT NULL,
    payload jsonb NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX gym_provider_cache_expiry_idx ON gym_provider_cache (expires_at);

-- ---------------------------------------------------------------------------
-- Memberships: a member may keep several gyms, exactly one primary
-- ---------------------------------------------------------------------------

ALTER TABLE gym_memberships ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE gym_memberships ADD COLUMN membership_type text NOT NULL DEFAULT 'member';
ALTER TABLE gym_memberships ADD COLUMN is_primary boolean NOT NULL DEFAULT true;
ALTER TABLE gym_memberships ADD COLUMN visibility text NOT NULL DEFAULT 'members';
ALTER TABLE gym_memberships ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE gym_memberships DROP CONSTRAINT gym_memberships_pkey;
ALTER TABLE gym_memberships ADD CONSTRAINT gym_memberships_pkey PRIMARY KEY (id);
ALTER TABLE gym_memberships
    ADD CONSTRAINT gym_memberships_user_gym_unique UNIQUE (user_id, gym_id),
    ADD CONSTRAINT gym_memberships_type_values
        CHECK (membership_type IN ('member', 'day_pass', 'online', 'coach')),
    ADD CONSTRAINT gym_memberships_visibility_values
        CHECK (visibility IN ('private', 'members', 'public'));

CREATE UNIQUE INDEX gym_memberships_one_primary
    ON gym_memberships (user_id) WHERE is_primary;

-- ---------------------------------------------------------------------------
-- Preferences: global discovery, city/country visibility and stored country
-- ---------------------------------------------------------------------------

ALTER TABLE community_preferences
    ADD COLUMN global_discovery boolean NOT NULL DEFAULT true,
    ADD COLUMN show_city boolean NOT NULL DEFAULT true,
    ADD COLUMN show_country boolean NOT NULL DEFAULT true,
    ADD COLUMN country text,
    ADD COLUMN country_code text;

UPDATE community_preferences SET show_city = show_area;

ALTER TABLE community_preferences
    ADD CONSTRAINT community_preferences_country_code_format
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$');

-- Reports can now target a gym, with an "incorrect details" reason.
ALTER TABLE community_reports DROP CONSTRAINT community_reports_target_type_check;
ALTER TABLE community_reports
    ADD CONSTRAINT community_reports_target_type_check
        CHECK (target_type IN ('profile', 'post', 'comment', 'message', 'gym'));

ALTER TABLE community_reports DROP CONSTRAINT community_reports_reason_check;
ALTER TABLE community_reports
    ADD CONSTRAINT community_reports_reason_check
        CHECK (reason IN (
            'harassment', 'spam', 'inappropriate', 'impersonation',
            'suspicious', 'incorrect_details', 'other'
        ));

-- ---------------------------------------------------------------------------
-- Discovery helpers
-- ---------------------------------------------------------------------------

-- Area compatibility also compares country when both sides have one, so a
-- shared city name in another country is not treated as the same place.
CREATE OR REPLACE FUNCTION community_area_compatible(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM community_preferences a
        JOIN community_preferences b ON true
        WHERE a.user_id = p_a AND b.user_id = p_b
          AND a.city IS NOT NULL AND b.city IS NOT NULL
          AND lower(a.city) = lower(b.city)
          AND (
            a.country_code IS NULL OR b.country_code IS NULL
            OR lower(a.country_code) = lower(b.country_code)
          )
          AND (
            lower(coalesce(a.area, '')) = lower(coalesce(b.area, ''))
            OR EXISTS (
                SELECT 1
                FROM community_areas aa
                JOIN community_areas bb
                  ON lower(aa.nearby_group) = lower(bb.nearby_group)
                 AND lower(aa.city) = lower(bb.city)
                WHERE lower(aa.city) = lower(a.city)
                  AND lower(aa.area) = lower(coalesce(a.area, ''))
                  AND lower(bb.area) = lower(coalesce(b.area, ''))
            )
          )
    );
$$;

-- A member who enabled worldwide discovery is viewable without sharing a gym
-- or area. Age bands, blocks, suspension and discoverability still apply.
CREATE OR REPLACE FUNCTION community_can_view_profile(p_viewer uuid, p_target uuid, p_is_admin boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_viewer IS NOT NULL AND p_target IS NOT NULL AND (
        p_viewer = p_target
        OR p_is_admin
        OR (
            NOT community_is_suspended(p_viewer)
            AND NOT community_is_suspended(p_target)
            AND community_not_blocked(p_viewer, p_target)
            AND community_age_compatible(p_viewer, p_target)
            AND EXISTS (
                SELECT 1 FROM community_profiles cp
                JOIN community_preferences pref ON pref.user_id = cp.user_id
                WHERE cp.user_id = p_target AND pref.discoverable
            )
            AND (
                community_connected(p_viewer, p_target)
                OR community_same_gym(p_viewer, p_target)
                OR community_area_compatible(p_viewer, p_target)
                OR coalesce(
                    (SELECT global_discovery FROM community_preferences WHERE user_id = p_target),
                    false
                )
            )
        )
    );
$$;
