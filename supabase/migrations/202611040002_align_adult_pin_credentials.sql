begin;

-- Rename in place: keep rows, hashes, salts, keys and grants until reset below.
-- Refuse ambiguous states instead of choosing a table or discarding data.
do $$
begin
  if to_regclass('public.parent_pin_credentials') is not null then
    if to_regclass('public.adult_pin_credentials') is not null then
      raise exception 'Both PIN credential tables exist. Reconcile them before running this migration.';
    end if;
    alter table public.parent_pin_credentials rename to adult_pin_credentials;
  elsif to_regclass('public.adult_pin_credentials') is null then
    raise exception 'PIN credential table not found. Apply the initial PIN migration first.';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'adult_pin_credentials'
      and column_name = 'user_id'
  ) then
    alter table public.adult_pin_credentials rename column user_id to adult_user_id;
  end if;
end;
$$;

alter table public.adult_pin_credentials
  add column if not exists updated_at timestamptz;
update public.adult_pin_credentials
  set updated_at = created_at where updated_at is null;
alter table public.adult_pin_credentials
  alter column updated_at set default now(),
  alter column updated_at set not null;

-- Keep created_at and the cryptographic metadata as implementation details.
-- Future PIN-reset transactions must also update updated_at.
alter table public.adult_pin_credentials enable row level security;
revoke all on public.adult_pin_credentials from public, anon, authenticated;
revoke all on public.adult_pin_credentials from service_role;
grant select, insert on public.adult_pin_credentials to service_role;

comment on table public.adult_pin_credentials is
  'Adult PIN credentials aligned with the ERD. Client access denied; reset requires a separate reauthenticated flow.';

notify pgrst, 'reload schema';
commit;
