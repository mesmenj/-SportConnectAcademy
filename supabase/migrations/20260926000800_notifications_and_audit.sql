-- Sport Connect Academy — local greenfield foundation, phase 3A.
CREATE TABLE private.academy_notification_recipients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academy_id uuid NOT NULL,
  UNIQUE (academy_id, id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  email text NOT NULL CHECK (length(btrim(email)) BETWEEN 1 AND 320),
  display_name text,
  active boolean NOT NULL DEFAULT true,
  updated_by uuid NOT NULL,
  UNIQUE (academy_id, email),
  CHECK (email = lower(btrim(email)) AND position('@' IN email) > 1)
);

CREATE TABLE private.notification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope text NOT NULL CHECK (scope IN ('TENANT','PLATFORM')),
  academy_id uuid,
  CHECK ((scope = 'TENANT' AND academy_id IS NOT NULL) OR (scope = 'PLATFORM' AND academy_id IS NULL)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  operation_id uuid NOT NULL,
  effect_key text NOT NULL CHECK (length(btrim(effect_key)) > 0),
  UNIQUE (operation_id, effect_key),
  booking_id uuid,
  invitation_id uuid,
  subject_user_id uuid,
  event_type text NOT NULL CHECK (event_type IN ('BOOKING_REQUESTED', 'BOOKING_SCHEDULED', 'BOOKING_APPROVED', 'BOOKING_REJECTED', 'BOOKING_CANCELLED', 'BOOKING_REMINDER', 'MEMBERSHIP_INVITED', 'INVITATION_RESENT')),
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
  snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object' AND octet_length(snapshot::text) <= 65536),
  status text NOT NULL CHECK (status IN ('QUEUED', 'PROCESSING', 'EXPANDED', 'FAILED')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at timestamptz,
  lease_token uuid,
  lease_until timestamptz,
  last_error_code text,
  expanded_at timestamptz,
  purge_at timestamptz,
  UNIQUE (academy_id, id),
  CHECK ((booking_id IS NULL AND invitation_id IS NULL) OR scope = 'TENANT'),
  CHECK (booking_id IS NULL OR invitation_id IS NULL),
  CHECK (status <> 'PROCESSING' OR (lease_token IS NOT NULL AND lease_until IS NOT NULL AND next_attempt_at IS NOT NULL AND next_attempt_at = lease_until))
);

CREATE TABLE private.notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope text NOT NULL CHECK (scope IN ('TENANT','PLATFORM')),
  academy_id uuid,
  CHECK ((scope = 'TENANT' AND academy_id IS NOT NULL) OR (scope = 'PLATFORM' AND academy_id IS NULL)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  event_id uuid NOT NULL,
  recipient_email text NOT NULL CHECK (length(btrim(recipient_email)) BETWEEN 1 AND 320),
  recipient_name text,
  template text NOT NULL CHECK (length(btrim(template)) BETWEEN 1 AND 100),
  language text NOT NULL CHECK (language IN ('FR', 'EN')),
  status text NOT NULL CHECK (status IN ('QUEUED', 'SENDING', 'RETRY', 'ACCEPTED', 'DELIVERED', 'DEFERRED', 'BOUNCED', 'BLOCKED', 'COMPLAINED', 'FAILED', 'SKIPPED', 'UNKNOWN')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  idempotency_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  lease_token uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz,
  expires_at timestamptz,
  uncertain_since timestamptz,
  provider text NOT NULL CHECK (provider IN ('BREVO')),
  provider_message_id text,
  provider_event_at timestamptz,
  accepted_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  retryable boolean NOT NULL DEFAULT false,
  UNIQUE (event_id, recipient_email),
  UNIQUE (academy_id, id),
  CHECK (status <> 'SENDING' OR (lease_token IS NOT NULL AND lease_until IS NOT NULL AND next_attempt_at IS NOT NULL AND next_attempt_at = lease_until)),
  CHECK (recipient_email = lower(btrim(recipient_email)) AND position('@' IN recipient_email) > 1)
);

CREATE TABLE private.notification_payloads (
  scope text NOT NULL CHECK (scope IN ('TENANT','PLATFORM')),
  academy_id uuid,
  CHECK ((scope = 'TENANT' AND academy_id IS NOT NULL) OR (scope = 'PLATFORM' AND academy_id IS NULL)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  delivery_id uuid PRIMARY KEY,
  body jsonb NOT NULL CHECK (jsonb_typeof(body) = 'object' AND octet_length(body::text) <= 65536),
  purge_at timestamptz NOT NULL
);

CREATE TABLE private.notification_webhook_receipts (
  scope text NOT NULL CHECK (scope IN ('TENANT','PLATFORM')),
  academy_id uuid,
  CHECK ((scope = 'TENANT' AND academy_id IS NOT NULL) OR (scope = 'PLATFORM' AND academy_id IS NULL)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  receipt_key text PRIMARY KEY CHECK (receipt_key ~ '^[0-9a-f]{64}$'),
  delivery_id uuid NOT NULL,
  provider_event text NOT NULL CHECK (length(btrim(provider_event)) BETWEEN 1 AND 100),
  provider_message_id text NOT NULL,
  provider_occurred_at timestamptz,
  received_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  purge_at timestamptz NOT NULL
);

CREATE TABLE private.booking_reminders (
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  booking_id uuid PRIMARY KEY,
  academy_id uuid NOT NULL,
  booking_revision bigint NOT NULL CHECK (booking_revision > 0),
  status text NOT NULL CHECK (status IN ('SCHEDULED', 'QUEUED', 'CANCELLED', 'SKIPPED')),
  due_at timestamptz,
  starts_at timestamptz NOT NULL,
  event_id uuid,
  reason_code text,
  purge_at timestamptz,
  CHECK (status <> 'SCHEDULED' OR due_at IS NOT NULL)
);

CREATE TABLE private.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope text NOT NULL CHECK (scope IN ('TENANT','PLATFORM')),
  academy_id uuid,
  CHECK ((scope = 'TENANT' AND academy_id IS NOT NULL) OR (scope = 'PLATFORM' AND academy_id IS NULL)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  operation_id uuid NOT NULL,
  effect_key text NOT NULL CHECK (length(btrim(effect_key)) > 0),
  UNIQUE (operation_id, effect_key),
  actor_kind text NOT NULL CHECK (actor_kind IN ('USER','SYSTEM')),
  actor_user_id uuid,
  actor_ref text NOT NULL CHECK (length(btrim(actor_ref)) > 0),
  CHECK ((actor_kind = 'USER' AND actor_user_id IS NOT NULL AND actor_ref = actor_user_id::text) OR (actor_kind = 'SYSTEM' AND actor_user_id IS NULL)),
  action text NOT NULL CHECK (length(btrim(action)) BETWEEN 1 AND 100),
  resource_type text NOT NULL CHECK (length(btrim(resource_type)) BETWEEN 1 AND 100),
  resource_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object' AND octet_length(metadata::text) <= 65536)
);
