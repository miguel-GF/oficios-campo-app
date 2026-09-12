create extension if not exists pgcrypto;

create table if not exists public.app_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  registered_period text not null check (registered_period ~ '^[0-9]{4}-[0-9]{2}$'),
  signup_bonus_remaining integer not null default 2 check (signup_bonus_remaining between 0 and 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_pro boolean not null default false,
  product_id text,
  purchase_token_hash text unique,
  pro_until timestamptz,
  verified_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.monthly_quotas (
  user_id uuid not null references auth.users(id) on delete cascade,
  period text not null check (period ~ '^[0-9]{4}-[0-9]{2}$'),
  ai_used integer not null default 0 check (ai_used >= 0),
  manual_used integer not null default 0 check (manual_used >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, period)
);

create table if not exists public.guest_installations (
  installation_hash text primary key,
  ai_uses integer not null default 0 check (ai_uses between 0 and 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.signup_credit_claims (
  installation_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  installation_hash text not null,
  period text not null,
  idempotency_key uuid not null unique,
  request_hash text not null,
  model text not null,
  credit_kind text not null check (credit_kind in ('guest', 'signup', 'monthly', 'pro')),
  status text not null check (status in ('pending', 'succeeded', 'failed')),
  input_tokens integer,
  output_tokens integer,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists public.billing_events (
  event_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  purchase_token_hash text,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now()
);

create table if not exists public.encrypted_backups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  format_version integer not null,
  size_bytes bigint not null check (size_bytes between 1 and 52428800),
  checksum_sha256 text not null,
  created_at timestamptz not null default now()
);

alter table public.app_accounts enable row level security;
alter table public.entitlements enable row level security;
alter table public.monthly_quotas enable row level security;
alter table public.guest_installations enable row level security;
alter table public.signup_credit_claims enable row level security;
alter table public.ai_usage enable row level security;
alter table public.billing_events enable row level security;
alter table public.encrypted_backups enable row level security;

create policy "read own account" on public.app_accounts for select using (auth.uid() = user_id);
create policy "read own entitlement" on public.entitlements for select using (auth.uid() = user_id);
create policy "read own quota" on public.monthly_quotas for select using (auth.uid() = user_id);
create policy "read own ai usage" on public.ai_usage for select using (auth.uid() = user_id);
create policy "read own backups" on public.encrypted_backups for select using (auth.uid() = user_id);

-- Writes intentionally have no client policy. Only the backend service role can
-- reserve credits, verify purchases, or register backup objects.
