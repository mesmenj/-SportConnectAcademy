-- Sport Connect Academy — local greenfield foundation, phase 3A.
CREATE TABLE public.communities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  active boolean NOT NULL DEFAULT true
);

CREATE UNIQUE INDEX communities_active_name ON public.communities (academy_id, name) WHERE deleted_at IS NULL;
CREATE TABLE public.community_courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  community_id uuid NOT NULL,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 500),
  active boolean NOT NULL DEFAULT true
);

CREATE UNIQUE INDEX community_courses_active_name ON public.community_courses (community_id, name) WHERE deleted_at IS NULL;
CREATE TABLE public.players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  first_name text NOT NULL CHECK (length(btrim(first_name)) BETWEEN 1 AND 80),
  last_name text NOT NULL CHECK (length(btrim(last_name)) BETWEEN 1 AND 80),
  reported_age integer CHECK (reported_age BETWEEN 3 AND 80),
  age_recorded_at timestamptz,
  birth_date date,
  gender text CHECK (gender IN ('FEMALE', 'MALE', 'OTHER')),
  status text NOT NULL CHECK (status IN ('ACTIVE', 'PENDING_PAYMENT', 'INACTIVE')),
  community_id uuid,
  CHECK ((reported_age IS NULL) = (age_recorded_at IS NULL))
);

CREATE TABLE public.player_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  player_id uuid NOT NULL,
  user_id uuid NOT NULL,
  relationship text NOT NULL CHECK (relationship IN ('SELF', 'GUARDIAN')),
  is_primary boolean NOT NULL DEFAULT false,
  is_financial_contact boolean NOT NULL DEFAULT false,
  assigned_by uuid,
  revoked_at timestamptz,
  revoked_by uuid,
  CHECK (revoked_by IS NULL OR revoked_at IS NOT NULL)
);

CREATE UNIQUE INDEX player_links_active_pair ON public.player_links (player_id, user_id) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX player_links_active_self ON public.player_links (player_id) WHERE revoked_at IS NULL AND relationship = 'SELF';
CREATE UNIQUE INDEX player_links_active_primary ON public.player_links (player_id) WHERE revoked_at IS NULL AND is_primary;
CREATE UNIQUE INDEX player_links_active_financial ON public.player_links (player_id) WHERE revoked_at IS NULL AND is_financial_contact;
CREATE TABLE public.coaches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  membership_id uuid NOT NULL UNIQUE,
  specialties text[] NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE public.stadiums (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  address text NOT NULL CHECK (length(address) <= 500),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE public.courts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL),
  stadium_id uuid NOT NULL,
  number integer NOT NULL CHECK (number BETWEEN 1 AND 100),
  label text,
  active boolean NOT NULL DEFAULT true,
  UNIQUE (stadium_id, number),
  UNIQUE (academy_id, stadium_id, id)
);
