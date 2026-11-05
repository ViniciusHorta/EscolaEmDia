begin;

-- Only the authenticated Edge Function can read or create these credentials.
-- No client-side access policy is granted, including for the account owner.
create table if not exists public.parent_pin_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null check (pin_hash ~ '^[0-9a-f]{64}$'),
  salt text not null check (salt ~ '^[0-9a-f]{32}$'),
  algorithm text not null default 'pbkdf2-sha256-hmac-pepper-v1'
    check (algorithm = 'pbkdf2-sha256-hmac-pepper-v1'),
  iterations integer not null default 600000 check (iterations >= 600000),
  created_at timestamptz not null default now()
);

alter table public.parent_pin_credentials enable row level security;
revoke all on public.parent_pin_credentials from public, anon, authenticated;
revoke all on public.parent_pin_credentials from service_role;
grant select, insert on public.parent_pin_credentials to service_role;

comment on table public.parent_pin_credentials is
  'Adult PIN hashes. Initial setup only; changing a PIN requires a separate reauthenticated flow.';

commit;
