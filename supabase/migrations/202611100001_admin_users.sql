begin;

-- Visão de utilizadores para a ferramenta local tools/admin: responsáveis, famílias, crianças,
-- plano efetivo e assinaturas (canal, pagamento, renovação). Só leitura; apenas service_role.

-- Criança: plano efetivo (child_access), vaga gratuita, atividade e todas as assinaturas (mais recente primeiro).
-- volatile (não stable): child_access pode reequilibrar as vagas gratuitas (bloqueia linhas), e o PostgREST
-- executa funções stable numa transação só de leitura.
create function public.admin_child_json(c public.children)
returns jsonb language sql volatile security definer set search_path = '' as $$
  select jsonb_build_object(
    'childId', c.id,
    'name', c.display_name,
    'schoolYear', c.school_year,
    'createdAt', c.created_at,
    'plan', public.child_access(c.id)->>'plan',
    'freeSlotSince', (select fs.claimed_at from public.child_free_slots fs where fs.child_id = c.id),
    'completedAttempts', (select count(*) from public.worksheet_attempts a where a.child_id = c.id and a.submitted_at is not null),
    'lastActivityAt', (select max(coalesce(a.submitted_at, a.started_at)) from public.worksheet_attempts a where a.child_id = c.id),
    'subscriptions', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', s.id,
          'channel', s.channel,
          'status', s.status,
          'autoRenew', s.auto_renew,
          'productId', s.store_product_id,
          'externalId', s.external_id,
          'currentPeriodStart', s.current_period_start,
          'currentPeriodEnd', s.current_period_end,
          'graceUntil', s.grace_until,
          'priceCents', s.price_amount_cents,
          'currency', s.currency,
          'createdAt', s.created_at,
          'updatedAt', s.updated_at,
          -- Último pagamento conhecido: fatura Stripe paga ou compra/renovação na loja.
          'lastPaymentAt', (select max(e.created_at) from public.billing_events e
                             where e.subscription_id = s.id
                               and e.event_type in ('invoice.paid', 'SUBSCRIPTION_PURCHASED', 'SUBSCRIPTION_RENEWED',
                                                    'SUBSCRIPTION_RECOVERED', 'SUBSCRIPTION_RESTARTED', 'subscription.granted')),
          'payments', (select count(*) from public.billing_events e
                        where e.subscription_id = s.id and e.event_type in ('invoice.paid', 'SUBSCRIPTION_PURCHASED',
                          'SUBSCRIPTION_RENEWED', 'SUBSCRIPTION_RECOVERED', 'SUBSCRIPTION_RESTARTED'))
        ) order by s.created_at desc)
        from public.child_subscriptions s where s.child_id = c.id), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Lista de responsáveis com famílias, crianças e assinaturas.
-- ---------------------------------------------------------------------------
create function public.admin_list_users()
returns jsonb language sql volatile security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.id,
      'email', u.email,
      'createdAt', u.created_at,
      'lastSignInAt', u.last_sign_in_at,
      'emailConfirmedAt', u.email_confirmed_at,
      'provider', u.raw_app_meta_data->>'provider',
      'lastLegalAcceptanceAt', (select max(a.accepted_at) from public.legal_acceptances a where a.user_id = u.id),
      'families', coalesce((
        select jsonb_agg(jsonb_build_object(
            'familyId', f.id,
            'status', f.status,
            'role', case when f.created_by = u.id then 'owner' else 'member' end,
            'createdAt', f.created_at,
            'closedAt', f.closed_at,
            'stripeCustomerId', (select sc.customer_id from public.stripe_customers sc where sc.family_id = f.id),
            'members', (select count(*) from public.family_members x where x.family_id = f.id and x.status = 'active'),
            'children', coalesce((
              select jsonb_agg(public.admin_child_json(c) order by c.created_at)
                from public.children c where c.family_id = f.id), '[]'::jsonb)
          ) order by f.created_at)
          from public.family_members m join public.families f on f.id = m.family_id
         where m.adult_user_id = u.id), '[]'::jsonb)
    ) order by u.created_at desc), '[]'::jsonb)
  from auth.users u
  where not coalesce(u.is_anonymous, false);
$$;

-- ---------------------------------------------------------------------------
-- Histórico de eventos de faturação de uma família (mais recente primeiro).
-- ---------------------------------------------------------------------------
create function public.admin_family_billing_events(p_family_id uuid, p_limit integer default 200)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object(
        'id', e.id, 'createdAt', e.created_at, 'source', e.source, 'eventType', e.event_type,
        'childId', e.child_id, 'childName', c.display_name, 'subscriptionId', e.subscription_id,
        'externalEventId', e.external_event_id, 'payload', e.payload) x
      from public.billing_events e left join public.children c on c.id = e.child_id
     where e.family_id = p_family_id
     order by e.id desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000)
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- Limites comerciais (billing_settings), só leitura.
-- ---------------------------------------------------------------------------
create function public.admin_list_billing_settings()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'description', s.description,
      'updatedAt', s.updated_at) order by s.key), '[]'::jsonb)
  from public.billing_settings s;
$$;

revoke all on function public.admin_list_users(), public.admin_child_json(public.children),
  public.admin_family_billing_events(uuid, integer), public.admin_list_billing_settings()
  from public, anon, authenticated;
grant execute on function public.admin_list_users(), public.admin_child_json(public.children),
  public.admin_family_billing_events(uuid, integer), public.admin_list_billing_settings()
  to service_role;

notify pgrst, 'reload schema';
commit;
