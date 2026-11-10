-- Aria — core schema (Phase 1)
-- Tenant = Circle. Every tenant-owned row carries circle_id; access is
-- enforced by RLS (next migration). Synced tables have updated_at (stamped
-- by the server) and deleted_at (soft delete) for offline-first sync.

create extension if not exists vector with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------------ enums
create type public.circle_type          as enum ('personal', 'family', 'team');
create type public.member_role          as enum ('owner', 'admin', 'member', 'dependent');
create type public.member_status        as enum ('active', 'invited', 'removed');
create type public.visibility           as enum ('private', 'shared');
create type public.reminder_status      as enum ('active', 'done', 'missed', 'archived');
create type public.reminder_priority    as enum ('low', 'normal', 'high', 'urgent');
create type public.reminder_event_type  as enum ('fired', 'done', 'snoozed', 'missed');
create type public.subscription_status  as enum ('trialing', 'active', 'past_due', 'canceled', 'expired');

-- --------------------------------------------------------------- helpers
-- Server-stamped updated_at: the sync pull cursor depends on it, so clients
-- can never set it.
create function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ------------------------------------------------------------- catalogue
create table public.plans (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,            -- free | personal | family | team
  name             text not null,
  max_seats        int  not null check (max_seats > 0),
  features_json    jsonb not null default '{}'::jsonb,
  price_month_inr  int  not null default 0 check (price_month_inr >= 0),
  price_year_inr   int  not null default 0 check (price_year_inr >= 0),
  trial_days       int  not null default 0,
  sort             int  not null default 0,
  is_active        boolean not null default true
);

create table public.voices (
  id           text primary key,
  name         text not null,
  language     text not null,          -- en-IN | hi-IN | en-GB | hinglish
  gender       text not null,
  description  text not null,
  provider     text not null,          -- google | azure | elevenlabs | device
  provider_voice_name text,
  is_free      boolean not null default false,
  sort         int not null default 0
);

create table public.theme_presets (
  id           text primary key,       -- matches ThemePresets ids in the app
  label        text not null,
  tokens_json  jsonb not null,         -- { light: {...}, dark: {...} }
  is_free      boolean not null default false,
  sort         int not null default 0
);

-- ------------------------------------------------------------- identity
create table public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text check (char_length(name) <= 80),
  phone       text,
  email       text,
  locale      text not null default 'en-IN',
  timezone    text not null default 'Asia/Kolkata',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- -------------------------------------------------------------- tenancy
create table public.circles (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  type        public.circle_type not null default 'family',
  owner_id    uuid not null references public.users (id) on delete cascade,
  plan_id     uuid references public.plans (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create unique index circles_one_personal_per_user
  on public.circles (owner_id) where type = 'personal';

create table public.memberships (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles (id) on delete cascade,
  user_id     uuid not null references public.users (id) on delete cascade,
  role        public.member_role   not null default 'member',
  status      public.member_status not null default 'active',
  joined_at   timestamptz default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (circle_id, user_id)
);
create index memberships_user_idx on public.memberships (user_id) where status = 'active';

create table public.invites (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles (id) on delete cascade,
  token       text not null unique default encode(extensions.gen_random_bytes(18), 'hex'),
  role        public.member_role not null default 'member' check (role <> 'owner'),
  expires_at  timestamptz not null default now() + interval '7 days',
  created_by  uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------ reminders
create table public.reminders (
  id               uuid primary key default gen_random_uuid(),
  circle_id        uuid not null references public.circles (id) on delete cascade,
  created_by       uuid not null default auth.uid() references public.users (id) on delete cascade,
  assigned_to      uuid references public.users (id) on delete set null,
  title            text not null check (char_length(title) between 1 and 200),
  category         text not null default 'personal'
                   check (category in ('health', 'bills', 'people', 'home', 'work', 'personal')),
  priority         public.reminder_priority not null default 'normal',
  start_at         timestamptz,
  all_day          boolean not null default false,
  rrule            text check (char_length(rrule) <= 500),
  timezone         text,
  location_json    jsonb,
  notify_mode      text check (notify_mode in ('voice', 'text', 'both', 'vibrate', 'silent')),
  voice_id         text references public.voices (id) on delete set null,
  follow_up_json   jsonb,
  amount           numeric(12, 2),
  quantity_left    int,
  contact_json     jsonb,
  notes            text check (char_length(notes) <= 2000),
  visibility       public.visibility not null default 'private',
  status           public.reminder_status not null default 'active',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index reminders_circle_start_idx   on public.reminders (circle_id, start_at);
create index reminders_assignee_status_idx on public.reminders (assigned_to, status);
create index reminders_sync_idx           on public.reminders (updated_at, id);

create table public.reminder_events (
  id           uuid primary key default gen_random_uuid(),
  reminder_id  uuid not null references public.reminders (id) on delete cascade,
  user_id      uuid not null default auth.uid() references public.users (id) on delete cascade,
  type         public.reminder_event_type not null,
  at           timestamptz not null default now(),
  meta_json    jsonb
);
create index reminder_events_reminder_idx on public.reminder_events (reminder_id, at desc);

-- ------------------------------------------------------- lists & notes
create table public.lists (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles (id) on delete cascade,
  created_by  uuid not null default auth.uid() references public.users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  type        text not null default 'custom'
              check (type in ('grocery', 'bills', 'work', 'packing', 'custom')),
  visibility  public.visibility not null default 'private',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index lists_circle_idx on public.lists (circle_id);
create index lists_sync_idx   on public.lists (updated_at, id);

create table public.list_items (
  id           uuid primary key default gen_random_uuid(),
  list_id      uuid not null references public.lists (id) on delete cascade,
  text         text not null check (char_length(text) between 1 and 300),
  qty          numeric(10, 2),
  done         boolean not null default false,
  added_by     uuid default auth.uid() references public.users (id) on delete set null,
  assigned_to  uuid references public.users (id) on delete set null,
  position     double precision not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index list_items_list_idx on public.list_items (list_id, position);
create index list_items_sync_idx on public.list_items (updated_at, id);

create table public.notes (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles (id) on delete cascade,
  created_by  uuid not null default auth.uid() references public.users (id) on delete cascade,
  text        text not null check (char_length(text) between 1 and 5000),
  -- 384 dims = Supabase's built-in gte-small model (Phase 5 semantic search).
  embedding   extensions.vector(384),
  visibility  public.visibility not null default 'private',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index notes_circle_idx on public.notes (circle_id);
create index notes_sync_idx   on public.notes (updated_at, id);

create table public.routines (
  id            uuid primary key default gen_random_uuid(),
  circle_id     uuid not null references public.circles (id) on delete cascade,
  user_id       uuid not null default auth.uid() references public.users (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 80),
  trigger_json  jsonb,
  steps_json    jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index routines_sync_idx on public.routines (updated_at, id);

-- -------------------------------------------------------------- settings
create table public.user_settings (
  user_id                  uuid primary key references public.users (id) on delete cascade,
  active_circle_id         uuid references public.circles (id) on delete set null,
  voice_id                 text not null default 'aria' references public.voices (id),
  pa_name                  text not null default 'Aria' check (char_length(pa_name) between 1 and 30),
  speed                    numeric(3, 2) not null default 1.00 check (speed between 0.75 and 1.50),
  pitch                    numeric(3, 2) not null default 1.00 check (pitch between 0.50 and 2.00),
  personality              text not null default 'friendly'
                           check (personality in ('friendly', 'professional', 'coach', 'caring', 'short')),
  language                 text not null default 'en' check (language in ('en', 'hi', 'hinglish')),
  notify_mode_default      text not null default 'both'
                           check (notify_mode_default in ('voice', 'text', 'both', 'vibrate', 'silent')),
  category_overrides_json  jsonb not null default '{}'::jsonb,
  theme_json               jsonb not null default '{}'::jsonb,
  simple_mode              boolean not null default false,
  quick_actions_json       jsonb not null default '[]'::jsonb,
  quiet_hours_json         jsonb not null default '{"enabled": false, "start": "23:00", "end": "07:00", "allow_urgent": true}'::jsonb,
  follow_up_json           jsonb not null default '{"enabled": true, "every_min": 10, "max_attempts": 3}'::jsonb,
  briefing_json            jsonb not null default '{"morning": {"enabled": true, "at": "07:30"}, "night": {"enabled": true, "at": "22:00"}}'::jsonb,
  extra_json               jsonb not null default '{}'::jsonb,   -- forward-compatible bucket for Phase 4 toggles
  updated_at               timestamptz not null default now()
);

-- --------------------------------------------------------- subscriptions
create table public.subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  circle_id           uuid not null references public.circles (id) on delete cascade,
  plan_id             uuid not null references public.plans (id),
  provider            text not null check (provider in ('revenuecat', 'razorpay', 'manual')),
  status              public.subscription_status not null,
  current_period_end  timestamptz,
  trial_end           timestamptz,
  external_ref        text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index subscriptions_circle_idx on public.subscriptions (circle_id);
-- A circle gets one free trial ever.
create unique index subscriptions_one_trial_per_circle
  on public.subscriptions (circle_id) where trial_end is not null;

-- ------------------------------------------------------------ audit log
create table public.audit_logs (
  id         uuid primary key default gen_random_uuid(),
  circle_id  uuid not null references public.circles (id) on delete cascade,
  actor_id   uuid references public.users (id) on delete set null,
  action     text not null,
  target     text,
  meta_json  jsonb,
  at         timestamptz not null default now()
);
create index audit_logs_circle_idx on public.audit_logs (circle_id, at desc);

-- ---------------------------------------------------- updated_at triggers
do $$
declare t text;
begin
  foreach t in array array['users', 'circles', 'memberships', 'reminders', 'lists',
                           'list_items', 'notes', 'routines', 'user_settings', 'subscriptions']
  loop
    execute format(
      'create trigger set_updated_at before insert or update on public.%I
         for each row execute function public.set_updated_at()', t);
  end loop;
end $$;
