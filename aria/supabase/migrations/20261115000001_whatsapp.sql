-- Phase 8: WhatsApp reminders (Meta Cloud API) for plans with "whatsapp".
--
-- Flow: pg_cron (every minute) → kick_whatsapp_dispatch() → POST the
-- whatsapp-dispatch Edge Function → claim_whatsapp_due() → send → record.
-- Replies ("done") come back through the whatsapp-webhook function.

create extension if not exists pg_net;

-- Opt-in is explicit and recorded (WhatsApp Business policy).
create table public.whatsapp_optins (
  user_id     uuid primary key references public.users (id) on delete cascade,
  phone_e164  text not null check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  enabled     boolean not null default true,
  opted_in_at timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.whatsapp_optins enable row level security;
create policy whatsapp_optins_select on public.whatsapp_optins for select to authenticated
  using (user_id = (select auth.uid()));

-- One message per reminder occurrence.
create table public.whatsapp_outbox (
  id            uuid primary key default gen_random_uuid(),
  reminder_id   uuid not null references public.reminders (id) on delete cascade,
  user_id       uuid not null references public.users (id) on delete cascade,
  occurrence_at timestamptz not null,
  phone_e164    text not null,
  status        text not null default 'claimed'
                check (status in ('claimed', 'sent', 'delivered', 'read', 'failed', 'logged')),
  wamid         text,          -- WhatsApp message id (for replies/receipts)
  error         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (reminder_id, occurrence_at)
);
create index whatsapp_outbox_wamid on public.whatsapp_outbox (wamid) where wamid is not null;
alter table public.whatsapp_outbox enable row level security;
create policy whatsapp_outbox_select on public.whatsapp_outbox for select to authenticated
  using (user_id = (select auth.uid()));

-- Does this user have a plan feature through any active membership?
create function public.user_has_feature(p_user uuid, p_feature text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
      join public.circles c on c.id = m.circle_id
      join public.plans p on p.id = c.plan_id
     where m.user_id = p_user and m.status = 'active' and m.deleted_at is null
       and coalesce((p.features_json ->> p_feature)::boolean, false));
$$;

-- App toggle. Uses the phone number verified at sign-in (never typed in).
create function public.set_whatsapp(p_enabled boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := (select auth.uid());
  v_phone text;
begin
  if v_uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if p_enabled and not public.user_has_feature(v_uid, 'whatsapp') then
    raise exception 'whatsapp needs a Family or Team plan' using errcode = 'P0001', hint = 'upgrade_required';
  end if;
  select phone into v_phone from auth.users where id = v_uid;
  if p_enabled and coalesce(v_phone, '') = '' then
    raise exception 'sign in with a phone number to use WhatsApp' using errcode = 'P0001', hint = 'no_phone';
  end if;
  if p_enabled then
    insert into public.whatsapp_optins (user_id, phone_e164)
    values (v_uid, '+' || ltrim(v_phone, '+'))
    on conflict (user_id) do update
      set enabled = true, phone_e164 = excluded.phone_e164, opted_in_at = now(), updated_at = now();
    return '+' || ltrim(v_phone, '+');
  end if;
  update public.whatsapp_optins set enabled = false, updated_at = now() where user_id = v_uid;
  return null;
end $$;

-- Claims reminders that came due in the last 10 minutes for opted-in
-- users with the feature, at most once per occurrence.
create function public.claim_whatsapp_due(p_limit int default 100)
returns table (outbox_id uuid, reminder_id uuid, phone text, title text,
               due_at timestamptz, timezone text, amount numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
  with due as (
    select r.id, coalesce(r.assigned_to, r.created_by) as owner,
           coalesce(r.snoozed_until, r.start_at) as at, r.title, r.timezone, r.amount
      from public.reminders r
     where r.status = 'active' and r.deleted_at is null
       and coalesce(r.snoozed_until, r.start_at) between now() - interval '10 minutes' and now()
  ), ins as (
    insert into public.whatsapp_outbox (reminder_id, user_id, occurrence_at, phone_e164)
    select d.id, d.owner, d.at, o.phone_e164
      from due d
      join public.whatsapp_optins o on o.user_id = d.owner and o.enabled
     where public.user_has_feature(d.owner, 'whatsapp')
     order by d.at
     limit p_limit
    on conflict (reminder_id, occurrence_at) do nothing
    returning id, whatsapp_outbox.reminder_id, phone_e164, occurrence_at
  )
  select ins.id, ins.reminder_id, ins.phone_e164, d.title, ins.occurrence_at, d.timezone, d.amount
    from ins join due d on d.id = ins.reminder_id;
end $$;

create function public.record_whatsapp_send(p_outbox uuid, p_status text, p_wamid text, p_error text)
returns void language sql security definer set search_path = '' as $$
  update public.whatsapp_outbox
     set status = p_status, wamid = coalesce(p_wamid, wamid), error = p_error, updated_at = now()
   where id = p_outbox;
$$;

-- Receipts and replies from the webhook. "done"/"ho gaya" on the reminder
-- message (or the latest one to that phone) completes it.
create function public.apply_whatsapp_inbound(p_phone text, p_context_wamid text, p_text text, p_status text, p_status_wamid text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_out public.whatsapp_outbox;
  v_rem public.reminders;
begin
  if p_status is not null and p_status_wamid is not null then
    update public.whatsapp_outbox set status = p_status, updated_at = now()
     where wamid = p_status_wamid and p_status in ('sent', 'delivered', 'read', 'failed');
    return 'status';
  end if;
  if p_text is null or lower(trim(p_text)) !~ '^(done|ok done|completed|ho gaya|ho gayi|kar liya|✅|👍)[.! ]*$' then
    return 'ignored';
  end if;
  select * into v_out from public.whatsapp_outbox
   where (p_context_wamid is not null and wamid = p_context_wamid)
      or (p_context_wamid is null and phone_e164 = '+' || ltrim(p_phone, '+'))
   order by created_at desc limit 1;
  if v_out.id is null then return 'no_message'; end if;
  select * into v_rem from public.reminders where id = v_out.reminder_id;
  if v_rem.id is null or v_rem.status <> 'active' then return 'already'; end if;
  insert into public.reminder_events (reminder_id, user_id, type, at, meta_json)
  values (v_rem.id, v_out.user_id, 'done', now(),
          jsonb_build_object('via', 'whatsapp', 'occurrence', v_out.occurrence_at));
  -- One-off → done. Recurring → the app advances the series when it syncs
  -- the event (same path as a Done tapped on another device).
  if v_rem.rrule is null then
    update public.reminders set status = 'done', last_done_at = now() where id = v_rem.id;
  else
    update public.reminders set last_done_at = now() where id = v_rem.id;
  end if;
  return 'done';
end $$;

-- Cron → Edge Function. URL and secret live in Vault (ops sets them):
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'aria_functions_url');
--   select vault.create_secret('<random>', 'aria_cron_secret');
create function public.kick_whatsapp_dispatch()
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'aria_functions_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'aria_cron_secret';
  if v_url is null or v_secret is null then return null; end if;
  if not exists (select 1 from public.whatsapp_optins where enabled) then return null; end if;
  return net.http_post(
    url := v_url || '/whatsapp-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb);
end $$;
select cron.schedule('aria-whatsapp-dispatch', '* * * * *', 'select public.kick_whatsapp_dispatch()');

revoke execute on function public.claim_whatsapp_due(int),
                           public.record_whatsapp_send(uuid, text, text, text),
                           public.apply_whatsapp_inbound(text, text, text, text, text),
                           public.kick_whatsapp_dispatch(),
                           public.user_has_feature(uuid, text)
  from anon, authenticated, public;
grant execute on function public.claim_whatsapp_due(int),
                          public.record_whatsapp_send(uuid, text, text, text),
                          public.apply_whatsapp_inbound(text, text, text, text, text)
  to service_role;
revoke execute on function public.set_whatsapp(boolean) from anon, public;
grant execute on function public.set_whatsapp(boolean) to authenticated;
