create extension if not exists pgcrypto;

create table public.businesses (id uuid primary key default gen_random_uuid(), name text not null, trade text not null default '', created_at timestamptz not null default now());
create table public.profiles (id uuid primary key references auth.users on delete cascade, business_id uuid not null references public.businesses, name text not null default '', role text not null default 'owner', created_at timestamptz not null default now());
create table public.clients (id text primary key, business_id uuid not null references public.businesses, name text not null, phone text not null default '', neighborhood text not null default '', address text not null default '', notes text not null default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz);
create table public.appointments (id text primary key, business_id uuid not null references public.businesses, client_id text not null references public.clients, starts_at timestamptz not null, service text not null, duration_minutes int not null default 60, status text not null, order_id text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.orders (id text primary key, business_id uuid not null references public.businesses, client_id text not null references public.clients, appointment_id text, status text not null, notes text not null default '', total_cents int not null default 0, payment_method text not null default 'pending', followup_at timestamptz, closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.order_lines (id text primary key, business_id uuid not null references public.businesses, order_id text not null references public.orders, concept text not null, quantity numeric not null, unit_price_cents int not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.payments (id text primary key, business_id uuid not null references public.businesses, order_id text not null references public.orders, method text not null, amount_cents int not null check (amount_cents > 0), paid_at timestamptz not null, voided_at timestamptz, created_at timestamptz not null default now());
create table public.attachments (id text primary key, business_id uuid not null references public.businesses, order_id text not null references public.orders, kind text not null, local_uri text, remote_path text, created_at timestamptz not null default now());
create table public.followups (id text primary key, business_id uuid not null references public.businesses, client_id text not null references public.clients, order_id text not null references public.orders, due_at timestamptz not null, status text not null default 'pending', created_at timestamptz not null default now());
create table public.sync_receipts (id text primary key, user_id uuid not null references auth.users, created_at timestamptz not null default now());
create table public.subscription_entitlements (business_id uuid primary key references public.businesses, provider text not null default 'google_play', product_id text not null default 'jale', status text not null, trial_ends_at timestamptz, current_period_ends_at timestamptz, purchase_token_hash text, updated_at timestamptz not null default now());

alter table public.businesses enable row level security;
alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.appointments enable row level security;
alter table public.orders enable row level security;
alter table public.order_lines enable row level security;
alter table public.payments enable row level security;
alter table public.attachments enable row level security;
alter table public.followups enable row level security;
alter table public.sync_receipts enable row level security;
alter table public.subscription_entitlements enable row level security;

create function public.current_business_id() returns uuid language sql stable security definer set search_path=public as $$ select business_id from profiles where id=auth.uid() $$;
create policy "own profile" on public.profiles for select using (id=auth.uid());
create policy "own business" on public.businesses for select using (id=public.current_business_id());
do $$ declare t text; begin foreach t in array array['clients','appointments','orders','order_lines','payments','attachments','followups'] loop execute format('create policy "tenant access" on public.%I for all using (business_id=public.current_business_id()) with check (business_id=public.current_business_id())',t); end loop; end $$;
create policy "own receipts" on public.sync_receipts for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "own entitlement" on public.subscription_entitlements for select using (business_id=public.current_business_id());

insert into storage.buckets (id,name,public) values ('evidence','evidence',false) on conflict do nothing;
create policy "tenant evidence" on storage.objects for all to authenticated using (bucket_id='evidence' and (storage.foldername(name))[1]=public.current_business_id()::text) with check (bucket_id='evidence' and (storage.foldername(name))[1]=public.current_business_id()::text);
