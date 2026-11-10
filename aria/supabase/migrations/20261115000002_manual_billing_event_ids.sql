-- Manual (trial / promo) billing events get unique ids. A fixed id made a
-- second trial or redemption impossible once the first was removed (e.g.
-- support refunds a promo, or a test cleans up): the history insert hit
-- billing_events' unique (provider, event_id). Webhook events keep the
-- provider's ids for idempotency.

create or replace function public.start_trial(p_circle uuid, p_plan text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_plan   public.plans;
  v_end    timestamptz;
begin
  select * into v_circle from public.circles where id = p_circle;
  if v_circle.id is null or v_circle.owner_id <> (select auth.uid()) then
    raise exception 'only the owner can start a trial' using errcode = '42501';
  end if;
  select * into v_plan from public.plans where code = p_plan and is_active;
  if v_plan.id is null or v_plan.trial_days <= 0 then
    raise exception 'no trial for this plan' using errcode = 'P0001', hint = 'no_trial';
  end if;
  if not public.plan_fits_circle(p_plan, v_circle.type) then
    raise exception 'plan does not fit this circle' using errcode = 'P0001', hint = 'wrong_circle';
  end if;
  if exists (select 1 from public.subscriptions where circle_id = p_circle and trial_end is not null) then
    raise exception 'trial already used' using errcode = 'P0001', hint = 'trial_used';
  end if;
  v_end := now() + make_interval(days => v_plan.trial_days);
  insert into public.subscriptions (circle_id, plan_id, provider, status, trial_end, external_ref)
  values (p_circle, v_plan.id, 'manual', 'trialing', v_end, 'trial:' || p_circle);
  insert into public.billing_events (circle_id, provider, event_id, type, plan_code)
  values (p_circle, 'manual', 'trial:' || p_circle || ':' || gen_random_uuid(), 'trial_started', p_plan);
  return v_end;
end $$;

create or replace function public.redeem_promo(p_circle uuid, p_code text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_promo  public.promo_codes;
  v_plan   public.plans;
  v_end    timestamptz;
  v_code   text := upper(trim(p_code));
begin
  select * into v_circle from public.circles where id = p_circle;
  if v_circle.id is null or v_circle.owner_id <> (select auth.uid()) then
    raise exception 'only the owner can redeem a code' using errcode = '42501';
  end if;
  select * into v_promo from public.promo_codes where code = v_code for update;
  if v_promo.code is null or not v_promo.is_active
     or (v_promo.expires_at is not null and v_promo.expires_at < now()) then
    raise exception 'promo code not valid' using errcode = 'P0001', hint = 'invalid_code';
  end if;
  if v_promo.max_redemptions is not null and v_promo.redemptions >= v_promo.max_redemptions then
    raise exception 'promo code used up' using errcode = 'P0001', hint = 'code_used_up';
  end if;
  select * into v_plan from public.plans where id = v_promo.plan_id;
  if not public.plan_fits_circle(v_plan.code, v_circle.type) then
    raise exception 'plan does not fit this circle' using errcode = 'P0001', hint = 'wrong_circle';
  end if;
  if exists (select 1 from public.promo_redemptions where code = v_code and circle_id = p_circle) then
    raise exception 'promo code already redeemed' using errcode = 'P0001', hint = 'already_redeemed';
  end if;
  v_end := now() + make_interval(days => v_promo.days);
  insert into public.promo_redemptions (code, circle_id, user_id) values (v_code, p_circle, (select auth.uid()));
  update public.promo_codes set redemptions = redemptions + 1 where code = v_code;
  insert into public.subscriptions (circle_id, plan_id, provider, status, current_period_end, external_ref, cancel_at_period_end)
  values (p_circle, v_plan.id, 'manual', 'active', v_end, 'promo:' || v_code || ':' || p_circle, true);
  insert into public.billing_events (circle_id, provider, event_id, type, plan_code, amount_inr)
  values (p_circle, 'manual', 'promo:' || v_code || ':' || p_circle || ':' || gen_random_uuid(), 'promo', v_plan.code, 0);
  return v_end;
end $$;
