-- Phase 4: in-app account deletion with a 7-day grace period (spec 6.9,
-- Play/App Store account-deletion policy, DPDP Act 2023).

create table public.account_deletions (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  requested_at timestamptz not null default now(),
  purge_after  timestamptz not null
);
alter table public.account_deletions enable row level security;
create policy account_deletions_select on public.account_deletions
  for select to authenticated using (user_id = (select auth.uid()));

-- Schedules deletion of the caller's account 7 days from now.
create function public.request_account_deletion()
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare v_after timestamptz;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  insert into public.account_deletions (user_id, purge_after)
  values (auth.uid(), now() + interval '7 days')
  on conflict (user_id) do update set requested_at = now(), purge_after = excluded.purge_after
  returning purge_after into v_after;
  return v_after;
end $$;

-- Changing your mind within the grace period.
create function public.cancel_account_deletion()
returns void language sql security definer set search_path = '' as $$
  delete from public.account_deletions where user_id = (select auth.uid());
$$;

-- Deletes accounts whose grace period has ended. Deleting auth.users
-- cascades to public.users and every row they own (circles they own,
-- memberships, reminders, events, lists, notes, settings).
create function public.purge_deleted_accounts()
returns int language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
  with gone as (
    delete from auth.users u
    using public.account_deletions d
    where d.user_id = u.id and d.purge_after <= now()
    returning u.id
  )
  select count(*) into v_count from gone;
  return v_count;
end $$;

revoke execute on function public.request_account_deletion() from anon, public;
revoke execute on function public.cancel_account_deletion() from anon, public;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;
-- Only the scheduler (postgres) may purge.
revoke execute on function public.purge_deleted_accounts() from anon, authenticated, public;

-- Daily purge at 03:17 UTC.
create extension if not exists pg_cron;
select cron.schedule('aria-purge-deleted-accounts', '17 3 * * *',
                     'select public.purge_deleted_accounts()');
