-- Phase 6: multi-tenant Circles — invites, roles, assignments, dependents.

-- Per-circle and per-member settings.
alter table public.circles     add column settings_json jsonb not null default '{}'::jsonb;
-- e.g. {"simple_lock": {"pin_hash": "...", "salt": "..."}} set by an admin on a dependent.
alter table public.memberships add column settings_json jsonb not null default '{}'::jsonb;

-- ------------------------------------------------------------- invites
alter table public.invites
  add column used_at timestamptz,
  add column used_by uuid references public.users (id) on delete set null;

-- What the invite screen shows before joining (caller isn't a member yet,
-- so RLS would hide the circle).
create function public.preview_invite(p_token text)
returns table (circle_id uuid, circle_name text, circle_type public.circle_type,
               inviter_name text, role public.member_role, expired boolean, used boolean,
               already_member boolean)
language sql stable security definer set search_path = '' as $$
  select c.id, c.name, c.type, u.name, i.role,
         i.expires_at < now(), i.used_at is not null,
         exists (select 1 from public.memberships m where m.circle_id = c.id
                 and m.user_id = auth.uid() and m.status = 'active')
  from public.invites i
  join public.circles c on c.id = i.circle_id and c.deleted_at is null
  left join public.users u on u.id = i.created_by
  where i.token = p_token;
$$;

-- Joins the caller to the invite's circle. Single use; expiring. The seat
-- limit is enforced by memberships_guard (raises P0001 'upgrade_required').
create function public.accept_invite(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_inv public.invites;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into v_inv from public.invites where token = p_token for update;
  if not found then raise exception 'invite not found' using errcode = 'P0002'; end if;
  if v_inv.used_at is not null then raise exception 'invite already used' using errcode = 'P0001', hint = 'used'; end if;
  if v_inv.expires_at < now() then raise exception 'invite expired' using errcode = 'P0001', hint = 'expired'; end if;

  insert into public.memberships (circle_id, user_id, role, status)
  values (v_inv.circle_id, v_uid, v_inv.role, 'active')
  on conflict (circle_id, user_id) do update
    set role = excluded.role, status = 'active', deleted_at = null, joined_at = now();

  update public.invites set used_at = now(), used_by = v_uid where id = v_inv.id;
  return v_inv.circle_id;
end $$;

-- Any member except the owner can leave.
create function public.leave_circle(p_circle uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.circles where id = p_circle and owner_id = auth.uid()) then
    raise exception 'the owner must transfer ownership or delete the circle'
      using errcode = 'P0001', hint = 'owner';
  end if;
  update public.memberships set status = 'removed'
   where circle_id = p_circle and user_id = auth.uid() and status = 'active';
end $$;

-- Owner hands the circle to another active member (who becomes owner;
-- the old owner becomes admin).
create function public.transfer_ownership(p_circle uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.circles where id = p_circle and owner_id = auth.uid()) then
    raise exception 'only the owner can transfer ownership' using errcode = '42501';
  end if;
  if not public.is_user_in_circle(p_new_owner, p_circle) then
    raise exception 'new owner must be an active member' using errcode = 'P0001';
  end if;
  update public.memberships set role = 'admin' where circle_id = p_circle and user_id = auth.uid();
  update public.memberships set role = 'owner' where circle_id = p_circle and user_id = p_new_owner;
  update public.circles set owner_id = p_new_owner where id = p_circle;
  insert into public.audit_logs (circle_id, actor_id, action, target)
  values (p_circle, auth.uid(), 'circle.ownership_transferred', p_new_owner::text);
end $$;

revoke execute on function public.preview_invite(text), public.accept_invite(text),
  public.leave_circle(uuid), public.transfer_ownership(uuid, uuid) from anon, public;
grant execute on function public.preview_invite(text), public.accept_invite(text),
  public.leave_circle(uuid), public.transfer_ownership(uuid, uuid) to authenticated;

-- ------------------------------------------------------------ assignment
-- Owners/admins may always assign; plain members too when the circle's
-- settings allow it. Dependents never assign to others.
create or replace function public.can_assign(p_circle uuid, p_assignee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_assignee is null
      or p_assignee = (select auth.uid())
      or (public.is_user_in_circle(p_assignee, p_circle)
          and (public.has_circle_role(p_circle, array['owner', 'admin']::public.member_role[])
               or (public.has_circle_role(p_circle, array['member']::public.member_role[])
                   and coalesce((select (c.settings_json ->> 'members_can_assign')::boolean
                                 from public.circles c where c.id = p_circle), false))));
$$;

-- Admin actions on reminders go in the audit log.
create function public.reminders_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.assigned_to is not null and new.assigned_to <> new.created_by
     and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to) then
    insert into public.audit_logs (circle_id, actor_id, action, target, meta_json)
    values (new.circle_id, coalesce(auth.uid(), new.created_by), 'reminder.assigned',
            new.assigned_to::text, jsonb_build_object('reminder_id', new.id, 'title', new.title));
  end if;
  return new;
end $$;
create trigger reminders_audit after insert or update of assigned_to on public.reminders
  for each row execute function public.reminders_audit();

-- Circle settings (members_can_assign, …) are owner/admin-editable via the
-- existing circles_update policy; the guard keeps plan/owner/type fixed.
