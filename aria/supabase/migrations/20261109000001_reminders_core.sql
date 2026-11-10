-- Phase 2: reminder lifecycle columns + syncable reminder events.

alter table public.reminders
  add column snoozed_until timestamptz,
  add column last_done_at  timestamptz;

-- Events sync like other tables (pull cursor needs updated_at). Ids are
-- deterministic for missed/done (uuid v5 of reminder+occurrence+type) so two
-- devices logging the same miss converge on one row.
alter table public.reminder_events
  add column occurrence_at timestamptz,
  add column created_at    timestamptz not null default now(),
  add column updated_at    timestamptz not null default now(),
  add column deleted_at    timestamptz;

create trigger set_updated_at before insert or update on public.reminder_events
  for each row execute function public.set_updated_at();
create index reminder_events_sync_idx on public.reminder_events (updated_at, id);

-- Upsert (retries, cross-device merges) needs UPDATE; only your own events,
-- and they can't be re-pointed at another reminder or user.
create policy reminder_events_update on public.reminder_events for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.can_access_reminder(reminder_id));

create function public.reminder_events_immutable() returns trigger
language plpgsql as $$
begin
  if new.reminder_id <> old.reminder_id or new.user_id <> old.user_id then
    raise exception 'reminder_id and user_id are immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger reminder_events_immutable before update on public.reminder_events
  for each row execute function public.reminder_events_immutable();
