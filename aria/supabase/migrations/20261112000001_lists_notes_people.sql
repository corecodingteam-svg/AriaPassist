-- Phase 5: people (birthdays, keep-in-touch), realtime for shared data,
-- semantic note search.

-- --------------------------------------------------------------- people
create table public.people (
  id                uuid primary key default gen_random_uuid(),
  circle_id         uuid not null references public.circles (id) on delete cascade,
  created_by        uuid not null default auth.uid() references public.users (id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 80),
  relation          text check (char_length(relation) <= 40),
  phone             text check (char_length(phone) <= 20),
  birthday          date,
  anniversary       date,
  call_every_days   int check (call_every_days between 1 and 365),
  last_contact_at   timestamptz,
  visibility        public.visibility not null default 'private',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index people_circle_idx on public.people (circle_id);
create index people_sync_idx on public.people (updated_at, id);
create trigger set_updated_at before insert or update on public.people
  for each row execute function public.set_updated_at();
create trigger people_immutable before update on public.people
  for each row execute function public.immutable_ownership('created_by');

alter table public.people enable row level security;
create policy people_select on public.people for select to authenticated
  using (public.is_circle_member(circle_id)
         and (visibility = 'shared' or created_by = (select auth.uid())));
create policy people_insert on public.people for insert to authenticated
  with check (created_by = (select auth.uid()) and public.is_circle_member(circle_id));
create policy people_update on public.people for update to authenticated
  using (public.is_circle_member(circle_id)
         and (visibility = 'shared' or created_by = (select auth.uid())))
  with check (public.is_circle_member(circle_id));
create policy people_delete on public.people for delete to authenticated
  using (created_by = (select auth.uid()));

-- ------------------------------------------------------------- realtime
-- Postgres-changes respect RLS, so members only hear about rows they can
-- read. Clients treat an event as "pull now".
alter publication supabase_realtime add table
  public.lists, public.list_items, public.notes, public.reminders, public.people;

-- ------------------------------------------------------- semantic search
create index notes_embedding_idx on public.notes
  using hnsw (embedding extensions.vector_cosine_ops);

-- Nearest notes the caller can read (SECURITY INVOKER → RLS applies).
create function public.match_notes(query_embedding extensions.vector(384), match_count int default 5)
returns table (id uuid, text text, similarity float)
language sql stable set search_path = '' as $$
  select n.id, n.text, 1 - (n.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.notes n
  where n.deleted_at is null and n.embedding is not null
  order by n.embedding operator(extensions.<=>) query_embedding
  limit least(match_count, 20);
$$;

-- Writing embeddings must not look like a user edit (it would bump
-- updated_at and re-download every note to every device). Notes get their
-- own trigger function; the generic one is shared by tables without an
-- embedding column.
create function public.notes_set_updated_at() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'embedding' - 'updated_at')
       = (to_jsonb(old) - 'embedding' - 'updated_at') then
    new.updated_at := old.updated_at;
  else
    new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger set_updated_at on public.notes;
create trigger set_updated_at before insert or update on public.notes
  for each row execute function public.notes_set_updated_at();
