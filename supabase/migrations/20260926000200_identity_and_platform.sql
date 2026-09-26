-- Sport Connect Academy — local greenfield foundation, phase 3A.
CREATE TABLE public.user_profiles (
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  id uuid PRIMARY KEY,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 160),
  phone text CHECK (length(phone) <= 40),
  preferred_language text NOT NULL CHECK (preferred_language IN ('FR', 'EN')),
  status text NOT NULL CHECK (status IN ('ACTIVE', 'SUSPENDED'))
);

CREATE TABLE public.permissions (
  code text NOT NULL CHECK (length(btrim(code)) BETWEEN 1 AND 100) PRIMARY KEY,
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 300)
);

CREATE TABLE public.platform_roles (
  code text NOT NULL CHECK (code IN ('SUPER_ADMIN', 'PLATFORM_ADMIN')) PRIMARY KEY,
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 300)
);

CREATE TABLE private.platform_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  user_id uuid NOT NULL,
  role_code text NOT NULL,
  granted_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  CHECK (revoked_by IS NULL OR revoked_at IS NOT NULL)
);

CREATE UNIQUE INDEX platform_user_roles_active ON private.platform_user_roles (user_id, role_code) WHERE revoked_at IS NULL;
CREATE TABLE private.platform_role_permissions (
  role_code text NOT NULL,
  permission_code text NOT NULL,
  PRIMARY KEY (role_code, permission_code)
);

CREATE TABLE public.academies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  city text NOT NULL CHECK (length(btrim(city)) BETWEEN 1 AND 160),
  country text NOT NULL CHECK (length(btrim(country)) BETWEEN 1 AND 160),
  address text CHECK (length(address) <= 500),
  timezone text NOT NULL CHECK (length(btrim(timezone)) BETWEEN 1 AND 100),
  default_language text NOT NULL CHECK (default_language IN ('FR', 'EN')),
  status text NOT NULL CHECK (status IN ('ACTIVE', 'SUSPENDED', 'ARCHIVED')),
  catalog_published boolean NOT NULL DEFAULT false CHECK (NOT catalog_published),
  logo_asset_id uuid
);
