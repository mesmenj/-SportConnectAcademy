-- Sport Connect Academy — local greenfield foundation, phase 3A.
CREATE TABLE public.academy_roles (
  code text NOT NULL CHECK (code IN ('ACADEMY_OWNER', 'ACADEMY_ADMIN', 'MANAGER', 'STAFF', 'COACH', 'STUDENT', 'PARENT')) PRIMARY KEY,
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 300)
);

CREATE TABLE public.academy_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  user_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('INVITED', 'ACTIVE', 'SUSPENDED')),
  joined_at timestamptz,
  UNIQUE (academy_id, user_id)
);

CREATE TABLE private.academy_membership_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  membership_id uuid NOT NULL,
  role_code text NOT NULL,
  granted_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  CHECK (revoked_by IS NULL OR revoked_at IS NOT NULL)
);

CREATE UNIQUE INDEX academy_membership_roles_active ON private.academy_membership_roles (membership_id, role_code) WHERE revoked_at IS NULL;
CREATE TABLE private.academy_role_permissions (
  role_code text NOT NULL,
  permission_code text NOT NULL,
  PRIMARY KEY (role_code, permission_code)
);

CREATE TABLE private.academy_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  email text NOT NULL CHECK (length(btrim(email)) BETWEEN 1 AND 320),
  requested_role_codes text[] NOT NULL,
  invited_user_id uuid,
  membership_id uuid,
  requested_by uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('REQUESTED', 'PROVISIONING', 'SENT', 'ACCEPTED', 'EXPIRED', 'FAILED', 'REVOKED')),
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  last_requested_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  last_error_code text,
  token_digest text UNIQUE CHECK (token_digest ~ '^[0-9a-f]{64}$'),
  operation_id uuid NOT NULL UNIQUE,
  CHECK (email = lower(btrim(email)) AND position('@' IN email) > 1),
  CHECK (cardinality(requested_role_codes) > 0 AND array_position(requested_role_codes, NULL) IS NULL AND requested_role_codes <@ ARRAY['ACADEMY_OWNER','ACADEMY_ADMIN','MANAGER','STAFF','COACH','STUDENT','PARENT']::text[]),
  CHECK (status <> 'ACCEPTED' OR (accepted_at IS NOT NULL AND invited_user_id IS NOT NULL AND membership_id IS NOT NULL))
);

CREATE UNIQUE INDEX academy_invitations_active_email ON private.academy_invitations (academy_id, email) WHERE status IN ('REQUESTED','PROVISIONING','SENT');
