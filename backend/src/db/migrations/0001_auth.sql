-- Accounts, sessions and tokens. Community tables arrive in a later migration.

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text NOT NULL,
    password_hash text NOT NULL,
    display_name text,
    email_verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Emails are compared case-insensitively.
CREATE UNIQUE INDEX users_email_lower_unique ON users (lower(email));

CREATE TABLE sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    access_token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    last_seen_at timestamptz
);

CREATE INDEX sessions_user_idx ON sessions (user_id);

CREATE TABLE refresh_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    rotated_at timestamptz,
    revoked_at timestamptz,
    replaced_by uuid REFERENCES refresh_tokens(id) ON DELETE SET NULL
);

CREATE INDEX refresh_tokens_session_idx ON refresh_tokens (session_id);

CREATE TABLE email_verifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz
);

CREATE TABLE password_resets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz
);
