create extension if not exists pgcrypto;

create table if not exists app_accounts (
  user_id text primary key,
  email text not null default '',
  stripe_customer_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists auth_exchange_codes (
  code_hash text primary key,
  user_id text not null references app_accounts(user_id) on delete cascade,
  code_challenge text not null,
  redirect_uri text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists mobile_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references app_accounts(user_id) on delete cascade,
  access_token_hash text not null unique,
  refresh_token_hash text not null unique,
  access_expires_at timestamptz not null,
  refresh_expires_at timestamptz not null,
  rotated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists mobile_sessions_user on mobile_sessions(user_id);

create table if not exists entitlements (
  user_id text primary key references app_accounts(user_id) on delete cascade,
  is_pro boolean not null default false,
  stripe_subscription_id text unique,
  pro_until timestamptz,
  verified_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists monthly_quotas (
  user_id text not null references app_accounts(user_id) on delete cascade,
  period text not null check (period ~ '^[0-9]{4}-[0-9]{2}$'),
  ai_used integer not null default 0 check (ai_used >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, period)
);

create table if not exists guest_installations (
  installation_hash text primary key,
  ai_uses integer not null default 0 check (ai_uses between 0 and 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id text references app_accounts(user_id) on delete set null,
  installation_hash text not null,
  period text not null,
  idempotency_key uuid not null unique,
  request_hash text not null,
  model text not null,
  credit_kind text not null check (credit_kind in ('guest', 'monthly', 'pro')),
  status text not null check (status in ('pending', 'succeeded', 'failed')),
  input_tokens integer,
  output_tokens integer,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists ai_usage_user_period on ai_usage(user_id, period);

create table if not exists billing_events (
  event_id text primary key,
  user_id text references app_accounts(user_id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now()
);
