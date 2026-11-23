-- Community: gym/area discovery, connections, messaging, feed, notifications,
-- blocking, reporting and server-side moderation.
--
-- Privacy model:
--   * Discovery never uses GPS or background location.
--   * Only coarse gym/area selections are stored and shown.
--   * Age bands and blocks are enforced by the server, never by the client.
--   * Every write is scoped to the authenticated user in SQL, so a client
--     cannot touch another member's rows by changing request fields.

-- ---------------------------------------------------------------------------
-- Reference geography
-- ---------------------------------------------------------------------------

CREATE TABLE community_areas (
    country text NOT NULL DEFAULT 'India',
    state text NOT NULL DEFAULT 'Tamil Nadu',
    city text NOT NULL,
    area text NOT NULL,
    nearby_group text NOT NULL,
    PRIMARY KEY (city, area)
);

INSERT INTO community_areas (city, area, nearby_group) VALUES
    ('Chennai', 'Anna Nagar', 'chennai-central'),
    ('Chennai', 'T. Nagar', 'chennai-central'),
    ('Chennai', 'Nungambakkam', 'chennai-central'),
    ('Chennai', 'Kilpauk', 'chennai-central'),
    ('Chennai', 'Adyar', 'chennai-south'),
    ('Chennai', 'Velachery', 'chennai-south'),
    ('Chennai', 'Thiruvanmiyur', 'chennai-south'),
    ('Chennai', 'Besant Nagar', 'chennai-south'),
    ('Chennai', 'OMR', 'chennai-south'),
    ('Chennai', 'Porur', 'chennai-west'),
    ('Chennai', 'Vadapalani', 'chennai-west'),
    ('Chennai', 'Guindy', 'chennai-west'),
    ('Chennai', 'Ambattur', 'chennai-north'),
    ('Chennai', 'Perambur', 'chennai-north'),
    ('Chennai', 'Royapuram', 'chennai-north');

-- ---------------------------------------------------------------------------
-- Identity, privacy and moderation state
-- ---------------------------------------------------------------------------

CREATE TABLE community_account_status (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    suspended boolean NOT NULL DEFAULT false,
    suspended_reason text,
    suspended_at timestamptz,
    suspended_by uuid REFERENCES users(id) ON DELETE SET NULL,
    age_band text NOT NULL DEFAULT 'unknown' CHECK (age_band IN ('minor', 'adult', 'unknown')),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE community_profiles (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    username text NOT NULL,
    display_name text NOT NULL,
    bio text,
    avatar_url text,
    interests text[] NOT NULL DEFAULT '{}',
    workout_categories text[] NOT NULL DEFAULT '{}',
    achievements_opt_in boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_profiles_username_format CHECK (username ~ '^[a-z0-9_]{3,24}$'),
    CONSTRAINT community_profiles_display_length CHECK (char_length(display_name) BETWEEN 2 AND 50),
    CONSTRAINT community_profiles_bio_length CHECK (bio IS NULL OR char_length(bio) <= 280),
    CONSTRAINT community_profiles_interests_count CHECK (coalesce(array_length(interests, 1), 0) <= 8),
    CONSTRAINT community_profiles_categories_count CHECK (coalesce(array_length(workout_categories, 1), 0) <= 8)
);

CREATE UNIQUE INDEX community_profiles_username_unique ON community_profiles (lower(username));
CREATE INDEX community_profiles_display_idx ON community_profiles (lower(display_name));

CREATE TABLE community_preferences (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    discoverable boolean NOT NULL DEFAULT false,
    show_gym boolean NOT NULL DEFAULT true,
    show_area boolean NOT NULL DEFAULT true,
    nearby_discovery boolean NOT NULL DEFAULT false,
    allow_connection_requests boolean NOT NULL DEFAULT true,
    allow_messages boolean NOT NULL DEFAULT true,
    city text,
    area text,
    notify_connections boolean NOT NULL DEFAULT true,
    notify_messages boolean NOT NULL DEFAULT true,
    notify_comments boolean NOT NULL DEFAULT true,
    notify_likes boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Gyms
-- ---------------------------------------------------------------------------

CREATE TABLE gyms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    address text,
    city text NOT NULL,
    state text,
    country text NOT NULL DEFAULT 'India',
    area text,
    verification_status text NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    submitted_by uuid REFERENCES users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    verified_at timestamptz,
    verified_by uuid REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT gyms_name_length CHECK (char_length(name) BETWEEN 2 AND 90),
    CONSTRAINT gyms_city_length CHECK (char_length(city) BETWEEN 2 AND 60)
);

CREATE UNIQUE INDEX gyms_identity_unique
    ON gyms (lower(name), lower(city), lower(coalesce(area, '')));
CREATE INDEX gyms_city_area_idx ON gyms (lower(city), lower(coalesce(area, '')));

CREATE TABLE gym_memberships (
    user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX gym_memberships_gym_idx ON gym_memberships (gym_id);

-- ---------------------------------------------------------------------------
-- Blocks, connections, conversations, messages
-- ---------------------------------------------------------------------------

CREATE TABLE community_blocks (
    blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT community_blocks_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX community_blocks_blocked_idx ON community_blocks (blocked_id);

CREATE TABLE community_connections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'withdrawn')),
    created_at timestamptz NOT NULL DEFAULT now(),
    responded_at timestamptz,
    CONSTRAINT community_connections_not_self CHECK (requester_id <> recipient_id)
);

CREATE UNIQUE INDEX community_connections_active_pair
    ON community_connections (
        least(requester_id, recipient_id),
        greatest(requester_id, recipient_id)
    )
    WHERE status IN ('pending', 'accepted');
CREATE INDEX community_connections_requester_idx ON community_connections (requester_id, status);
CREATE INDEX community_connections_recipient_idx ON community_connections (recipient_id, status);

CREATE TABLE community_conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id uuid NOT NULL UNIQUE REFERENCES community_connections(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE community_messages (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES community_conversations(id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_messages_body_length CHECK (char_length(body) BETWEEN 1 AND 2000)
);

CREATE INDEX community_messages_conversation_idx
    ON community_messages (conversation_id, created_at DESC);

CREATE TABLE community_conversation_reads (
    conversation_id uuid NOT NULL REFERENCES community_conversations(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE community_conversation_mutes (
    conversation_id uuid NOT NULL REFERENCES community_conversations(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------

CREATE TABLE community_posts (
    id uuid PRIMARY KEY,
    author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content text NOT NULL,
    kind text NOT NULL DEFAULT 'update'
        CHECK (kind IN ('workout', 'milestone', 'achievement', 'update', 'motivation')),
    shared_session jsonb,
    achievement_label text,
    moderation_status text NOT NULL DEFAULT 'visible'
        CHECK (moderation_status IN ('visible', 'removed')),
    like_count integer NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count integer NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_posts_content_length CHECK (char_length(content) BETWEEN 1 AND 2000),
    CONSTRAINT community_posts_achievement_length
        CHECK (achievement_label IS NULL OR char_length(achievement_label) <= 80)
);

CREATE INDEX community_posts_feed_idx ON community_posts (created_at DESC, id DESC);
CREATE INDEX community_posts_author_idx ON community_posts (author_id, created_at DESC);

CREATE TABLE community_likes (
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX community_likes_user_idx ON community_likes (user_id);

CREATE TABLE community_comments (
    id uuid PRIMARY KEY,
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content text NOT NULL,
    moderation_status text NOT NULL DEFAULT 'visible'
        CHECK (moderation_status IN ('visible', 'removed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_comments_content_length CHECK (char_length(content) BETWEEN 1 AND 1000)
);

CREATE INDEX community_comments_post_idx ON community_comments (post_id, created_at);
CREATE INDEX community_comments_author_idx ON community_comments (author_id);

CREATE TABLE community_hidden_posts (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);

-- ---------------------------------------------------------------------------
-- Reports, moderation, notifications
-- ---------------------------------------------------------------------------

CREATE TABLE community_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type text NOT NULL CHECK (target_type IN ('profile', 'post', 'comment', 'message')),
    target_id uuid NOT NULL,
    reason text NOT NULL
        CHECK (reason IN ('harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'other')),
    details text,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
    resolution_note text,
    CONSTRAINT community_reports_details_length CHECK (details IS NULL OR char_length(details) <= 1000)
);

CREATE INDEX community_reports_status_idx ON community_reports (status, created_at DESC);
CREATE INDEX community_reports_target_idx ON community_reports (target_type, target_id);

CREATE TABLE community_moderation_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action text NOT NULL,
    target_type text NOT NULL,
    target_id uuid,
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE community_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind text NOT NULL
        CHECK (kind IN ('connection_request', 'connection_accepted', 'message', 'post_comment', 'post_like')),
    actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
    entity_id uuid,
    post_id uuid REFERENCES community_posts(id) ON DELETE CASCADE,
    body text NOT NULL,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_notifications_body_length CHECK (char_length(body) <= 160)
);

CREATE INDEX community_notifications_user_idx ON community_notifications (user_id, created_at DESC);
CREATE INDEX community_notifications_unread_idx ON community_notifications (user_id) WHERE read_at IS NULL;

-- ---------------------------------------------------------------------------
-- Server-side helpers. Every function takes the viewer explicitly; the
-- router always passes the authenticated session user, never a client value.
-- ---------------------------------------------------------------------------

CREATE FUNCTION community_is_suspended(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT s.suspended FROM community_account_status s WHERE s.user_id = p_user),
        false
    );
$$;

CREATE FUNCTION community_age_band(p_user uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT s.age_band FROM community_account_status s WHERE s.user_id = p_user),
        'unknown'
    );
$$;

CREATE FUNCTION community_age_compatible(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT community_age_band(p_a) <> 'unknown'
       AND community_age_band(p_a) = community_age_band(p_b);
$$;

CREATE FUNCTION community_not_blocked(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM community_blocks b
        WHERE (b.blocker_id = p_a AND b.blocked_id = p_b)
           OR (b.blocker_id = p_b AND b.blocked_id = p_a)
    );
$$;

CREATE FUNCTION community_connected(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM community_connections c
        WHERE c.status = 'accepted'
          AND ((c.requester_id = p_a AND c.recipient_id = p_b)
            OR (c.requester_id = p_b AND c.recipient_id = p_a))
    );
$$;

CREATE FUNCTION community_same_gym(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM gym_memberships a
        JOIN gym_memberships b ON b.gym_id = a.gym_id
        WHERE a.user_id = p_a AND b.user_id = p_b
    );
$$;

CREATE FUNCTION community_area_compatible(p_a uuid, p_b uuid)
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

CREATE FUNCTION community_connection_status(p_viewer uuid, p_target uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN NOT community_not_blocked(p_viewer, p_target) THEN 'blocked'
        WHEN community_connected(p_viewer, p_target) THEN 'accepted'
        WHEN EXISTS (
            SELECT 1 FROM community_connections c
            WHERE c.status = 'pending' AND c.requester_id = p_viewer AND c.recipient_id = p_target
        ) THEN 'pending_sent'
        WHEN EXISTS (
            SELECT 1 FROM community_connections c
            WHERE c.status = 'pending' AND c.requester_id = p_target AND c.recipient_id = p_viewer
        ) THEN 'pending_received'
        ELSE 'none'
    END;
$$;

CREATE FUNCTION community_can_view_profile(p_viewer uuid, p_target uuid, p_is_admin boolean DEFAULT false)
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
            )
        )
    );
$$;

CREATE FUNCTION community_can_read_post(p_viewer uuid, p_post uuid, p_is_admin boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM community_posts p
        JOIN community_profiles cp ON cp.user_id = p.author_id
        JOIN community_preferences pref ON pref.user_id = p.author_id
        WHERE p.id = p_post
          AND p_viewer IS NOT NULL
          AND (
            p.author_id = p_viewer
            OR p_is_admin
            OR (
                p.moderation_status = 'visible'
                AND NOT community_is_suspended(p_viewer)
                AND NOT community_is_suspended(p.author_id)
                AND community_not_blocked(p_viewer, p.author_id)
                AND community_age_compatible(p_viewer, p.author_id)
                AND (
                    community_connected(p_viewer, p.author_id)
                    OR (
                        pref.discoverable
                        AND (
                            (pref.show_gym AND community_same_gym(p_viewer, p.author_id))
                            OR (pref.show_area AND community_area_compatible(p_viewer, p.author_id))
                        )
                    )
                )
                AND (
                    community_age_band(p.author_id) <> 'minor'
                    OR community_connected(p_viewer, p.author_id)
                )
            )
          )
    );
$$;

CREATE FUNCTION community_can_message(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_a IS NOT NULL AND p_b IS NOT NULL
       AND p_a <> p_b
       AND NOT community_is_suspended(p_a)
       AND NOT community_is_suspended(p_b)
       AND community_not_blocked(p_a, p_b)
       AND community_connected(p_a, p_b)
       AND community_age_compatible(p_a, p_b)
       AND coalesce((SELECT allow_messages FROM community_preferences WHERE user_id = p_a), false)
       AND coalesce((SELECT allow_messages FROM community_preferences WHERE user_id = p_b), false);
$$;

CREATE FUNCTION community_conversation_participant(p_conversation uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM community_conversations conv
        JOIN community_connections c ON c.id = conv.connection_id
        WHERE conv.id = p_conversation
          AND (c.requester_id = p_user OR c.recipient_id = p_user)
    );
$$;
