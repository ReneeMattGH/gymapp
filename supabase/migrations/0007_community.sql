-- Community: gym-based discovery, connections, messaging, feed, notifications,
-- blocking, reporting, and server-side moderation.
--
-- Privacy model:
--   * Discovery never uses GPS or background location.
--   * Only coarse gym/area selections are stored and shown.
--   * Precise coordinates on gyms are admin/reference data and never exposed.
--   * Age bands and blocks are enforced on the server, not in the client.
--   * All mutations go through security-definer functions so clients cannot
--     write another user's rows even if they bypass the UI.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Reference geography
-- ---------------------------------------------------------------------------

create table if not exists public.community_areas (
  id uuid primary key default gen_random_uuid(),
  country text not null default 'India',
  state text not null default 'Tamil Nadu',
  city text not null,
  area text not null,
  nearby_group text not null,
  created_at timestamptz not null default now(),
  constraint community_areas_unique unique (city, area)
);

insert into public.community_areas (city, area, nearby_group) values
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
  ('Chennai', 'Royapuram', 'chennai-north')
on conflict (city, area) do nothing;

-- ---------------------------------------------------------------------------
-- Gyms
-- ---------------------------------------------------------------------------

create table if not exists public.gyms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  city text not null,
  state text,
  country text not null default 'India',
  area text,
  latitude double precision,
  longitude double precision,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  submitted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references auth.users (id) on delete set null,
  constraint gyms_name_length check (char_length(name) between 2 and 90),
  constraint gyms_city_length check (char_length(city) between 2 and 60)
);

create unique index if not exists gyms_identity_unique
  on public.gyms (lower(name), lower(city), lower(coalesce(area, '')));
create index if not exists gyms_city_area_idx on public.gyms (lower(city), lower(coalesce(area, '')));
create index if not exists gyms_verification_idx on public.gyms (verification_status);

-- ---------------------------------------------------------------------------
-- Community identity and privacy preferences
-- ---------------------------------------------------------------------------

create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  display_name text not null,
  bio text,
  avatar_url text,
  interests text[] not null default '{}',
  workout_categories text[] not null default '{}',
  achievements_opt_in boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_profiles_username_format check (username ~ '^[a-z0-9_]{3,24}$'),
  constraint community_profiles_display_length check (char_length(display_name) between 2 and 50),
  constraint community_profiles_bio_length check (bio is null or char_length(bio) <= 280),
  constraint community_profiles_interests_count check (coalesce(array_length(interests, 1), 0) <= 8),
  constraint community_profiles_categories_count check (coalesce(array_length(workout_categories, 1), 0) <= 8)
);

create unique index if not exists community_profiles_username_unique
  on public.community_profiles (lower(username));
create index if not exists community_profiles_display_idx
  on public.community_profiles (lower(display_name));

create table if not exists public.community_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  discoverable boolean not null default false,
  show_gym boolean not null default true,
  show_area boolean not null default true,
  nearby_discovery boolean not null default false,
  allow_connection_requests boolean not null default true,
  allow_messages boolean not null default true,
  city text,
  area text,
  notify_connections boolean not null default true,
  notify_messages boolean not null default true,
  notify_comments boolean not null default true,
  notify_likes boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gym_memberships (
  user_id uuid primary key references auth.users (id) on delete cascade,
  gym_id uuid not null references public.gyms (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists gym_memberships_gym_idx on public.gym_memberships (gym_id);

create table if not exists public.community_account_status (
  user_id uuid primary key references auth.users (id) on delete cascade,
  suspended boolean not null default false,
  suspended_reason text,
  suspended_at timestamptz,
  suspended_by uuid references auth.users (id) on delete set null,
  age_band text not null default 'unknown' check (age_band in ('minor', 'adult', 'unknown')),
  updated_at timestamptz not null default now()
);

insert into public.community_account_status (user_id, age_band)
select p.id,
       case when p.age is null then 'unknown'
            when p.age < 18 then 'minor'
            else 'adult' end
from public.profiles p
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Blocks, connections, conversations
-- ---------------------------------------------------------------------------

create table if not exists public.community_blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint community_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists community_blocks_blocked_idx on public.community_blocks (blocked_id);

create table if not exists public.community_connections (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint community_connections_not_self check (requester_id <> recipient_id)
);

create unique index if not exists community_connections_active_pair
  on public.community_connections (
    least(requester_id, recipient_id),
    greatest(requester_id, recipient_id)
  )
  where status in ('pending', 'accepted');
create index if not exists community_connections_requester_idx on public.community_connections (requester_id, status);
create index if not exists community_connections_recipient_idx on public.community_connections (recipient_id, status);

create table if not exists public.community_conversations (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null unique references public.community_connections (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.community_messages (
  id uuid primary key,
  conversation_id uuid not null references public.community_conversations (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint community_messages_body_length check (char_length(body) between 1 and 2000)
);

create index if not exists community_messages_conversation_idx
  on public.community_messages (conversation_id, created_at desc);

create table if not exists public.community_conversation_reads (
  conversation_id uuid not null references public.community_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.community_conversation_mutes (
  conversation_id uuid not null references public.community_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------

create table if not exists public.community_posts (
  id uuid primary key,
  author_id uuid not null references auth.users (id) on delete cascade,
  content text not null,
  kind text not null default 'update'
    check (kind in ('workout', 'milestone', 'achievement', 'update', 'motivation')),
  session_id uuid references public.workout_sessions (id) on delete set null,
  achievement_label text,
  moderation_status text not null default 'visible'
    check (moderation_status in ('visible', 'removed')),
  like_count integer not null default 0 check (like_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_posts_content_length check (char_length(content) between 1 and 2000),
  constraint community_posts_achievement_length check (achievement_label is null or char_length(achievement_label) <= 80)
);

create index if not exists community_posts_feed_idx on public.community_posts (created_at desc, id desc);
create index if not exists community_posts_author_idx on public.community_posts (author_id, created_at desc);

create table if not exists public.community_likes (
  post_id uuid not null references public.community_posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists community_likes_user_idx on public.community_likes (user_id);

create table if not exists public.community_comments (
  id uuid primary key,
  post_id uuid not null references public.community_posts (id) on delete cascade,
  author_id uuid not null references auth.users (id) on delete cascade,
  content text not null,
  moderation_status text not null default 'visible'
    check (moderation_status in ('visible', 'removed')),
  created_at timestamptz not null default now(),
  constraint community_comments_content_length check (char_length(content) between 1 and 1000)
);

create index if not exists community_comments_post_idx on public.community_comments (post_id, created_at);
create index if not exists community_comments_author_idx on public.community_comments (author_id);

create table if not exists public.community_hidden_posts (
  user_id uuid not null references auth.users (id) on delete cascade,
  post_id uuid not null references public.community_posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

-- ---------------------------------------------------------------------------
-- Reports, moderation, notifications
-- ---------------------------------------------------------------------------

create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'post', 'comment', 'message')),
  target_id uuid not null,
  reason text not null check (reason in ('harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'other')),
  details text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null,
  resolution_note text,
  constraint community_reports_details_length check (details is null or char_length(details) <= 1000)
);

create index if not exists community_reports_status_idx on public.community_reports (status, created_at desc);
create index if not exists community_reports_target_idx on public.community_reports (target_type, target_id);

create table if not exists public.community_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.community_moderation_actions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id) on delete cascade,
  action text not null,
  target_type text not null,
  target_id uuid,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.community_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('connection_request', 'connection_accepted', 'message', 'post_comment', 'post_like')),
  actor_id uuid references auth.users (id) on delete set null,
  entity_id uuid,
  post_id uuid references public.community_posts (id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint community_notifications_body_length check (char_length(body) <= 160)
);

create index if not exists community_notifications_user_idx
  on public.community_notifications (user_id, created_at desc);
create index if not exists community_notifications_unread_idx
  on public.community_notifications (user_id) where read_at is null;

-- ---------------------------------------------------------------------------
-- Server-side helpers
-- ---------------------------------------------------------------------------

create or replace function public.community_is_admin(p_user uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select p_user is not null
     and exists (select 1 from public.community_admins a where a.user_id = p_user);
$$;

create or replace function public.community_is_suspended(p_user uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select s.suspended from public.community_account_status s where s.user_id = p_user), false);
$$;

create or replace function public.community_age_band(p_user uuid)
returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select s.age_band from public.community_account_status s where s.user_id = p_user),
    case
      when exists (select 1 from public.profiles p where p.id = p_user and p.age is not null) then
        case when (select p.age from public.profiles p where p.id = p_user) < 18 then 'minor' else 'adult' end
      else 'unknown'
    end
  );
$$;

create or replace function public.community_age_compatible(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when public.community_age_band(p_a) = 'unknown' or public.community_age_band(p_b) = 'unknown' then false
    else public.community_age_band(p_a) = public.community_age_band(p_b)
  end;
$$;

create or replace function public.community_not_blocked(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select not exists (
    select 1 from public.community_blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b)
       or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

create or replace function public.community_connected(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.community_connections c
    where c.status = 'accepted'
      and ((c.requester_id = p_a and c.recipient_id = p_b)
        or (c.requester_id = p_b and c.recipient_id = p_a))
  );
$$;

create or replace function public.community_same_gym(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.gym_memberships a
    join public.gym_memberships b on b.gym_id = a.gym_id
    where a.user_id = p_a and b.user_id = p_b
  );
$$;

create or replace function public.community_area_compatible(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.community_preferences a
    join public.community_preferences b on true
    where a.user_id = p_a and b.user_id = p_b
      and a.city is not null and b.city is not null
      and lower(a.city) = lower(b.city)
      and (
        lower(coalesce(a.area, '')) = lower(coalesce(b.area, ''))
        or exists (
          select 1
          from public.community_areas aa
          join public.community_areas bb
            on lower(aa.nearby_group) = lower(bb.nearby_group)
           and lower(aa.city) = lower(bb.city)
          where lower(aa.city) = lower(a.city)
            and lower(aa.area) = lower(coalesce(a.area, ''))
            and lower(bb.area) = lower(coalesce(b.area, ''))
        )
      )
  );
$$;

create or replace function public.community_connection_status(p_viewer uuid, p_target uuid)
returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when not public.community_not_blocked(p_viewer, p_target) then 'blocked'
    when exists (
      select 1 from public.community_connections c
      where c.status = 'accepted'
        and ((c.requester_id = p_viewer and c.recipient_id = p_target)
          or (c.requester_id = p_target and c.recipient_id = p_viewer))
    ) then 'accepted'
    when exists (
      select 1 from public.community_connections c
      where c.status = 'pending' and c.requester_id = p_viewer and c.recipient_id = p_target
    ) then 'pending_sent'
    when exists (
      select 1 from public.community_connections c
      where c.status = 'pending' and c.requester_id = p_target and c.recipient_id = p_viewer
    ) then 'pending_received'
    else 'none'
  end;
$$;

create or replace function public.community_can_view_profile(p_viewer uuid, p_target uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select p_viewer is not null and p_target is not null and (
    p_viewer = p_target
    or public.community_is_admin(p_viewer)
    or (
      not public.community_is_suspended(p_viewer)
      and not public.community_is_suspended(p_target)
      and public.community_not_blocked(p_viewer, p_target)
      and public.community_age_compatible(p_viewer, p_target)
      and exists (
        select 1 from public.community_profiles cp
        join public.community_preferences pref on pref.user_id = cp.user_id
        where cp.user_id = p_target and pref.discoverable
      )
      and (
        public.community_connected(p_viewer, p_target)
        or public.community_same_gym(p_viewer, p_target)
        or public.community_area_compatible(p_viewer, p_target)
      )
    )
  );
$$;

create or replace function public.community_can_read_post(p_viewer uuid, p_post uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.community_posts p
    join public.community_profiles cp on cp.user_id = p.author_id
    join public.community_preferences pref on pref.user_id = p.author_id
    where p.id = p_post
      and p_viewer is not null
      and (
        p.author_id = p_viewer
        or public.community_is_admin(p_viewer)
        or (
          p.moderation_status = 'visible'
          and not public.community_is_suspended(p_viewer)
          and not public.community_is_suspended(p.author_id)
          and public.community_not_blocked(p_viewer, p.author_id)
          and public.community_age_compatible(p_viewer, p.author_id)
          and (
            public.community_connected(p_viewer, p.author_id)
            or (
              pref.discoverable
              and (
                (pref.show_gym and public.community_same_gym(p_viewer, p.author_id))
                or (pref.show_area and public.community_area_compatible(p_viewer, p.author_id))
              )
            )
          )
          and (
            public.community_age_band(p.author_id) <> 'minor'
            or public.community_connected(p_viewer, p.author_id)
          )
        )
      )
  );
$$;

create or replace function public.community_can_message(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select p_a is not null and p_b is not null
    and p_a <> p_b
    and not public.community_is_suspended(p_a)
    and not public.community_is_suspended(p_b)
    and public.community_not_blocked(p_a, p_b)
    and public.community_connected(p_a, p_b)
    and public.community_age_compatible(p_a, p_b)
    and coalesce((select allow_messages from public.community_preferences where user_id = p_a), false)
    and coalesce((select allow_messages from public.community_preferences where user_id = p_b), false);
$$;

create or replace function public.community_conversation_participant(p_conversation uuid, p_user uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.community_conversations conv
    join public.community_connections c on c.id = conv.connection_id
    where conv.id = p_conversation
      and (c.requester_id = p_user or c.recipient_id = p_user)
  );
$$;

-- ---------------------------------------------------------------------------
-- Discovery and home
-- ---------------------------------------------------------------------------

create or replace function public.community_discover(
  p_scope text default 'gym',
  p_query text default '',
  p_interest text default '',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  interests text[],
  workout_categories text[],
  gym_name text,
  area text,
  city text,
  connection_status text
)
language sql stable security definer set search_path = public, pg_temp as $$
  with me as (
    select auth.uid() as id
  ),
  eligible as (
    select cp.user_id,
           cp.username,
           cp.display_name,
           cp.avatar_url,
           cp.bio,
           cp.interests,
           cp.workout_categories,
           case when pref.show_gym then g.name else null end as gym_name,
           case when pref.show_area then pref.area else null end as area,
           case when pref.show_area then pref.city else null end as city,
           public.community_same_gym(m.id, cp.user_id) as shares_gym,
           public.community_area_compatible(m.id, cp.user_id) as shares_area
    from public.community_profiles cp
    join public.community_preferences pref on pref.user_id = cp.user_id
    left join public.gym_memberships gm on gm.user_id = cp.user_id
    left join public.gyms g on g.id = gm.gym_id
    cross join me m
    where m.id is not null
      and cp.user_id <> m.id
      and pref.discoverable
      and not public.community_is_suspended(cp.user_id)
      and not public.community_is_suspended(m.id)
      and public.community_not_blocked(m.id, cp.user_id)
      and public.community_age_compatible(m.id, cp.user_id)
      and (
        (lower(coalesce(p_scope, 'gym')) = 'gym'
          and pref.show_gym
          and public.community_same_gym(m.id, cp.user_id))
        or (lower(coalesce(p_scope, 'gym')) = 'area'
          and pref.show_area
          and pref.nearby_discovery
          and public.community_area_compatible(m.id, cp.user_id))
        or lower(coalesce(p_scope, 'gym')) = 'all'
      )
  )
  select e.user_id,
         e.username,
         e.display_name,
         e.avatar_url,
         e.bio,
         e.interests,
         e.workout_categories,
         e.gym_name,
         e.area,
         e.city,
         public.community_connection_status((select id from me), e.user_id) as connection_status
  from eligible e
  where (
      trim(coalesce(p_query, '')) = ''
      or lower(e.username) like '%' || lower(trim(p_query)) || '%'
      or lower(e.display_name) like '%' || lower(trim(p_query)) || '%'
      or lower(coalesce(e.gym_name, '')) like '%' || lower(trim(p_query)) || '%'
      or lower(coalesce(e.area, '')) like '%' || lower(trim(p_query)) || '%'
      or lower(coalesce(e.city, '')) like '%' || lower(trim(p_query)) || '%'
    )
    and (
      trim(coalesce(p_interest, '')) = ''
      or exists (select 1 from unnest(e.interests) i where lower(i) = lower(trim(p_interest)))
      or exists (select 1 from unnest(e.workout_categories) c where lower(c) = lower(trim(p_interest)))
    )
  order by e.shares_gym desc, e.shares_area desc, lower(e.display_name)
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.community_home()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  gym_count integer := 0;
  area_count integer := 0;
  request_count integer := 0;
  unread_notifications integer := 0;
  unread_messages integer := 0;
begin
  if uid is null then
    raise exception 'Sign in to use Community.';
  end if;

  select count(*) into gym_count
  from public.community_profiles cp
  join public.community_preferences pref on pref.user_id = cp.user_id
  where cp.user_id <> uid
    and pref.discoverable and pref.show_gym
    and not public.community_is_suspended(cp.user_id)
    and not public.community_is_suspended(uid)
    and public.community_not_blocked(uid, cp.user_id)
    and public.community_age_compatible(uid, cp.user_id)
    and public.community_same_gym(uid, cp.user_id);

  select count(*) into area_count
  from public.community_profiles cp
  join public.community_preferences pref on pref.user_id = cp.user_id
  where cp.user_id <> uid
    and pref.discoverable and pref.show_area and pref.nearby_discovery
    and not public.community_is_suspended(cp.user_id)
    and not public.community_is_suspended(uid)
    and public.community_not_blocked(uid, cp.user_id)
    and public.community_age_compatible(uid, cp.user_id)
    and public.community_area_compatible(uid, cp.user_id);

  select count(*) into request_count
  from public.community_connections c
  where c.recipient_id = uid and c.status = 'pending';

  select count(*) into unread_notifications
  from public.community_notifications n
  where n.user_id = uid and n.read_at is null;

  select count(*) into unread_messages
  from public.community_conversations conv
  join public.community_connections c on c.id = conv.connection_id
  left join public.community_conversation_reads r
    on r.conversation_id = conv.id and r.user_id = uid
  where (c.requester_id = uid or c.recipient_id = uid)
    and exists (
      select 1 from public.community_messages m
      where m.conversation_id = conv.id
        and m.sender_id <> uid
        and m.created_at > coalesce(r.last_read_at, 'epoch'::timestamptz)
    );

  return jsonb_build_object(
    'profile', (select to_jsonb(cp) from public.community_profiles cp where cp.user_id = uid),
    'preferences', (select to_jsonb(pref) from public.community_preferences pref where pref.user_id = uid),
    'membership', (
      select jsonb_build_object(
        'gym_id', g.id,
        'gym_name', g.name,
        'address', g.address,
        'city', g.city,
        'area', g.area,
        'verification_status', g.verification_status
      )
      from public.gym_memberships gm
      join public.gyms g on g.id = gm.gym_id
      where gm.user_id = uid
    ),
    'is_admin', public.community_is_admin(uid),
    'suspended', public.community_is_suspended(uid),
    'members_at_gym', gym_count,
    'nearby_members', area_count,
    'incoming_request_count', request_count,
    'unread_notifications', unread_notifications,
    'unread_messages', unread_messages,
    'suggestions', (
      select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
      from public.community_discover('gym', '', '', 5, 0) d
    ),
    'nearby', (
      select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
      from public.community_discover('area', '', '', 5, 0) d
    ),
    'incoming_requests', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'connection_id', c.id,
        'user_id', c.requester_id,
        'username', cp.username,
        'display_name', cp.display_name,
        'avatar_url', cp.avatar_url,
        'created_at', c.created_at
      ) order by c.created_at desc), '[]'::jsonb)
      from public.community_connections c
      join public.community_profiles cp on cp.user_id = c.requester_id
      where c.recipient_id = uid and c.status = 'pending'
        and not public.community_is_suspended(c.requester_id)
        and public.community_not_blocked(uid, c.requester_id)
    ),
    'connections', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'connection_id', c.id,
        'user_id', other.user_id,
        'username', other.username,
        'display_name', other.display_name,
        'avatar_url', other.avatar_url
      ) order by c.responded_at desc nulls last), '[]'::jsonb)
      from public.community_connections c
      join lateral (
        select cp.user_id, cp.username, cp.display_name, cp.avatar_url
        from public.community_profiles cp
        where cp.user_id = case when c.requester_id = uid then c.recipient_id else c.requester_id end
      ) other on true
      where c.status = 'accepted'
        and (c.requester_id = uid or c.recipient_id = uid)
        and public.community_not_blocked(uid, other.user_id)
      limit 5
    ),
    'feed', (
      select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
      from public.community_feed('all', 5, 0) f
    )
  );
end;
$$;

-- Single call the client uses on launch: the home payload plus the curated
-- area list it needs for gym/area selection.
create or replace function public.community_bootstrap()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  payload jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in to use Community.';
  end if;

  payload := public.community_home();
  return payload || jsonb_build_object(
    'areas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'city', a.city,
        'area', a.area,
        'nearby_group', a.nearby_group
      ) order by a.area), '[]'::jsonb)
      from public.community_areas a
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Gym selection, area selection, profile and preferences
-- ---------------------------------------------------------------------------

create or replace function public.community_search_gyms(
  p_query text default '',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  address text,
  city text,
  state text,
  country text,
  area text,
  verification_status text,
  member_count integer
)
language sql stable security definer set search_path = public, pg_temp as $$
  select g.id, g.name, g.address, g.city, g.state, g.country, g.area, g.verification_status,
         (select count(*)::integer from public.gym_memberships gm where gm.gym_id = g.id)
  from public.gyms g
  where (
      g.verification_status = 'verified'
      or g.submitted_by = auth.uid()
      or public.community_is_admin(auth.uid())
    )
    and (
      trim(coalesce(p_query, '')) = ''
      or lower(g.name) like '%' || lower(trim(p_query)) || '%'
      or lower(g.city) like '%' || lower(trim(p_query)) || '%'
      or lower(coalesce(g.area, '')) like '%' || lower(trim(p_query)) || '%'
    )
  order by (g.verification_status = 'verified') desc, g.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.community_request_gym(
  p_name text,
  p_city text,
  p_area text default null,
  p_address text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  existing public.gyms;
  created public.gyms;
  clean_name text := trim(coalesce(p_name, ''));
  clean_city text := trim(coalesce(p_city, ''));
begin
  if uid is null then
    raise exception 'Sign in to request a gym.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account cannot submit gyms right now.';
  end if;
  if char_length(clean_name) < 2 or char_length(clean_city) < 2 then
    raise exception 'Enter the gym name and city.';
  end if;

  select * into existing from public.gyms g
  where lower(g.name) = lower(clean_name)
    and lower(g.city) = lower(clean_city)
    and lower(coalesce(g.area, '')) = lower(trim(coalesce(p_area, '')))
  limit 1;

  if existing.id is not null then
    return jsonb_build_object('id', existing.id, 'status', existing.verification_status, 'created', false);
  end if;

  insert into public.gyms (name, city, area, address, submitted_by)
  values (clean_name, clean_city, nullif(trim(coalesce(p_area, '')), ''), nullif(trim(coalesce(p_address, '')), ''), uid)
  returning * into created;

  return jsonb_build_object('id', created.id, 'status', created.verification_status, 'created', true);
end;
$$;

create or replace function public.community_join_gym(p_gym_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  chosen public.gyms;
begin
  if uid is null then
    raise exception 'Sign in to join a gym community.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account cannot join a gym right now.';
  end if;

  select * into chosen from public.gyms g where g.id = p_gym_id;
  if chosen.id is null then
    raise exception 'That gym could not be found.';
  end if;
  if chosen.verification_status <> 'verified' and chosen.submitted_by <> uid then
    raise exception 'This gym is still awaiting review.';
  end if;

  insert into public.gym_memberships (user_id, gym_id)
  values (uid, chosen.id)
  on conflict (user_id) do update set gym_id = excluded.gym_id, created_at = now();

  insert into public.community_preferences (user_id, city, area)
  values (uid, chosen.city, chosen.area)
  on conflict (user_id) do update set city = excluded.city, area = excluded.area, updated_at = now();

  return jsonb_build_object(
    'gym_id', chosen.id,
    'gym_name', chosen.name,
    'city', chosen.city,
    'area', chosen.area,
    'verification_status', chosen.verification_status
  );
end;
$$;

create or replace function public.community_leave_gym()
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to leave a gym community.';
  end if;
  delete from public.gym_memberships where user_id = auth.uid();
end;
$$;

create or replace function public.community_set_area(p_city text, p_area text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  clean_city text := trim(coalesce(p_city, ''));
  clean_area text := trim(coalesce(p_area, ''));
begin
  if uid is null then
    raise exception 'Sign in to choose an area.';
  end if;
  if char_length(clean_city) < 2 or char_length(clean_area) < 2 then
    raise exception 'Enter a city and area.';
  end if;
  if char_length(clean_city) > 60 or char_length(clean_area) > 60 then
    raise exception 'That city or area name is too long.';
  end if;

  insert into public.community_preferences (user_id, city, area)
  values (uid, clean_city, clean_area)
  on conflict (user_id) do update set city = excluded.city, area = excluded.area, updated_at = now();
end;
$$;

create or replace function public.community_save_profile(
  p_username text,
  p_display_name text,
  p_bio text default null,
  p_interests text[] default '{}',
  p_categories text[] default '{}',
  p_avatar_url text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  base_name text;
  candidate text;
  fallback text;
begin
  if uid is null then
    raise exception 'Sign in to edit your community profile.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account is suspended and cannot change its community profile.';
  end if;

  base_name := lower(regexp_replace(trim(coalesce(p_username, '')), '[^a-zA-Z0-9_]', '', 'g'));
  if base_name = '' then
    base_name := 'member_' || substr(replace(uid::text, '-', ''), 1, 8);
  end if;
  if char_length(base_name) < 3 then
    raise exception 'Usernames need at least three letters or numbers.';
  end if;
  candidate := left(base_name, 24);
  fallback := left(base_name, 17) || '_' || substr(replace(uid::text, '-', ''), 1, 6);

  if exists (
    select 1 from public.community_profiles cp
    where lower(cp.username) = lower(candidate) and cp.user_id <> uid
  ) then
    candidate := fallback;
  end if;

  if exists (
    select 1 from public.community_profiles cp
    where lower(cp.username) = lower(candidate) and cp.user_id <> uid
  ) then
    raise exception 'That username is already taken.';
  end if;

  if char_length(trim(coalesce(p_display_name, ''))) < 2 then
    raise exception 'Add a display name.';
  end if;

  if p_avatar_url is not null and trim(p_avatar_url) <> '' and p_avatar_url !~* '^https://' then
    raise exception 'The photo address must use HTTPS.';
  end if;

  insert into public.community_profiles (
    user_id, username, display_name, bio, avatar_url, interests, workout_categories
  )
  values (
    uid, candidate, trim(p_display_name), nullif(trim(coalesce(p_bio, '')), ''),
    nullif(trim(coalesce(p_avatar_url, '')), ''),
    coalesce(p_interests, '{}'), coalesce(p_categories, '{}')
  )
  on conflict (user_id) do update set
    username = excluded.username,
    display_name = excluded.display_name,
    bio = excluded.bio,
    avatar_url = excluded.avatar_url,
    interests = excluded.interests,
    workout_categories = excluded.workout_categories,
    updated_at = now();

  insert into public.community_preferences (user_id)
  values (uid)
  on conflict (user_id) do nothing;

  return (select to_jsonb(cp) from public.community_profiles cp where cp.user_id = uid);
end;
$$;

create or replace function public.community_save_preferences(
  p_discoverable boolean,
  p_show_gym boolean,
  p_show_area boolean,
  p_nearby_discovery boolean,
  p_allow_connection_requests boolean,
  p_allow_messages boolean,
  p_notify_connections boolean,
  p_notify_messages boolean,
  p_notify_comments boolean,
  p_notify_likes boolean
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  result public.community_preferences;
begin
  if uid is null then
    raise exception 'Sign in to change community settings.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account is suspended.';
  end if;

  insert into public.community_preferences (
    user_id, discoverable, show_gym, show_area, nearby_discovery,
    allow_connection_requests, allow_messages,
    notify_connections, notify_messages, notify_comments, notify_likes
  )
  values (
    uid, coalesce(p_discoverable, false), coalesce(p_show_gym, true), coalesce(p_show_area, true),
    coalesce(p_nearby_discovery, false), coalesce(p_allow_connection_requests, true),
    coalesce(p_allow_messages, true), coalesce(p_notify_connections, true),
    coalesce(p_notify_messages, true), coalesce(p_notify_comments, true), coalesce(p_notify_likes, true)
  )
  on conflict (user_id) do update set
    discoverable = excluded.discoverable,
    show_gym = excluded.show_gym,
    show_area = excluded.show_area,
    nearby_discovery = excluded.nearby_discovery,
    allow_connection_requests = excluded.allow_connection_requests,
    allow_messages = excluded.allow_messages,
    notify_connections = excluded.notify_connections,
    notify_messages = excluded.notify_messages,
    notify_comments = excluded.notify_comments,
    notify_likes = excluded.notify_likes,
    updated_at = now()
  returning * into result;

  return to_jsonb(result);
end;
$$;

-- ---------------------------------------------------------------------------
-- Connections and blocks
-- ---------------------------------------------------------------------------

create or replace function public.community_send_connection_request(p_target uuid)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  target_pref public.community_preferences;
  existing public.community_connections;
  created public.community_connections;
  request_count integer;
begin
  if uid is null then
    raise exception 'Sign in to connect with members.';
  end if;
  if p_target is null or p_target = uid then
    raise exception 'Choose another member to connect with.';
  end if;
  if public.community_is_suspended(uid) or public.community_is_suspended(p_target) then
    raise exception 'This connection cannot be requested right now.';
  end if;
  if not public.community_not_blocked(uid, p_target) then
    raise exception 'This member is not available.';
  end if;
  if not public.community_age_compatible(uid, p_target) then
    raise exception 'Connections are limited to members in the same age group.';
  end if;
  if not public.community_can_view_profile(uid, p_target) then
    raise exception 'This member is not discoverable right now.';
  end if;

  select * into target_pref from public.community_preferences where user_id = p_target;
  if target_pref.user_id is null or not target_pref.allow_connection_requests then
    raise exception 'This member is not accepting connection requests right now.';
  end if;

  select * into existing from public.community_connections c
  where c.status in ('pending', 'accepted')
    and ((c.requester_id = uid and c.recipient_id = p_target)
      or (c.requester_id = p_target and c.recipient_id = uid))
  limit 1;
  if existing.id is not null then
    return jsonb_build_object('connection_id', existing.id, 'status', existing.status);
  end if;

  select count(*) into request_count
  from public.community_connections c
  where c.requester_id = uid and c.created_at > now() - interval '24 hours';
  if request_count >= 20 then
    raise exception 'Too many connection requests today. Try again tomorrow.';
  end if;

  insert into public.community_connections (requester_id, recipient_id, status)
  values (uid, p_target, 'pending')
  returning * into created;

  return jsonb_build_object('connection_id', created.id, 'status', created.status);
end;
$$;

create or replace function public.community_respond_connection(p_connection_id uuid, p_accept boolean)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  connection public.community_connections;
  conversation public.community_conversations;
begin
  if uid is null then
    raise exception 'Sign in to respond to a request.';
  end if;

  select * into connection from public.community_connections c
  where c.id = p_connection_id and c.recipient_id = uid and c.status = 'pending'
  for update;

  if connection.id is null then
    raise exception 'This request is no longer available.';
  end if;
  if not public.community_not_blocked(uid, connection.requester_id) then
    raise exception 'This request is not available.';
  end if;

  update public.community_connections
  set status = case when coalesce(p_accept, false) then 'accepted' else 'declined' end,
      responded_at = now()
  where id = connection.id
  returning * into connection;

  if connection.status = 'accepted' then
    insert into public.community_conversations (connection_id)
    values (connection.id)
    on conflict (connection_id) do nothing
    returning * into conversation;
  end if;

  return jsonb_build_object(
    'connection_id', connection.id,
    'status', connection.status,
    'conversation_id', conversation.id
  );
end;
$$;

create or replace function public.community_remove_connection(p_connection_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Sign in to remove a connection.';
  end if;
  delete from public.community_connections c
  where c.id = p_connection_id
    and (c.requester_id = uid or c.recipient_id = uid);
  if not found then
    raise exception 'That connection could not be found.';
  end if;
end;
$$;

create or replace function public.community_block(p_target uuid, p_block boolean)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Sign in to block or unblock members.';
  end if;
  if p_target is null or p_target = uid then
    raise exception 'Choose another member.';
  end if;

  if coalesce(p_block, false) then
    insert into public.community_blocks (blocker_id, blocked_id)
    values (uid, p_target)
    on conflict do nothing;
    delete from public.community_connections c
    where c.status = 'pending'
      and ((c.requester_id = uid and c.recipient_id = p_target)
        or (c.requester_id = p_target and c.recipient_id = uid));
  else
    delete from public.community_blocks b
    where b.blocker_id = uid and b.blocked_id = p_target;
  end if;
end;
$$;

create or replace function public.community_connections_list()
returns table (
  connection_id uuid,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  status text,
  direction text,
  conversation_id uuid,
  created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id,
         other.user_id,
         other.username,
         other.display_name,
         other.avatar_url,
         c.status,
         case when c.requester_id = auth.uid() then 'sent' else 'received' end,
         conv.id,
         c.created_at
  from public.community_connections c
  join lateral (
    select cp.user_id, cp.username, cp.display_name, cp.avatar_url
    from public.community_profiles cp
    where cp.user_id = case when c.requester_id = auth.uid() then c.recipient_id else c.requester_id end
  ) other on true
  left join public.community_conversations conv on conv.connection_id = c.id
  where (c.requester_id = auth.uid() or c.recipient_id = auth.uid())
    and c.status in ('pending', 'accepted')
    and public.community_not_blocked(auth.uid(), other.user_id)
  order by c.status = 'pending' desc, c.created_at desc;
$$;

create or replace function public.community_blocked_members()
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  blocked_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.blocked_id, cp.username, cp.display_name, cp.avatar_url, b.created_at
  from public.community_blocks b
  left join public.community_profiles cp on cp.user_id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

create or replace function public.community_public_profile(p_user uuid)
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select case when public.community_can_view_profile(auth.uid(), p_user) then
    jsonb_build_object(
      'user_id', cp.user_id,
      'username', cp.username,
      'display_name', cp.display_name,
      'bio', cp.bio,
      'avatar_url', cp.avatar_url,
      'interests', cp.interests,
      'workout_categories', cp.workout_categories,
      'joined_at', cp.created_at,
      'achievements_opt_in', cp.achievements_opt_in,
      'gym_name', case when pref.show_gym then g.name else null end,
      'city', case when pref.show_area then pref.city else null end,
      'area', case when pref.show_area then pref.area else null end,
      'connection_status', public.community_connection_status(auth.uid(), cp.user_id),
      'shared_gym', public.community_same_gym(auth.uid(), cp.user_id),
      'shared_area', public.community_area_compatible(auth.uid(), cp.user_id)
    )
  else null end
  from public.community_profiles cp
  join public.community_preferences pref on pref.user_id = cp.user_id
  left join public.gym_memberships gm on gm.user_id = cp.user_id
  left join public.gyms g on g.id = gm.gym_id
  where cp.user_id = p_user;
$$;

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------

create or replace function public.community_feed(
  p_filter text default 'all',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  author_id uuid,
  username text,
  display_name text,
  avatar_url text,
  content text,
  kind text,
  achievement_label text,
  like_count integer,
  comment_count integer,
  liked boolean,
  is_own boolean,
  shared_session jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select p.id,
         p.author_id,
         cp.username,
         cp.display_name,
         cp.avatar_url,
         p.content,
         p.kind,
         p.achievement_label,
         p.like_count,
         p.comment_count,
         exists (select 1 from public.community_likes l where l.post_id = p.id and l.user_id = auth.uid()),
         p.author_id = auth.uid(),
         case when p.session_id is not null then (
           select jsonb_build_object(
             'session_id', s.id,
             'title', s.title,
             'started_at', s.started_at,
             'duration_seconds', s.duration_seconds
           )
           from public.workout_sessions s
           where s.id = p.session_id and s.user_id = p.author_id
         ) else null end,
         p.created_at,
         p.updated_at
  from public.community_posts p
  join public.community_profiles cp on cp.user_id = p.author_id
  where (p.moderation_status = 'visible' or p.author_id = auth.uid() or public.community_is_admin(auth.uid()))
    and public.community_can_read_post(auth.uid(), p.id)
    and not exists (
      select 1 from public.community_hidden_posts h
      where h.post_id = p.id and h.user_id = auth.uid()
    )
    and (
      lower(coalesce(p_filter, 'all')) = 'all'
      or (lower(p_filter) = 'connections' and public.community_connected(auth.uid(), p.author_id))
      or (lower(p_filter) = 'gym' and public.community_same_gym(auth.uid(), p.author_id))
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.community_create_post(
  p_id uuid,
  p_content text,
  p_kind text default 'update',
  p_session_id uuid default null,
  p_achievement_label text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  clean_content text := trim(coalesce(p_content, ''));
  clean_kind text := lower(coalesce(p_kind, 'update'));
  created public.community_posts;
  post_count integer;
begin
  if uid is null then
    raise exception 'Sign in to post.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account cannot post right now.';
  end if;
  if char_length(clean_content) < 1 or char_length(clean_content) > 2000 then
    raise exception 'Posts need between 1 and 2000 characters.';
  end if;
  if clean_kind not in ('workout', 'milestone', 'achievement', 'update', 'motivation') then
    raise exception 'Choose a supported post type.';
  end if;
  if p_session_id is not null and not exists (
    select 1 from public.workout_sessions s
    where s.id = p_session_id and s.user_id = uid and s.status = 'completed'
  ) then
    raise exception 'Only your own completed sessions can be shared.';
  end if;

  select count(*) into post_count
  from public.community_posts p
  where p.author_id = uid and p.created_at > now() - interval '24 hours';
  if post_count >= 20 then
    raise exception 'You have reached today''s posting limit.';
  end if;

  insert into public.community_posts (id, author_id, content, kind, session_id, achievement_label)
  values (
    coalesce(p_id, gen_random_uuid()), uid, clean_content, clean_kind, p_session_id,
    nullif(trim(coalesce(p_achievement_label, '')), '')
  )
  returning * into created;

  return jsonb_build_object('id', created.id, 'created_at', created.created_at);
end;
$$;

create or replace function public.community_update_post(p_id uuid, p_content text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  clean_content text := trim(coalesce(p_content, ''));
begin
  if char_length(clean_content) < 1 or char_length(clean_content) > 2000 then
    raise exception 'Posts need between 1 and 2000 characters.';
  end if;
  update public.community_posts
  set content = clean_content, updated_at = now()
  where id = p_id and author_id = auth.uid();
  if not found then
    raise exception 'That post could not be edited.';
  end if;
end;
$$;

create or replace function public.community_delete_post(p_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.community_posts where id = p_id and author_id = auth.uid();
  if not found then
    raise exception 'That post could not be deleted.';
  end if;
end;
$$;

create or replace function public.community_toggle_like(p_post_id uuid, p_like boolean)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  counts record;
begin
  if uid is null then
    raise exception 'Sign in to like posts.';
  end if;
  if not public.community_can_read_post(uid, p_post_id) then
    raise exception 'That post is not available.';
  end if;

  if coalesce(p_like, true) then
    insert into public.community_likes (post_id, user_id)
    values (p_post_id, uid)
    on conflict do nothing;
  else
    delete from public.community_likes where post_id = p_post_id and user_id = uid;
  end if;

  select like_count, comment_count into counts from public.community_posts where id = p_post_id;
  return jsonb_build_object(
    'liked', exists (select 1 from public.community_likes where post_id = p_post_id and user_id = uid),
    'like_count', coalesce(counts.like_count, 0),
    'comment_count', coalesce(counts.comment_count, 0)
  );
end;
$$;

create or replace function public.community_comments_list(
  p_post_id uuid,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid,
  post_id uuid,
  author_id uuid,
  username text,
  display_name text,
  avatar_url text,
  content text,
  is_own boolean,
  created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id, c.post_id, c.author_id, cp.username, cp.display_name, cp.avatar_url,
         c.content, c.author_id = auth.uid(), c.created_at
  from public.community_comments c
  join public.community_profiles cp on cp.user_id = c.author_id
  where c.post_id = p_post_id
    and public.community_can_read_post(auth.uid(), c.post_id)
    and (c.moderation_status = 'visible' or c.author_id = auth.uid() or public.community_is_admin(auth.uid()))
  order by c.created_at asc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.community_add_comment(p_id uuid, p_post_id uuid, p_content text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  clean_content text := trim(coalesce(p_content, ''));
  created public.community_comments;
  comment_count integer;
begin
  if uid is null then
    raise exception 'Sign in to comment.';
  end if;
  if public.community_is_suspended(uid) then
    raise exception 'This account cannot comment right now.';
  end if;
  if char_length(clean_content) < 1 or char_length(clean_content) > 1000 then
    raise exception 'Comments need between 1 and 1000 characters.';
  end if;
  if not public.community_can_read_post(uid, p_post_id) then
    raise exception 'That post is not available.';
  end if;

  select count(*) into comment_count
  from public.community_comments c
  where c.author_id = uid and c.created_at > now() - interval '24 hours';
  if comment_count >= 100 then
    raise exception 'You have reached today''s comment limit.';
  end if;

  insert into public.community_comments (id, post_id, author_id, content)
  values (coalesce(p_id, gen_random_uuid()), p_post_id, uid, clean_content)
  returning * into created;

  return jsonb_build_object('id', created.id, 'created_at', created.created_at);
end;
$$;

create or replace function public.community_delete_comment(p_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.community_comments where id = p_id and author_id = auth.uid();
  if not found then
    raise exception 'That comment could not be deleted.';
  end if;
end;
$$;

create or replace function public.community_hide_post(p_post_id uuid, p_hidden boolean)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to hide posts.';
  end if;
  if coalesce(p_hidden, true) then
    insert into public.community_hidden_posts (user_id, post_id)
    values (auth.uid(), p_post_id)
    on conflict do nothing;
  else
    delete from public.community_hidden_posts
    where user_id = auth.uid() and post_id = p_post_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messaging
-- ---------------------------------------------------------------------------

create or replace function public.community_conversations_list()
returns table (
  conversation_id uuid,
  connection_id uuid,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count integer,
  muted boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select conv.id,
         c.id,
         other.user_id,
         cp.username,
         cp.display_name,
         cp.avatar_url,
         (select m.body from public.community_messages m where m.conversation_id = conv.id order by m.created_at desc limit 1),
         (select m.created_at from public.community_messages m where m.conversation_id = conv.id order by m.created_at desc limit 1),
         (
           select count(*)::integer
           from public.community_messages m
           left join public.community_conversation_reads r
             on r.conversation_id = conv.id and r.user_id = auth.uid()
           where m.conversation_id = conv.id
             and m.sender_id <> auth.uid()
             and m.created_at > coalesce(r.last_read_at, 'epoch'::timestamptz)
         ),
         exists (
           select 1 from public.community_conversation_mutes mute
           where mute.conversation_id = conv.id and mute.user_id = auth.uid()
         )
  from public.community_conversations conv
  join public.community_connections c on c.id = conv.connection_id
  join lateral (
    select cp.user_id, cp.username, cp.display_name, cp.avatar_url
    from public.community_profiles cp
    where cp.user_id = case when c.requester_id = auth.uid() then c.recipient_id else c.requester_id end
  ) other on true
  where c.status = 'accepted'
    and (c.requester_id = auth.uid() or c.recipient_id = auth.uid())
    and public.community_not_blocked(auth.uid(), other.user_id)
  order by last_message_at desc nulls last;
$$;

create or replace function public.community_messages_list(
  p_conversation_id uuid,
  p_before timestamptz default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  body text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.community_conversation_participant(p_conversation_id, auth.uid()) then
    raise exception 'That conversation is not available.';
  end if;

  return query
  select m.id, m.conversation_id, m.sender_id, m.body, m.created_at
  from public.community_messages m
  where m.conversation_id = p_conversation_id
    and (p_before is null or m.created_at < p_before)
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50);
end;
$$;

create or replace function public.community_send_message(
  p_id uuid,
  p_conversation_id uuid,
  p_body text
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  other_id uuid;
  clean_body text := trim(coalesce(p_body, ''));
  existing public.community_messages;
  created public.community_messages;
  recent_count integer;
  daily_count integer;
begin
  if uid is null then
    raise exception 'Sign in to send messages.';
  end if;
  if not public.community_conversation_participant(p_conversation_id, uid) then
    raise exception 'That conversation is not available.';
  end if;

  select case when c.requester_id = uid then c.recipient_id else c.requester_id end
  into other_id
  from public.community_conversations conv
  join public.community_connections c on c.id = conv.connection_id
  where conv.id = p_conversation_id;

  if not public.community_can_message(uid, other_id) then
    raise exception 'Messaging is not available for this connection.';
  end if;
  if char_length(clean_body) < 1 or char_length(clean_body) > 2000 then
    raise exception 'Messages need between 1 and 2000 characters.';
  end if;
  if clean_body ~* '(https?://|www\.|\m[a-z0-9-]+\.(com|net|org|io|co|ly|me)\M)' then
    raise exception 'Links are not supported in messages yet.';
  end if;

  select * into existing from public.community_messages m where m.id = p_id;
  if existing.id is not null then
    if existing.sender_id <> uid or existing.conversation_id <> p_conversation_id then
      raise exception 'That message id is already in use.';
    end if;
    return jsonb_build_object('id', existing.id, 'created_at', existing.created_at, 'duplicate', true);
  end if;

  select count(*) into recent_count
  from public.community_messages m
  where m.sender_id = uid and m.created_at > now() - interval '1 minute';
  if recent_count >= 20 then
    raise exception 'Slow down a moment before sending another message.';
  end if;

  select count(*) into daily_count
  from public.community_messages m
  where m.sender_id = uid and m.created_at > now() - interval '24 hours';
  if daily_count >= 500 then
    raise exception 'You have reached today''s message limit.';
  end if;

  insert into public.community_messages (id, conversation_id, sender_id, body)
  values (coalesce(p_id, gen_random_uuid()), p_conversation_id, uid, clean_body)
  returning * into created;

  return jsonb_build_object('id', created.id, 'created_at', created.created_at, 'duplicate', false);
end;
$$;

create or replace function public.community_mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.community_conversation_participant(p_conversation_id, auth.uid()) then
    raise exception 'That conversation is not available.';
  end if;
  insert into public.community_conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conversation_id, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set last_read_at = now();
end;
$$;

create or replace function public.community_mute_conversation(p_conversation_id uuid, p_muted boolean)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.community_conversation_participant(p_conversation_id, auth.uid()) then
    raise exception 'That conversation is not available.';
  end if;
  if coalesce(p_muted, true) then
    insert into public.community_conversation_mutes (conversation_id, user_id)
    values (p_conversation_id, auth.uid())
    on conflict do nothing;
  else
    delete from public.community_conversation_mutes
    where conversation_id = p_conversation_id and user_id = auth.uid();
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reports and notifications
-- ---------------------------------------------------------------------------

create or replace function public.community_report(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  clean_type text := lower(coalesce(p_target_type, ''));
  clean_reason text := lower(coalesce(p_reason, ''));
  recent integer;
  created public.community_reports;
  target_ok boolean := false;
begin
  if uid is null then
    raise exception 'Sign in to report content.';
  end if;
  if clean_reason not in ('harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'other') then
    raise exception 'Choose a reason for the report.';
  end if;
  if clean_type = 'profile' then
    select exists (select 1 from public.community_profiles cp where cp.user_id = p_target_id and cp.user_id <> uid)
    into target_ok;
  elsif clean_type = 'post' then
    select public.community_can_read_post(uid, p_target_id) into target_ok;
  elsif clean_type = 'comment' then
    select exists (
      select 1 from public.community_comments c
      where c.id = p_target_id and public.community_can_read_post(uid, c.post_id) and c.author_id <> uid
    ) into target_ok;
  elsif clean_type = 'message' then
    select exists (
      select 1 from public.community_messages m
      where m.id = p_target_id and m.sender_id <> uid
        and public.community_conversation_participant(m.conversation_id, uid)
    ) into target_ok;
  else
    raise exception 'Unsupported report type.';
  end if;

  if not target_ok then
    raise exception 'That content is not available to report.';
  end if;

  select count(*) into recent
  from public.community_reports r
  where r.reporter_id = uid and r.created_at > now() - interval '24 hours';
  if recent >= 10 then
    raise exception 'You have reached today''s report limit.';
  end if;

  insert into public.community_reports (reporter_id, target_type, target_id, reason, details)
  values (uid, clean_type, p_target_id, clean_reason, nullif(trim(coalesce(p_details, '')), ''))
  returning * into created;

  return jsonb_build_object('id', created.id, 'status', created.status);
end;
$$;

create or replace function public.community_notifications_list(
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid,
  kind text,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  actor_avatar_url text,
  entity_id uuid,
  post_id uuid,
  body text,
  read_at timestamptz,
  created_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $$
  select n.id, n.kind, n.actor_id, cp.username, cp.display_name, cp.avatar_url,
         n.entity_id, n.post_id, n.body, n.read_at, n.created_at
  from public.community_notifications n
  left join public.community_profiles cp on cp.user_id = n.actor_id
  where n.user_id = auth.uid()
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.community_mark_notifications_read(p_ids uuid[] default null)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to update notifications.';
  end if;
  update public.community_notifications
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null
    and (p_ids is null or id = any(p_ids));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin moderation (server-verified role only)
-- ---------------------------------------------------------------------------

create or replace function public.community_admin_reports()
returns table (
  id uuid,
  reporter_id uuid,
  reporter_username text,
  target_type text,
  target_id uuid,
  reason text,
  details text,
  status text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  return query
  select r.id, r.reporter_id, cp.username, r.target_type, r.target_id, r.reason, r.details, r.status, r.created_at
  from public.community_reports r
  left join public.community_profiles cp on cp.user_id = r.reporter_id
  order by r.status = 'open' desc, r.created_at desc
  limit 200;
end;
$$;

create or replace function public.community_admin_set_suspension(
  p_user uuid,
  p_suspended boolean,
  p_reason text default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  if p_user = auth.uid() then
    raise exception 'You cannot suspend your own account.';
  end if;

  insert into public.community_account_status (user_id, suspended, suspended_reason, suspended_at, suspended_by)
  values (p_user, coalesce(p_suspended, false),
          case when coalesce(p_suspended, false) then nullif(trim(coalesce(p_reason, '')), '') else null end,
          case when coalesce(p_suspended, false) then now() else null end,
          case when coalesce(p_suspended, false) then auth.uid() else null end)
  on conflict (user_id) do update set
    suspended = excluded.suspended,
    suspended_reason = excluded.suspended_reason,
    suspended_at = excluded.suspended_at,
    suspended_by = excluded.suspended_by,
    updated_at = now();

  insert into public.community_moderation_actions (admin_id, action, target_type, target_id, note)
  values (auth.uid(), case when coalesce(p_suspended, false) then 'suspend_user' else 'reinstate_user' end,
          'profile', p_user, nullif(trim(coalesce(p_reason, '')), ''));
end;
$$;

create or replace function public.community_admin_resolve_report(
  p_report_id uuid,
  p_action text,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  report public.community_reports;
  clean_action text := lower(coalesce(p_action, ''));
  target_author uuid;
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;

  select * into report from public.community_reports where id = p_report_id for update;
  if report.id is null then
    raise exception 'That report was not found.';
  end if;

  if clean_action = 'remove_content' then
    if report.target_type = 'post' then
      update public.community_posts set moderation_status = 'removed' where id = report.target_id;
    elsif report.target_type = 'comment' then
      update public.community_comments set moderation_status = 'removed' where id = report.target_id;
    else
      raise exception 'Only posts and comments can be removed from a report.';
    end if;
  elsif clean_action = 'suspend_user' then
    if report.target_type = 'profile' then
      target_author := report.target_id;
    elsif report.target_type = 'post' then
      select author_id into target_author from public.community_posts where id = report.target_id;
    elsif report.target_type = 'comment' then
      select author_id into target_author from public.community_comments where id = report.target_id;
    elsif report.target_type = 'message' then
      select sender_id into target_author from public.community_messages where id = report.target_id;
    end if;
    if target_author is null then
      raise exception 'The reported account could not be determined.';
    end if;
    perform public.community_admin_set_suspension(target_author, true, p_note);
  elsif clean_action not in ('dismiss', 'no_action') then
    raise exception 'Unsupported moderation action.';
  end if;

  update public.community_reports
  set status = case when clean_action in ('dismiss', 'no_action') then 'dismissed' else 'resolved' end,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      resolution_note = nullif(trim(coalesce(p_note, '')), '')
  where id = report.id;

  insert into public.community_moderation_actions (admin_id, action, target_type, target_id, note)
  values (auth.uid(), clean_action, report.target_type, report.target_id, nullif(trim(coalesce(p_note, '')), ''));
end;
$$;

create or replace function public.community_admin_gyms()
returns table (
  id uuid,
  name text,
  city text,
  area text,
  address text,
  verification_status text,
  submitted_by uuid,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  return query
  select g.id, g.name, g.city, g.area, g.address, g.verification_status, g.submitted_by, g.created_at
  from public.gyms g
  order by g.verification_status = 'pending' desc, g.created_at desc
  limit 200;
end;
$$;

create or replace function public.community_admin_review_gym(
  p_gym_id uuid,
  p_approve boolean,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  update public.gyms
  set verification_status = case when coalesce(p_approve, false) then 'verified' else 'rejected' end,
      verified_at = now(),
      verified_by = auth.uid()
  where id = p_gym_id;
  if not found then
    raise exception 'That gym could not be found.';
  end if;
  insert into public.community_moderation_actions (admin_id, action, target_type, target_id, note)
  values (auth.uid(), case when coalesce(p_approve, false) then 'verify_gym' else 'reject_gym' end,
          'gym', p_gym_id, nullif(trim(coalesce(p_note, '')), ''));
end;
$$;

create or replace function public.community_admin_audit()
returns table (
  id uuid,
  admin_id uuid,
  action text,
  target_type text,
  target_id uuid,
  note text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.community_is_admin(auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  return query
  select a.id, a.admin_id, a.action, a.target_type, a.target_id, a.note, a.created_at
  from public.community_moderation_actions a
  order by a.created_at desc
  limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers: counters, age band, notifications
-- ---------------------------------------------------------------------------

create or replace function public.community_sync_age_band()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.community_account_status (user_id, age_band)
  values (new.id, case when new.age is null then 'unknown' when new.age < 18 then 'minor' else 'adult' end)
  on conflict (user_id) do update set age_band = excluded.age_band, updated_at = now();
  return new;
end;
$$;

drop trigger if exists community_profiles_age_band on public.profiles;
create trigger community_profiles_age_band
after insert or update of age on public.profiles
for each row execute function public.community_sync_age_band();

create or replace function public.community_like_counter()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.community_posts set like_count = like_count + 1 where id = new.post_id;
    return new;
  end if;
  update public.community_posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

drop trigger if exists community_likes_counter on public.community_likes;
create trigger community_likes_counter
after insert or delete on public.community_likes
for each row execute function public.community_like_counter();

create or replace function public.community_comment_counter()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    update public.community_posts set comment_count = comment_count + 1 where id = new.post_id;
    return new;
  end if;
  update public.community_posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

drop trigger if exists community_comments_counter on public.community_comments;
create trigger community_comments_counter
after insert or delete on public.community_comments
for each row execute function public.community_comment_counter();

create or replace function public.community_notify(
  p_user uuid,
  p_kind text,
  p_actor uuid,
  p_entity uuid,
  p_post uuid,
  p_body text
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_user is null or p_user = p_actor then
    return;
  end if;
  if public.community_is_suspended(p_user) or public.community_is_suspended(p_actor) then
    return;
  end if;
  if not public.community_not_blocked(p_user, p_actor) then
    return;
  end if;
  insert into public.community_notifications (user_id, kind, actor_id, entity_id, post_id, body)
  values (p_user, p_kind, p_actor, p_entity, p_post, left(p_body, 160));
end;
$$;

create or replace function public.community_connection_notifications()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    if coalesce((select notify_connections from public.community_preferences where user_id = new.recipient_id), true) then
      perform public.community_notify(new.recipient_id, 'connection_request', new.requester_id, new.id, null,
        'sent you a connection request.');
    end if;
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status <> 'accepted' then
    if coalesce((select notify_connections from public.community_preferences where user_id = new.requester_id), true) then
      perform public.community_notify(new.requester_id, 'connection_accepted', new.recipient_id, new.id, null,
        'accepted your connection request.');
    end if;
    insert into public.community_notifications (user_id, kind, actor_id, entity_id, body)
    values (new.recipient_id, 'connection_accepted', new.requester_id, new.id, 'You are now connected.')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists community_connections_notify on public.community_connections;
create trigger community_connections_notify
after insert or update of status on public.community_connections
for each row execute function public.community_connection_notifications();

create or replace function public.community_message_notification()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  recipient uuid;
begin
  select case when c.requester_id = new.sender_id then c.recipient_id else c.requester_id end
  into recipient
  from public.community_conversations conv
  join public.community_connections c on c.id = conv.connection_id
  where conv.id = new.conversation_id;

  if recipient is null then
    return new;
  end if;
  if exists (
    select 1 from public.community_conversation_mutes mute
    where mute.conversation_id = new.conversation_id and mute.user_id = recipient
  ) then
    return new;
  end if;
  if coalesce((select notify_messages from public.community_preferences where user_id = recipient), true) then
    perform public.community_notify(recipient, 'message', new.sender_id, new.id, null, 'sent you a message.');
  end if;
  return new;
end;
$$;

drop trigger if exists community_messages_notify on public.community_messages;
create trigger community_messages_notify
after insert on public.community_messages
for each row execute function public.community_message_notification();

create or replace function public.community_like_notification()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  author uuid;
begin
  select author_id into author from public.community_posts where id = new.post_id;
  if author is not null and coalesce((select notify_likes from public.community_preferences where user_id = author), true) then
    perform public.community_notify(author, 'post_like', new.user_id, new.post_id, new.post_id, 'liked your post.');
  end if;
  return new;
end;
$$;

drop trigger if exists community_likes_notify on public.community_likes;
create trigger community_likes_notify
after insert on public.community_likes
for each row execute function public.community_like_notification();

create or replace function public.community_comment_notification()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  author uuid;
begin
  select author_id into author from public.community_posts where id = new.post_id;
  if author is not null and coalesce((select notify_comments from public.community_preferences where user_id = author), true) then
    perform public.community_notify(author, 'post_comment', new.author_id, new.id, new.post_id, 'commented on your post.');
  end if;
  return new;
end;
$$;

drop trigger if exists community_comments_notify on public.community_comments;
create trigger community_comments_notify
after insert on public.community_comments
for each row execute function public.community_comment_notification();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.community_areas enable row level security;
alter table public.gyms enable row level security;
alter table public.community_profiles enable row level security;
alter table public.community_preferences enable row level security;
alter table public.gym_memberships enable row level security;
alter table public.community_account_status enable row level security;
alter table public.community_blocks enable row level security;
alter table public.community_connections enable row level security;
alter table public.community_conversations enable row level security;
alter table public.community_messages enable row level security;
alter table public.community_conversation_reads enable row level security;
alter table public.community_conversation_mutes enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_likes enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_hidden_posts enable row level security;
alter table public.community_reports enable row level security;
alter table public.community_admins enable row level security;
alter table public.community_moderation_actions enable row level security;
alter table public.community_notifications enable row level security;

drop policy if exists community_areas_read on public.community_areas;
create policy community_areas_read on public.community_areas
  for select to authenticated using (true);

drop policy if exists gyms_read on public.gyms;
create policy gyms_read on public.gyms
  for select to authenticated using (
    verification_status = 'verified'
    or submitted_by = auth.uid()
    or public.community_is_admin(auth.uid())
  );

drop policy if exists community_profiles_read on public.community_profiles;
create policy community_profiles_read on public.community_profiles
  for select to authenticated using (public.community_can_view_profile(auth.uid(), user_id));

drop policy if exists community_preferences_read on public.community_preferences;
create policy community_preferences_read on public.community_preferences
  for select to authenticated using (user_id = auth.uid());

drop policy if exists gym_memberships_read on public.gym_memberships;
create policy gym_memberships_read on public.gym_memberships
  for select to authenticated using (user_id = auth.uid());

drop policy if exists community_account_status_read on public.community_account_status;
create policy community_account_status_read on public.community_account_status
  for select to authenticated using (user_id = auth.uid());

drop policy if exists community_blocks_read on public.community_blocks;
create policy community_blocks_read on public.community_blocks
  for select to authenticated using (blocker_id = auth.uid() or blocked_id = auth.uid());

drop policy if exists community_connections_read on public.community_connections;
create policy community_connections_read on public.community_connections
  for select to authenticated using (requester_id = auth.uid() or recipient_id = auth.uid());

drop policy if exists community_conversations_read on public.community_conversations;
create policy community_conversations_read on public.community_conversations
  for select to authenticated using (public.community_conversation_participant(id, auth.uid()));

drop policy if exists community_messages_read on public.community_messages;
create policy community_messages_read on public.community_messages
  for select to authenticated using (public.community_conversation_participant(conversation_id, auth.uid()));

drop policy if exists community_conversation_reads_read on public.community_conversation_reads;
create policy community_conversation_reads_read on public.community_conversation_reads
  for select to authenticated using (user_id = auth.uid());

drop policy if exists community_conversation_mutes_read on public.community_conversation_mutes;
create policy community_conversation_mutes_read on public.community_conversation_mutes
  for select to authenticated using (user_id = auth.uid());

drop policy if exists community_posts_read on public.community_posts;
create policy community_posts_read on public.community_posts
  for select to authenticated using (
    author_id = auth.uid()
    or public.community_is_admin(auth.uid())
    or (moderation_status = 'visible' and public.community_can_read_post(auth.uid(), id))
  );

drop policy if exists community_likes_read on public.community_likes;
create policy community_likes_read on public.community_likes
  for select to authenticated using (public.community_can_read_post(auth.uid(), post_id));

drop policy if exists community_comments_read on public.community_comments;
create policy community_comments_read on public.community_comments
  for select to authenticated using (
    public.community_can_read_post(auth.uid(), post_id)
    and (moderation_status = 'visible' or author_id = auth.uid() or public.community_is_admin(auth.uid()))
  );

drop policy if exists community_hidden_posts_read on public.community_hidden_posts;
create policy community_hidden_posts_read on public.community_hidden_posts
  for select to authenticated using (user_id = auth.uid());

drop policy if exists community_reports_read on public.community_reports;
create policy community_reports_read on public.community_reports
  for select to authenticated using (reporter_id = auth.uid() or public.community_is_admin(auth.uid()));

drop policy if exists community_notifications_read on public.community_notifications;
create policy community_notifications_read on public.community_notifications
  for select to authenticated using (user_id = auth.uid());

-- No policies exist for community_admins or community_moderation_actions:
-- only security-definer admin functions can touch them.

-- Direct reads only. Every write goes through a validated function above.
grant select on public.community_areas, public.gyms, public.community_profiles,
  public.community_preferences, public.gym_memberships, public.community_account_status,
  public.community_blocks, public.community_connections, public.community_conversations,
  public.community_messages, public.community_conversation_reads,
  public.community_conversation_mutes, public.community_posts, public.community_likes,
  public.community_comments, public.community_hidden_posts, public.community_reports,
  public.community_notifications
to authenticated;

revoke all on public.community_admins, public.community_moderation_actions from anon, authenticated;

grant execute on function public.community_bootstrap() to authenticated;
grant execute on function public.community_discover(text, text, text, integer, integer) to authenticated;
grant execute on function public.community_home() to authenticated;
grant execute on function public.community_search_gyms(text, integer, integer) to authenticated;
grant execute on function public.community_request_gym(text, text, text, text) to authenticated;
grant execute on function public.community_join_gym(uuid) to authenticated;
grant execute on function public.community_leave_gym() to authenticated;
grant execute on function public.community_set_area(text, text) to authenticated;
grant execute on function public.community_save_profile(text, text, text, text[], text[], text) to authenticated;
grant execute on function public.community_save_preferences(boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.community_send_connection_request(uuid) to authenticated;
grant execute on function public.community_respond_connection(uuid, boolean) to authenticated;
grant execute on function public.community_remove_connection(uuid) to authenticated;
grant execute on function public.community_block(uuid, boolean) to authenticated;
grant execute on function public.community_connections_list() to authenticated;
grant execute on function public.community_blocked_members() to authenticated;
grant execute on function public.community_public_profile(uuid) to authenticated;
grant execute on function public.community_feed(text, integer, integer) to authenticated;
grant execute on function public.community_create_post(uuid, text, text, uuid, text) to authenticated;
grant execute on function public.community_update_post(uuid, text) to authenticated;
grant execute on function public.community_delete_post(uuid) to authenticated;
grant execute on function public.community_toggle_like(uuid, boolean) to authenticated;
grant execute on function public.community_comments_list(uuid, integer, integer) to authenticated;
grant execute on function public.community_add_comment(uuid, uuid, text) to authenticated;
grant execute on function public.community_delete_comment(uuid) to authenticated;
grant execute on function public.community_hide_post(uuid, boolean) to authenticated;
grant execute on function public.community_conversations_list() to authenticated;
grant execute on function public.community_messages_list(uuid, timestamptz, integer) to authenticated;
grant execute on function public.community_send_message(uuid, uuid, text) to authenticated;
grant execute on function public.community_mark_conversation_read(uuid) to authenticated;
grant execute on function public.community_mute_conversation(uuid, boolean) to authenticated;
grant execute on function public.community_report(text, uuid, text, text) to authenticated;
grant execute on function public.community_notifications_list(integer, integer) to authenticated;
grant execute on function public.community_mark_notifications_read(uuid[]) to authenticated;
grant execute on function public.community_admin_reports() to authenticated;
grant execute on function public.community_admin_set_suspension(uuid, boolean, text) to authenticated;
grant execute on function public.community_admin_resolve_report(uuid, text, text) to authenticated;
grant execute on function public.community_admin_gyms() to authenticated;
grant execute on function public.community_admin_review_gym(uuid, boolean, text) to authenticated;
grant execute on function public.community_admin_audit() to authenticated;

-- ---------------------------------------------------------------------------
-- Avatars: public read, owner-only writes in a per-user folder
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('community-avatars', 'community-avatars', true)
on conflict (id) do nothing;

drop policy if exists community_avatars_read on storage.objects;
create policy community_avatars_read on storage.objects
  for select using (bucket_id = 'community-avatars');

drop policy if exists community_avatars_insert on storage.objects;
create policy community_avatars_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'community-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists community_avatars_update on storage.objects;
create policy community_avatars_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'community-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'community-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists community_avatars_delete on storage.objects;
create policy community_avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'community-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Realtime: one notification stream per signed-in user
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.community_notifications;
    exception when duplicate_object then
      null;
    end;
  end if;
end;
$$;
