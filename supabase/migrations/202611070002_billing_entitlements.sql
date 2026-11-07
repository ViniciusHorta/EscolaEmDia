-- Fase 1 — Modelo de direitos de acesso (Premium por criança), ainda sem pagamentos.
--
-- Conceitos:
--   * billing_settings     — limites comerciais configuráveis (nada hardcoded).
--   * child_subscriptions  — uma linha por assinatura (manual, Stripe, Google Play, App Store).
--                            Só pode existir uma assinatura "viva" por criança.
--   * child_free_slots     — crianças que ocupam a(s) vaga(s) gratuita(s) da família.
--   * billing_events       — registo auditável e append-only; external_event_id garante idempotência.
--
-- Plano efetivo de uma criança (child_access):
--   premium  → assinatura active/in_grace dentro do período (ou da tolerância);
--   free     → ocupa uma vaga gratuita;
--   locked   → nenhum dos dois: não pode iniciar novas atividades.
--
-- A vaga gratuita é atribuída automaticamente e não se transfere manualmente:
--   * quem a ocupa mantém-na enquanto não for Premium;
--   * é libertada quando a criança passa a Premium ou é eliminada;
--   * uma vaga livre é ocupada pela criança não-Premium mais antiga sem vaga.
begin;

-- ---------------------------------------------------------------------------
-- Configuração
-- ---------------------------------------------------------------------------
create table public.billing_settings (
  key text primary key check (key ~ '^[a-z_]+$'),
  value integer not null check (value >= 0),
  description text not null,
  updated_at timestamptz not null default now()
);
insert into public.billing_settings(key, value, description) values
  ('free_child_slots',       1, 'Vagas gratuitas por conta'),
  ('max_premium_children',   5, 'Máximo de crianças Premium por conta (= produtos-vaga nas lojas)'),
  ('free_max_questions',     6, 'Máximo de questões numa ficha Free'),
  ('free_daily_assignments', 1, 'Fichas que o responsável pode disponibilizar por dia a uma criança Free'),
  ('free_daily_attempts',    1, 'Fichas que uma criança Free pode executar por dia (novas ou repetidas)');

create function public.billing_setting(p_key text)
returns integer language plpgsql stable security definer set search_path = '' as $$
declare v integer;
begin
  select value into v from public.billing_settings where key = p_key;
  if not found then
    raise exception using message = 'BILLING_SETTING_MISSING', detail = p_key, errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------
create table public.child_subscriptions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  -- set null: a assinatura (e o seu histórico) sobrevive à eliminação do perfil.
  child_id uuid references public.children(id) on delete set null,
  channel text not null check (channel in ('manual','stripe','google_play','app_store')),
  external_id text,
  store_product_id text,
  status text not null check (status in ('pending','active','in_grace','expired','revoked')),
  auto_renew boolean not null default true,
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_until timestamptz,
  price_amount_cents integer check (price_amount_cents is null or price_amount_cents >= 0),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status = 'pending' or current_period_end is not null),
  check (channel = 'manual' or external_id is not null),
  check (grace_until is null or current_period_end is null or grace_until >= current_period_end)
);
create unique index child_subscriptions_external_unique
  on public.child_subscriptions(channel, external_id) where external_id is not null;
-- Proteção contra assinaturas duplicadas: uma assinatura viva por criança.
create unique index child_subscriptions_one_live_per_child
  on public.child_subscriptions(child_id) where status in ('pending','active','in_grace');
create index child_subscriptions_family_status_idx on public.child_subscriptions(family_id, status);

create table public.child_free_slots (
  child_id uuid primary key references public.children(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  claimed_at timestamptz not null default now()
);
create index child_free_slots_family_idx on public.child_free_slots(family_id);

create table public.billing_events (
  id bigint generated always as identity primary key,
  family_id uuid references public.families(id) on delete cascade,
  child_id uuid,  -- sem FK: o evento mantém-se após a eliminação do perfil
  subscription_id uuid references public.child_subscriptions(id) on delete set null,
  source text not null check (source in ('system','admin','stripe','google_play','app_store')),
  event_type text not null,
  external_event_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index billing_events_external_unique
  on public.billing_events(source, external_event_id) where external_event_id is not null;
create index billing_events_family_created_idx on public.billing_events(family_id, created_at);
create index billing_events_child_created_idx on public.billing_events(child_id, created_at);

alter table public.billing_settings enable row level security;
alter table public.child_subscriptions enable row level security;
alter table public.child_free_slots enable row level security;
alter table public.billing_events enable row level security;
revoke all on public.billing_settings, public.child_subscriptions, public.child_free_slots,
  public.billing_events from public, anon, authenticated, service_role;
-- Leituras só após autorização nas Edge Functions; escritas apenas pelas funções abaixo.
grant select on public.billing_settings, public.child_subscriptions, public.child_free_slots,
  public.billing_events to service_role;

-- ---------------------------------------------------------------------------
-- Regras
-- ---------------------------------------------------------------------------
create function public.child_has_premium(p_child_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.child_subscriptions s
    where s.child_id = p_child_id
      and s.status in ('active','in_grace')
      and greatest(s.current_period_end, coalesce(s.grace_until, s.current_period_end)) > now()
  );
$$;

-- Marca como expiradas as assinaturas cujo período (e tolerância) já terminou.
create function public.billing_expire_due(p_family_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  with expired as (
    update public.child_subscriptions s
       set status = 'expired', updated_at = now()
     where s.family_id = p_family_id
       and s.status in ('active','in_grace')
       and greatest(s.current_period_end, coalesce(s.grace_until, s.current_period_end)) <= now()
    returning s.id, s.child_id, s.family_id
  )
  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type)
  select family_id, child_id, id, 'system', 'subscription.expired' from expired;
end;
$$;

-- Recalcula as vagas gratuitas da família. Idempotente; serializado por família.
create function public.billing_rebalance_family(p_family_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_available integer;
begin
  perform 1 from public.families where id = p_family_id and status = 'active' for update;
  if not found then return; end if;

  perform public.billing_expire_due(p_family_id);

  with released as (
    delete from public.child_free_slots s
     where s.family_id = p_family_id and public.child_has_premium(s.child_id)
    returning s.child_id
  )
  insert into public.billing_events(family_id, child_id, source, event_type)
  select p_family_id, child_id, 'system', 'free_slot.released' from released;

  v_available := public.billing_setting('free_child_slots')
    - (select count(*) from public.child_free_slots where family_id = p_family_id);

  if v_available > 0 then
    with claimed as (
      insert into public.child_free_slots(child_id, family_id)
      select c.id, p_family_id from public.children c
       where c.family_id = p_family_id
         and not exists (select 1 from public.child_free_slots s where s.child_id = c.id)
         and not public.child_has_premium(c.id)
       order by c.created_at, c.id
       limit v_available
      returning child_id
    )
    insert into public.billing_events(family_id, child_id, source, event_type)
    select p_family_id, child_id, 'system', 'free_slot.claimed' from claimed;
  end if;
end;
$$;

-- Plano efetivo de uma criança. Fonte de verdade para o servidor (Fase 2) e para a UI (Fase 3).
create function public.child_access(p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family_id uuid;
  v_sub public.child_subscriptions;
  v_plan text;
begin
  select family_id into v_family_id from public.children where id = p_child_id;
  if not found then
    raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
  end if;

  perform public.billing_rebalance_family(v_family_id);

  select * into v_sub from public.child_subscriptions s
   where s.child_id = p_child_id
     and s.status in ('active','in_grace')
     and greatest(s.current_period_end, coalesce(s.grace_until, s.current_period_end)) > now()
   order by s.current_period_end desc
   limit 1;

  if v_sub.id is not null then
    v_plan := 'premium';
  elsif exists (select 1 from public.child_free_slots where child_id = p_child_id) then
    v_plan := 'free';
  else
    v_plan := 'locked';
  end if;

  return jsonb_build_object(
    'childId', p_child_id,
    'plan', v_plan,
    'subscription', case when v_sub.id is null then null else jsonb_build_object(
      'id', v_sub.id,
      'channel', v_sub.channel,
      'status', v_sub.status,
      'autoRenew', v_sub.auto_renew,
      'currentPeriodEnd', v_sub.current_period_end,
      'graceUntil', v_sub.grace_until
    ) end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Integridade das assinaturas
-- ---------------------------------------------------------------------------
create function public.guard_child_subscription()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_live integer;
begin
  if new.child_id is not null and not exists (
    select 1 from public.children where id = new.child_id and family_id = new.family_id
  ) then
    raise exception using message = 'SUBSCRIPTION_CHILD_FAMILY_MISMATCH', errcode = 'P0001';
  end if;

  if new.status in ('pending','active','in_grace')
     and (tg_op = 'INSERT' or old.status not in ('pending','active','in_grace')) then
    select count(*) into v_live from public.child_subscriptions
     where family_id = new.family_id and id <> new.id
       and status in ('pending','active','in_grace');
    if v_live >= public.billing_setting('max_premium_children') then
      raise exception using message = 'MAX_PREMIUM_CHILDREN_REACHED', errcode = 'P0001';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;
create trigger child_subscriptions_guard before insert or update on public.child_subscriptions
  for each row execute function public.guard_child_subscription();

-- Qualquer alteração de assinatura ou de crianças recalcula as vagas da família.
-- pg_trigger_depth evita recursão quando o próprio rebalance expira assinaturas.
create function public.billing_after_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;
  if tg_op = 'DELETE' then
    perform public.billing_rebalance_family(old.family_id);
  else
    perform public.billing_rebalance_family(new.family_id);
  end if;
  return null;
end;
$$;
create trigger child_subscriptions_rebalance after insert or update or delete on public.child_subscriptions
  for each row execute function public.billing_after_change();
create trigger children_billing_rebalance after insert or delete on public.children
  for each row execute function public.billing_after_change();

-- ---------------------------------------------------------------------------
-- Admin: concessão manual (testes e casos excecionais). Apenas service_role.
-- ---------------------------------------------------------------------------
create function public.admin_grant_premium(p_child_id uuid, p_days integer default 30, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family_id uuid;
  v_sub_id uuid;
begin
  if p_days is null or p_days not between 1 and 3650 then
    raise exception using message = 'INVALID_DAYS', errcode = 'P0001';
  end if;
  select family_id into v_family_id from public.children where id = p_child_id;
  if not found then
    raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
  end if;

  perform public.billing_rebalance_family(v_family_id);  -- expira assinaturas vencidas antes de validar
  if exists (select 1 from public.child_subscriptions
              where child_id = p_child_id and status in ('pending','active','in_grace')) then
    raise exception using message = 'CHILD_ALREADY_PREMIUM', errcode = 'P0001';
  end if;

  insert into public.child_subscriptions(family_id, child_id, channel, status, auto_renew,
      current_period_start, current_period_end)
    values (v_family_id, p_child_id, 'manual', 'active', false, now(), now() + make_interval(days => p_days))
    returning id into v_sub_id;
  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type, payload)
    values (v_family_id, p_child_id, v_sub_id, 'admin', 'subscription.granted',
      jsonb_build_object('days', p_days, 'note', p_note));

  return public.child_access(p_child_id);
end;
$$;

create function public.admin_revoke_premium(p_child_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family_id uuid;
  v_sub_id uuid;
begin
  select family_id into v_family_id from public.children where id = p_child_id;
  if not found then
    raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
  end if;

  -- Só assinaturas manuais: as das lojas/Stripe são geridas pela plataforma de origem.
  update public.child_subscriptions set status = 'revoked'
   where child_id = p_child_id and channel = 'manual' and status in ('pending','active','in_grace')
   returning id into v_sub_id;
  if v_sub_id is null then
    raise exception using message = 'NO_MANUAL_SUBSCRIPTION', errcode = 'P0001';
  end if;
  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type, payload)
    values (v_family_id, p_child_id, v_sub_id, 'admin', 'subscription.revoked', jsonb_build_object('note', p_note));

  return public.child_access(p_child_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------------
revoke all on function
  public.billing_setting(text), public.child_has_premium(uuid), public.billing_expire_due(uuid),
  public.billing_rebalance_family(uuid), public.child_access(uuid),
  public.guard_child_subscription(), public.billing_after_change(),
  public.admin_grant_premium(uuid,integer,text), public.admin_revoke_premium(uuid,text)
  from public, anon, authenticated;
grant execute on function
  public.billing_setting(text), public.child_has_premium(uuid), public.child_access(uuid),
  public.admin_grant_premium(uuid,integer,text), public.admin_revoke_premium(uuid,text)
  to service_role;

-- Famílias existentes: atribuir vagas gratuitas (a criança mais antiga de cada família).
select public.billing_rebalance_family(id) from public.families where status = 'active';

notify pgrst, 'reload schema';
commit;
