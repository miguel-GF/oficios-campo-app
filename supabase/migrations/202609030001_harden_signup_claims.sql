-- Prevent several email accounts on one installation from replaying the
-- first-period welcome credits. Safe to run after the base migration.
create table if not exists public.signup_credit_claims (
  installation_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.signup_credit_claims enable row level security;
