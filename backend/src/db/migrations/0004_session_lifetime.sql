-- A session used to expire with its access token, which made the 30-day
-- refresh token unusable after the first hour. Access and session lifetimes are
-- now independent: access_expires_at gates requests, expires_at gates the
-- session and its refresh tokens.

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS access_expires_at timestamptz;

UPDATE sessions s
   SET access_expires_at = s.expires_at
 WHERE s.access_expires_at IS NULL;

ALTER TABLE sessions ALTER COLUMN access_expires_at SET NOT NULL;

-- Existing sessions were stamped with the access-token lifetime. Give them the
-- lifetime of the refresh tokens already issued instead of shortening them.
UPDATE sessions s
   SET expires_at = GREATEST(
         s.expires_at,
         COALESCE(
           (SELECT max(rt.expires_at) FROM refresh_tokens rt WHERE rt.session_id = s.id),
           s.expires_at
         )
       );

CREATE INDEX IF NOT EXISTS sessions_access_expires_idx ON sessions (access_expires_at);
