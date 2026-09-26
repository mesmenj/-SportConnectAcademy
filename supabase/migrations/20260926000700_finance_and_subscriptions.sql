-- Sport Connect Academy — local greenfield foundation, phase 3A.
CREATE TABLE public.academy_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  player_id uuid,
  package_id uuid,
  amount numeric(18,2) NOT NULL,
  currency text NOT NULL CHECK (currency IN ('AED', 'XAF', 'EUR', 'USD', 'MAD')),
  CHECK (amount > 0 AND amount <> 'NaN'::numeric),
  CHECK (currency <> 'XAF' OR amount = trunc(amount)),
  method text NOT NULL CHECK (method IN ('CASH', 'CARD', 'PAYMENT_LINK', 'BANK_TRANSFER')),
  status text NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED')),
  origin text NOT NULL CHECK (origin IN ('CASH_CONFIRMATION', 'ADMIN_DECLARATION')),
  confirmed_at timestamptz,
  confirmed_by uuid,
  created_by uuid,
  external_reference text,
  UNIQUE (academy_id, player_id, id),
  operation_id uuid NOT NULL UNIQUE,
  CHECK (package_id IS NULL OR player_id IS NOT NULL),
  CHECK (status <> 'CONFIRMED' OR confirmed_at IS NOT NULL)
);

CREATE UNIQUE INDEX academy_payments_confirmed_package ON public.academy_payments (package_id) WHERE status = 'CONFIRMED';
CREATE TABLE public.academy_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  player_id uuid,
  payment_id uuid,
  number text NOT NULL CHECK (length(btrim(number)) BETWEEN 1 AND 100),
  issued_at timestamptz NOT NULL,
  amount numeric(18,2) NOT NULL,
  currency text NOT NULL CHECK (currency IN ('AED', 'XAF', 'EUR', 'USD', 'MAD')),
  CHECK (amount > 0 AND amount <> 'NaN'::numeric),
  CHECK (currency <> 'XAF' OR amount = trunc(amount)),
  status text NOT NULL CHECK (status IN ('PAID', 'UNPAID')),
  source text NOT NULL CHECK (source IN ('CASH', 'MANUAL')),
  payment_method text NOT NULL CHECK (payment_method IN ('CASH', 'CARD', 'PAYMENT_LINK', 'BANK_TRANSFER')),
  issuer_snapshot jsonb NOT NULL CHECK (jsonb_typeof(issuer_snapshot) = 'object' AND octet_length(issuer_snapshot::text) <= 65536),
  customer_snapshot jsonb NOT NULL CHECK (jsonb_typeof(customer_snapshot) = 'object' AND octet_length(customer_snapshot::text) <= 65536),
  player_name_snapshot text,
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  session_count integer NOT NULL DEFAULT 0 CHECK (session_count >= 0),
  activity text CHECK (activity IN ('TENNIS', 'PADEL')),
  created_by uuid,
  UNIQUE (academy_id, number),
  UNIQUE (payment_id),
  operation_id uuid NOT NULL UNIQUE
);

CREATE TABLE public.tournaments (
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
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 150),
  venue text NOT NULL CHECK (length(btrim(venue)) BETWEEN 1 AND 200),
  category text NOT NULL CHECK (length(btrim(category)) BETWEEN 1 AND 100),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  starts_at timestamptz NOT NULL,
  capacity integer NOT NULL CHECK (capacity BETWEEN 2 AND 10000),
  status text NOT NULL CHECK (status IN ('OPEN', 'CLOSED', 'DELETED')),
  published boolean NOT NULL DEFAULT false CHECK (NOT published),
  cover_asset_id uuid
);

CREATE TABLE public.platform_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  code text NOT NULL CHECK (length(btrim(code)) BETWEEN 1 AND 100),
  version integer NOT NULL CHECK (version > 0),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  active boolean NOT NULL DEFAULT true,
  description text NOT NULL DEFAULT '',
  UNIQUE (code, version)
);

CREATE TABLE public.academy_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  plan_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('TRIALING', 'ACTIVE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  trial_ends_at timestamptz,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  CHECK (trial_ends_at IS NULL OR trial_ends_at > starts_at),
  CHECK (status <> 'TRIALING' OR trial_ends_at IS NOT NULL)
);

CREATE UNIQUE INDEX academy_subscriptions_current ON public.academy_subscriptions (academy_id) WHERE status IN ('TRIALING','ACTIVE','SUSPENDED');
CREATE TABLE private.subscription_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  operation_id uuid NOT NULL,
  effect_key text NOT NULL CHECK (length(btrim(effect_key)) > 0),
  UNIQUE (operation_id, effect_key),
  actor_kind text NOT NULL CHECK (actor_kind IN ('USER','SYSTEM')),
  actor_user_id uuid,
  actor_ref text NOT NULL CHECK (length(btrim(actor_ref)) > 0),
  CHECK ((actor_kind = 'USER' AND actor_user_id IS NOT NULL AND actor_ref = actor_user_id::text) OR (actor_kind = 'SYSTEM' AND actor_user_id IS NULL)),
  subscription_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('CREATED', 'ACTIVATED', 'SUSPENDED', 'RESUMED', 'CANCELLED', 'EXPIRED', 'PLAN_CHANGED')),
  before_status text CHECK (before_status IN ('TRIALING', 'ACTIVE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')),
  after_status text NOT NULL CHECK (after_status IN ('TRIALING', 'ACTIVE', 'SUSPENDED', 'CANCELLED', 'EXPIRED')),
  effective_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 1000),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object' AND octet_length(metadata::text) <= 65536)
);
