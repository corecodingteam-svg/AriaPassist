-- Admin panel API: MFA-gated admin access, read functions for the panel.
--
-- * API admins must have completed two-factor sign-in (JWT aal2) for every
--   admin function, read or write. The console / service role is unchanged.
-- * The panel never reads tables directly: it calls these SECURITY DEFINER
--   functions, which check the role and return metadata only.

-- Admin identity now also requires MFA for API callers.
create or replace function public.admin_actor(p_roles text[])
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
begin
  if v_uid is not null then
    select role into v_role from public.admins where user_id = v_uid;
    if v_role is null or not (v_role = 'super' or v_role = any (p_roles)) then
      raise exception 'admin permission required' using errcode = '42501';
    end if;
    if coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
      raise exception 'two-factor sign-in required' using errcode = '42501', hint = 'mfa_required';
    end if;
    return v_uid::text;
  end if;
  if auth.role() = 'service_role' or session_user <> 'authenticator' then
    return 'console:' || coalesce(nullif(current_setting('aria.actor', true), ''), session_user);
  end if;
  raise exception 'admin permission required' using errcode = '42501';
end $$;

-- Every admin role may read.
create function public.admin_reader() returns text
language sql stable security definer set search_path = '' as $$
  select public.admin_actor(array['support', 'finance']);
$$;

-- Who am I? Works before MFA so the panel can ask for the second factor.
create function public.admin_me()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'role', (select role from public.admins where user_id = auth.uid()),
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'));
$$;

-- Headline numbers for the Overview page.
create function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform public.admin_reader();
  with live as (
    select s.*, p.code, p.price_month_inr, p.price_year_inr
      from public.subscriptions s join public.plans p on p.id = s.plan_id
     where public.subscription_entitles(s)
  )
  select jsonb_build_object(
    'users', (select count(*) from public.users),
    'signups_7d', (select count(*) from public.users where created_at > now() - interval '7 days'),
    'active_7d', (select count(*) from public.users where last_seen_at > now() - interval '7 days'),
    'active_30d', (select count(*) from public.users where last_seen_at > now() - interval '30 days'),
    'suspended', (select count(*) from public.users where suspended_at is not null),
    'pending_deletions', (select count(*) from public.account_deletions),
    'paid_circles', (select count(distinct circle_id) from live where provider <> 'manual'),
    'trials', (select count(distinct circle_id) from live where status = 'trialing'),
    'granted', (select count(distinct circle_id) from live where provider = 'manual' and status = 'active'),
    -- Monthly-equivalent of paying subscriptions (gross, before store fees).
    'mrr_inr', (select coalesce(sum(case when period = 'year' then price_year_inr / 12.0 else price_month_inr end), 0)
                  from live where provider <> 'manual' and status in ('active', 'past_due')),
    'past_due', (select count(*) from live where status = 'past_due'),
    'expiring_7d', (select count(*) from reports.expiring where days_left <= 7),
    'lapsed_30d', (select count(*) from reports.lapsed where ended_at > now() - interval '30 days'),
    'revenue_this_month_inr', (select coalesce(sum(amount_inr), 0) from public.billing_events
                                where occurred_at >= date_trunc('month', now())),
    'reminders_7d', (select count(*) from public.reminders where created_at > now() - interval '7 days')
  ) into v;
  return v;
end $$;

-- Read-only gateway to the reports views (whitelisted), paginated.
create function public.admin_report(p_name text, p_limit int default 200, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform public.admin_reader();
  if p_name not in ('activity_daily', 'circle_tenure', 'expiring', 'lapsed', 'subscriptions_overview',
                    'revenue_monthly', 'renewal_rate_monthly', 'trial_conversion', 'messaging_daily',
                    'admin_activity') then
    raise exception 'unknown report' using errcode = 'P0001', hint = 'unknown_report';
  end if;
  execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from reports.%I limit %s offset %s) t',
                 p_name, least(greatest(coalesce(p_limit, 200), 1), 1000), greatest(coalesce(p_offset, 0), 0))
    into v;
  return v;
end $$;

-- Find users by phone, email, name or id (metadata only).
create function public.admin_search_users(p_q text, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
  q text := trim(coalesce(p_q, ''));
begin
  perform public.admin_reader();
  select coalesce(jsonb_agg(u order by u.created_at desc), '[]'::jsonb) into v
    from (select * from reports.users r
           where q = ''
              or r.id::text = q
              or r.phone ilike '%' || regexp_replace(q, '[^0-9]', '', 'g') || '%' and length(regexp_replace(q, '[^0-9]', '', 'g')) >= 4
              or r.email ilike '%' || q || '%'
              or r.name ilike '%' || q || '%'
           order by r.created_at desc
           limit least(greatest(coalesce(p_limit, 50), 1), 200)) u;
  return v;
end $$;

-- One user: profile metadata, Circles + plans, billing history of owned
-- Circles, renewal messages, admin history. Viewing is logged.
create function public.admin_user_detail(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := public.admin_reader();
  v jsonb;
begin
  if not exists (select 1 from public.users where id = p_user) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  perform public.admin_log(v_actor, 'user.viewed', p_user, null, 'opened in admin panel');
  select jsonb_build_object(
    'user', (select to_jsonb(r) from reports.users r where r.id = p_user),
    'circles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'type', c.type, 'role', m.role, 'status', m.status,
        'plan', p.code, 'paid_until', pu.ends_at, 'auto_renews', pu.auto_renews, 'provider', pu.provider,
        'members', (select count(*) from public.memberships x where x.circle_id = c.id and x.status = 'active'))
        order by (c.type = 'personal') desc, c.created_at)
        from public.memberships m
        join public.circles c on c.id = m.circle_id
        join public.plans p on p.id = c.plan_id
        left join public.circle_paid_until pu on pu.circle_id = c.id
       where m.user_id = p_user and m.deleted_at is null), '[]'::jsonb),
    'billing', coalesce((
      select jsonb_agg(jsonb_build_object('type', b.type, 'plan', b.plan_code, 'amount_inr', b.amount_inr,
                                          'provider', b.provider, 'at', b.occurred_at, 'circle_id', b.circle_id)
                       order by b.occurred_at desc)
        from public.billing_events b
        join public.circles c on c.id = b.circle_id and c.owner_id = p_user), '[]'::jsonb),
    'renewal_notices', coalesce((
      select jsonb_agg(jsonb_build_object('step', n.step, 'channel', n.channel, 'status', n.status, 'at', n.created_at)
                       order by n.created_at desc)
        from public.renewal_notices n where n.user_id = p_user), '[]'::jsonb),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('action', a.action, 'actor', a.actor, 'reason', a.reason,
                                          'details', a.details, 'at', a.at) order by a.at desc)
        from (select * from public.admin_actions where target_user = p_user order by at desc limit 100) a), '[]'::jsonb)
  ) into v;
  return v;
end $$;

create function public.admin_list_promos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform public.admin_reader();
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', pc.code, 'plan', p.code, 'days', pc.days, 'max_redemptions', pc.max_redemptions,
           'redemptions', pc.redemptions, 'expires_at', pc.expires_at, 'is_active', pc.is_active, 'note', pc.note)
           order by pc.is_active desc, pc.code), '[]'::jsonb) into v
    from public.promo_codes pc join public.plans p on p.id = pc.plan_id;
  return v;
end $$;

create function public.admin_list_admins()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform public.admin_actor(array[]::text[]);  -- super only
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', a.user_id, 'role', a.role, 'since', a.created_at,
           'name', u.name, 'email', u.email, 'phone', u.phone, 'last_seen_at', u.last_seen_at)
           order by a.created_at), '[]'::jsonb) into v
    from public.admins a join public.users u on u.id = a.user_id;
  return v;
end $$;

revoke execute on function public.admin_reader(), public.admin_me(), public.admin_overview(),
  public.admin_report(text, int, int), public.admin_search_users(text, int),
  public.admin_user_detail(uuid), public.admin_list_promos(), public.admin_list_admins()
  from anon, public;
grant execute on function public.admin_me(), public.admin_overview(),
  public.admin_report(text, int, int), public.admin_search_users(text, int),
  public.admin_user_detail(uuid), public.admin_list_promos(), public.admin_list_admins()
  to authenticated, service_role;
