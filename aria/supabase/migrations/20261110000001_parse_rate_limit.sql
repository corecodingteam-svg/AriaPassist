-- Phase 3: per-user rate limit for the LLM parse Edge Function.
create table public.parse_requests (
  id       bigint generated always as identity primary key,
  user_id  uuid not null references public.users (id) on delete cascade,
  at       timestamptz not null default now()
);
create index parse_requests_user_at on public.parse_requests (user_id, at desc);
alter table public.parse_requests enable row level security; -- no policies: definer-only

-- Allows 20 parses per user per minute. Called by the parse function with
-- the user's JWT, so auth.uid() is the caller.
create function public.take_parse_token()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
  if auth.uid() is null then return false; end if;
  select count(*) into v_count from public.parse_requests
   where user_id = auth.uid() and at > now() - interval '1 minute';
  if v_count >= 20 then return false; end if;
  insert into public.parse_requests (user_id) values (auth.uid());
  -- Opportunistic cleanup keeps the table tiny.
  delete from public.parse_requests where at < now() - interval '1 hour';
  return true;
end $$;
revoke execute on function public.take_parse_token() from anon, public;
grant execute on function public.take_parse_token() to authenticated;
