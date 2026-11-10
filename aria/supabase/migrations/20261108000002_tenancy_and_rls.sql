-- Aria — multi-tenant access control.
-- Rule of thumb: never trust the client for circle_id, role, plan or
-- authorship. RLS decides visibility; guard triggers block tampering with
-- columns RLS can't express (immutable ownership, server-managed plan).

-- ============================================================ helper fns
-- SECURITY DEFINER so policies can consult memberships without recursing
-- into memberships' own RLS. search_path pinned for safety.

create function public.is_circle_member(p_circle uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.circle_id = p_circle
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.deleted_at is null
  );
$$;

create function public.has_circle_role(p_circle uuid, p_roles public.member_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.circle_id = p_circle
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.deleted_at is null
      and m.role = any (p_roles)
  );
$$;

create function public.is_user_in_circle(p_user uuid, p_circle uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.circle_id = p_circle and m.user_id = p_user
      and m.status = 'active' and m.deleted_at is null
  );
$$;

create function public.shares_circle_with(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.memberships a
    join public.memberships b on b.circle_id = a.circle_id
    where a.user_id = (select auth.uid()) and a.status = 'active' and a.deleted_at is null
      and b.user_id = p_user           and b.status = 'active' and b.deleted_at is null
  );
$$;

-- Assignment rule (Phase 1): yourself, nobody, or — for owners/admins —
-- any active member of the same circle. Phase 6 makes this configurable.
create function public.can_assign(p_circle uuid, p_assignee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_assignee is null
      or p_assignee = (select auth.uid())
      or (public.has_circle_role(p_circle, array['owner', 'admin']::public.member_role[])
          and public.is_user_in_circle(p_assignee, p_circle));
$$;

create function public.can_access_reminder(p_reminder uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.reminders r
    where r.id = p_reminder
      and public.is_circle_member(r.circle_id)
      and (r.visibility = 'shared'
           or r.created_by = (select auth.uid())
           or r.assigned_to = (select auth.uid()))
  );
$$;

create function public.can_access_list(p_list uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.lists l
    where l.id = p_list
      and public.is_circle_member(l.circle_id)
      and (l.visibility = 'shared' or l.created_by = (select auth.uid()))
  );
$$;

create function public.free_plan_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.plans where code = 'free';
$$;

-- True when the statement comes from an app user (PostgREST switches role
-- to anon/authenticated); false for service_role, migrations and triggers
-- running as the definer.
create function public.is_client_request()
returns boolean language sql stable as $$
  select current_user in ('anon', 'authenticated');
$$;

-- ======================================================== guard triggers

-- circles: plan is server-managed (billing webhooks); owner/type immutable.
create function public.circles_guard() returns trigger
language plpgsql as $$
begin
  if public.is_client_request() then
    if tg_op = 'INSERT' then
      new.plan_id := public.free_plan_id();
    elsif new.plan_id is distinct from old.plan_id
       or new.owner_id <> old.owner_id
       or new.type <> old.type then
      raise exception 'plan, owner and type of a circle cannot be changed by the client'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger circles_guard before insert or update on public.circles
  for each row execute function public.circles_guard();

-- Every new circle gets its owner as an active 'owner' member.
create function public.circles_add_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.memberships (circle_id, user_id, role, status)
  values (new.id, new.owner_id, 'owner', 'active');
  return new;
end $$;
create trigger circles_add_owner after insert on public.circles
  for each row execute function public.circles_add_owner();

-- memberships: personal circles are single-user; seat limits per plan.
create function public.memberships_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_circle public.circles;
  v_seats  int;
  v_active int;
begin
  select * into v_circle from public.circles where id = new.circle_id;

  if v_circle.type = 'personal' and new.user_id <> v_circle.owner_id then
    raise exception 'personal circles cannot have other members' using errcode = '42501';
  end if;

  if new.status = 'active' and new.deleted_at is null
     and (tg_op = 'INSERT' or old.status <> 'active' or old.deleted_at is not null) then
    select coalesce(p.max_seats, 1) into v_seats
      from public.plans p where p.id = v_circle.plan_id;
    select count(*) into v_active
      from public.memberships m
      where m.circle_id = new.circle_id and m.status = 'active'
        and m.deleted_at is null and m.id <> new.id;
    if v_active >= coalesce(v_seats, 1) then
      raise exception 'seat limit reached for this circle''s plan (% seats)', coalesce(v_seats, 1)
        using errcode = 'P0001', hint = 'upgrade_required';
    end if;
  end if;

  if tg_op = 'UPDATE' and (new.circle_id <> old.circle_id or new.user_id <> old.user_id) then
    raise exception 'circle_id and user_id of a membership are immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger memberships_guard before insert or update on public.memberships
  for each row execute function public.memberships_guard();

-- Audit admin actions on memberships.
create function public.memberships_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Circle itself is being deleted (cascade): nothing left to audit.
  if not exists (select 1 from public.circles c where c.id = coalesce(new.circle_id, old.circle_id)) then
    return coalesce(new, old);
  end if;
  insert into public.audit_logs (circle_id, actor_id, action, target, meta_json)
  values (
    coalesce(new.circle_id, old.circle_id),
    auth.uid(),
    case tg_op
      when 'INSERT' then 'member.added'
      when 'DELETE' then 'member.removed'
      else case when new.status = 'removed' and old.status <> 'removed' then 'member.removed'
                when new.role <> old.role then 'member.role_changed'
                else 'member.updated' end
    end,
    coalesce(new.user_id, old.user_id)::text,
    jsonb_build_object('role', coalesce(new.role, old.role),
                       'old_role', case when tg_op = 'UPDATE' then old.role end)
  );
  return coalesce(new, old);
end $$;
create trigger memberships_audit after insert or update or delete on public.memberships
  for each row execute function public.memberships_audit();

-- Tenant rows can never move between circles or change author.
create function public.immutable_ownership() returns trigger
language plpgsql as $$
declare
  owner_col text := tg_argv[0];
  o jsonb := to_jsonb(old);
  n jsonb := to_jsonb(new);
begin
  if n -> 'circle_id' is distinct from o -> 'circle_id'
     or n -> owner_col is distinct from o -> owner_col then
    raise exception 'circle_id and % are immutable', owner_col using errcode = '42501';
  end if;
  return new;
end $$;
create trigger reminders_immutable before update on public.reminders
  for each row execute function public.immutable_ownership('created_by');
create trigger lists_immutable before update on public.lists
  for each row execute function public.immutable_ownership('created_by');
create trigger notes_immutable before update on public.notes
  for each row execute function public.immutable_ownership('created_by');
create trigger routines_immutable before update on public.routines
  for each row execute function public.immutable_ownership('user_id');

create function public.list_items_immutable() returns trigger
language plpgsql as $$
begin
  if new.list_id <> old.list_id then
    raise exception 'list_id is immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger list_items_immutable before update on public.list_items
  for each row execute function public.list_items_immutable();

-- =================================================== sign-up provisioning
-- On auth sign-up: profile row, personal Circle (owner membership is added
-- by circles_add_owner) and default settings.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_circle uuid;
begin
  insert into public.users (id, phone, email, name)
  values (new.id, new.phone, new.email,
          coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name'));

  insert into public.circles (name, type, owner_id, plan_id)
  values ('Personal', 'personal', new.id, public.free_plan_id())
  returning id into v_circle;

  insert into public.user_settings (user_id, active_circle_id)
  values (new.id, v_circle);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- =================================================================== RLS
alter table public.plans           enable row level security;
alter table public.voices          enable row level security;
alter table public.theme_presets   enable row level security;
alter table public.users           enable row level security;
alter table public.circles         enable row level security;
alter table public.memberships     enable row level security;
alter table public.invites         enable row level security;
alter table public.reminders       enable row level security;
alter table public.reminder_events enable row level security;
alter table public.lists           enable row level security;
alter table public.list_items      enable row level security;
alter table public.notes           enable row level security;
alter table public.routines        enable row level security;
alter table public.user_settings   enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.audit_logs      enable row level security;

-- Catalogue: readable by anyone (paywall before sign-in), writable by none.
create policy plans_read  on public.plans         for select to anon, authenticated using (is_active);
create policy voices_read on public.voices        for select to anon, authenticated using (true);
create policy themes_read on public.theme_presets for select to anon, authenticated using (true);

-- users
create policy users_select on public.users for select to authenticated
  using (id = (select auth.uid()) or public.shares_circle_with(id));
create policy users_update on public.users for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- circles
create policy circles_select on public.circles for select to authenticated
  using (public.is_circle_member(id));
create policy circles_insert on public.circles for insert to authenticated
  with check (owner_id = (select auth.uid()) and type <> 'personal');
create policy circles_update on public.circles for update to authenticated
  using (public.has_circle_role(id, array['owner', 'admin']::public.member_role[]))
  with check (public.has_circle_role(id, array['owner', 'admin']::public.member_role[]));
create policy circles_delete on public.circles for delete to authenticated
  using (owner_id = (select auth.uid()) and type <> 'personal');

-- memberships: owners/admins manage; nobody can create, alter or remove an
-- owner row from the client; only the owner can grant admin.
create policy memberships_select on public.memberships for select to authenticated
  using (public.is_circle_member(circle_id));
create policy memberships_insert on public.memberships for insert to authenticated
  with check (
    public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[])
    and role <> 'owner'
    and (role <> 'admin' or public.has_circle_role(circle_id, array['owner']::public.member_role[]))
  );
create policy memberships_update on public.memberships for update to authenticated
  using (
    public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[])
    and role <> 'owner'
  )
  with check (
    role <> 'owner'
    and (role <> 'admin' or public.has_circle_role(circle_id, array['owner']::public.member_role[]))
  );
create policy memberships_delete on public.memberships for delete to authenticated
  using (
    public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[])
    and role <> 'owner'
  );

-- invites (accepting is a SECURITY DEFINER function in Phase 6)
create policy invites_select on public.invites for select to authenticated
  using (public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[]));
create policy invites_insert on public.invites for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[])
  );
create policy invites_delete on public.invites for delete to authenticated
  using (public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[]));

-- reminders: private = creator + assignee only, even inside a shared circle.
create policy reminders_select on public.reminders for select to authenticated
  using (
    public.is_circle_member(circle_id)
    and (visibility = 'shared'
         or created_by = (select auth.uid())
         or assigned_to = (select auth.uid()))
  );
create policy reminders_insert on public.reminders for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and public.is_circle_member(circle_id)
    and public.can_assign(circle_id, assigned_to)
  );
create policy reminders_update on public.reminders for update to authenticated
  using (
    public.is_circle_member(circle_id)
    and (created_by = (select auth.uid())
         or assigned_to = (select auth.uid())
         or (visibility = 'shared'
             and public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[])))
  )
  with check (
    public.is_circle_member(circle_id)
    and public.can_assign(circle_id, assigned_to)
  );
create policy reminders_delete on public.reminders for delete to authenticated
  using (created_by = (select auth.uid()));

create policy reminder_events_select on public.reminder_events for select to authenticated
  using (public.can_access_reminder(reminder_id));
create policy reminder_events_insert on public.reminder_events for insert to authenticated
  with check (user_id = (select auth.uid()) and public.can_access_reminder(reminder_id));

-- lists / list_items
create policy lists_select on public.lists for select to authenticated
  using (public.is_circle_member(circle_id)
         and (visibility = 'shared' or created_by = (select auth.uid())));
create policy lists_insert on public.lists for insert to authenticated
  with check (created_by = (select auth.uid()) and public.is_circle_member(circle_id));
create policy lists_update on public.lists for update to authenticated
  using (public.is_circle_member(circle_id)
         and (visibility = 'shared' or created_by = (select auth.uid())))
  with check (public.is_circle_member(circle_id));
create policy lists_delete on public.lists for delete to authenticated
  using (created_by = (select auth.uid()));

create policy list_items_select on public.list_items for select to authenticated
  using (public.can_access_list(list_id));
create policy list_items_insert on public.list_items for insert to authenticated
  with check (public.can_access_list(list_id)
              and (added_by is null or added_by = (select auth.uid())));
create policy list_items_update on public.list_items for update to authenticated
  using (public.can_access_list(list_id)) with check (public.can_access_list(list_id));
create policy list_items_delete on public.list_items for delete to authenticated
  using (public.can_access_list(list_id));

-- notes
create policy notes_select on public.notes for select to authenticated
  using (public.is_circle_member(circle_id)
         and (visibility = 'shared' or created_by = (select auth.uid())));
create policy notes_insert on public.notes for insert to authenticated
  with check (created_by = (select auth.uid()) and public.is_circle_member(circle_id));
create policy notes_update on public.notes for update to authenticated
  using (created_by = (select auth.uid())) with check (public.is_circle_member(circle_id));
create policy notes_delete on public.notes for delete to authenticated
  using (created_by = (select auth.uid()));

-- routines are always personal
create policy routines_all on public.routines for all to authenticated
  using (user_id = (select auth.uid()) and public.is_circle_member(circle_id))
  with check (user_id = (select auth.uid()) and public.is_circle_member(circle_id));

-- user_settings
create policy user_settings_select on public.user_settings for select to authenticated
  using (user_id = (select auth.uid()));
create policy user_settings_update on public.user_settings for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid())
              and (active_circle_id is null or public.is_circle_member(active_circle_id)));

-- subscriptions: members can see their circle's plan; writes = webhooks only.
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (public.is_circle_member(circle_id));

-- audit log: owners/admins read; writes only via triggers.
create policy audit_logs_select on public.audit_logs for select to authenticated
  using (public.has_circle_role(circle_id, array['owner', 'admin']::public.member_role[]));

-- Helper functions are for policies, not for direct RPC by anonymous users.
revoke execute on function public.is_circle_member(uuid),
                           public.has_circle_role(uuid, public.member_role[]),
                           public.is_user_in_circle(uuid, uuid),
                           public.shares_circle_with(uuid),
                           public.can_assign(uuid, uuid),
                           public.can_access_reminder(uuid),
                           public.can_access_list(uuid),
                           public.free_plan_id()
  from anon, public;
