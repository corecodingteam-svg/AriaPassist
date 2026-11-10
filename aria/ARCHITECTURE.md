# Aria architecture

## 1. Layers

```
presentation (features/*)  ──reads/writes──▶  LocalStore (Drift/SQLite)
                                                 │  outbox
                                                 ▼
                                            SyncEngine ◀──▶ Supabase (PostgREST + RLS)
```

The UI **only** talks to the local database. The network is never on the
critical path: reminders, lists and settings work fully offline, and cold
start does no network I/O (`Supabase.initialize` only restores the cached
session).

State: Riverpod 3 (`Notifier`/`Provider`). Navigation: go_router with a
`StatefulShellRoute` (Today · mic · Lists) and an auth redirect driven by
`AuthRepository` as a `Listenable`.

## 2. Multi-tenancy (tenant = Circle)

* Sign-up trigger `handle_new_user` creates `users`, a **personal Circle**
  (owner membership added by `circles_add_owner`) and `user_settings`.
* Every tenant-owned row carries `circle_id`. Access is enforced **only** in
  Postgres via RLS; the client is never trusted for circle, role, plan or
  author.
* Policy helpers (`is_circle_member`, `has_circle_role`, `can_access_list`, …)
  are `SECURITY DEFINER` with a pinned `search_path`, so policies can read
  `memberships` without recursing into its RLS.
* **Private vs shared:** a private reminder, list or note is visible only to
  its creator (and the assignee, for reminders), even inside a shared Circle.
* **Guard triggers** cover what RLS can't express:
  * `circles_guard` makes `plan_id`, `owner_id` and `type` server-managed.
    Client inserts are forced onto the free plan.
  * `memberships_guard` keeps personal Circles single-member and enforces
    **seat limits** from `plans.max_seats`.
  * `immutable_ownership` stops rows moving between Circles or changing
    author.
  * `memberships_audit` writes `audit_logs` entries for adds, removals and
    role changes.
* Owners can't be demoted or removed from the client. Only the owner can
  grant admin.
* Subscriptions are attached to the Circle and written only by billing
  webhooks (service role, Phase 7).

Verified by `supabase/tests/database/01_tenancy_rls.test.sql` (37 assertions).

## 3. Sync

**Write path.** `LocalStore.write(table, row)` runs one SQLite transaction
that does two things:

1. Upserts the row locally.
2. Puts the change in `sync_outbox`. Only the newest pending change per
   entity is kept, so repeated offline edits don't pile up.

Deletes are soft (`deleted_at`) and sync like any other change.

**Push.** The engine reads outbox entries whose time has come and upserts
each one. On failure it stores the error and retries later, with
exponential backoff and jitter (2 s, 4 s, 8 s and so on, capped at
10 minutes). A timer wakes the engine when the next retry is due.

**Pull.** Each table has a cursor `(updated_at, id)` in `sync_cursors`. The
engine asks for rows that are strictly after that cursor, ordered by
`(updated_at, id)`, in pages of 500. Using the id as a tie-breaker means no
rows are skipped when several share a timestamp. A page of rows and the
cursor move are saved in one transaction.

**Conflicts.** `updated_at` is stamped by the server (trigger), never the
client:
* The server's copy is ordered by arrival: last write wins.
* On the device, a row that still has a local change waiting to be pushed
  is *not* overwritten by a pull. The local edit is pushed next and then
  becomes the latest version.
* Phase 2 will move reminders to field-by-field merging, and Phase 5 will
  merge list items one item at a time.

**Triggers.** The engine syncs at these moments:
* app start and resume
* when the network comes back
* 1.5 s after a local write
* when a retry timer fires

Requests that arrive during a pass join it. A follow-up pass runs inside the
same future, so callers wait until their change is actually covered.

**Mapping.** The local tables use the same column names as Postgres. That
lets the engine move rows generically. Columns that exist only on the
server, such as `notes.embedding`, are dropped. JSON fields are stored as
text, and dates as ISO-8601 text.

**Known gap:** a Postgres transaction that commits after a later one with an
earlier `now()` could be missed by the cursor. Phase 6 adds Realtime
plus a periodic full resync, which closes this.

## 4. Theming

* Design tokens live in `AriaTokens`, a `ThemeExtension`. That covers
  palette, radii, spacing and motion; read them with `context.tokens`.
* 8 presets, each with light and dark palettes. Derived colours (text on
  primary, the gradient end) are computed so that they always meet WCAG AA.
* `ThemeController` (a Notifier) saves to SharedPreferences, which is loaded
  before the first frame so the theme never flashes. Changes rebuild
  `MaterialApp` instantly. `theme_json` in `user_settings` syncs in Phase 4.
* Font size multiplies the phone's own text-size setting. Reduce motion (or
  the OS setting) turns off animations and page transitions.
* A custom accent colour is applied only if it passes AA. Otherwise the app
  quietly uses the preset colour.
* `test/core/theme_test.dart` checks AA contrast for all 32 variants
  (8 presets × light/dark × normal/high-contrast). A test also keeps preset
  ids in sync with the `theme_presets` seed.

## 5. Reminders and notifications

**Source of truth.** The device fires reminders from its local database. The
server is never needed to fire one. All of the reminder logic lives in
`features/reminders/domain` as pure functions with no I/O, so it is unit
tested exhaustively.

**Recurrence.** Repeats use a subset of the RFC 5545 RRULE format:

| Supported | Rejected |
|---|---|
| DAILY, WEEKLY, MONTHLY, YEARLY | Ordinals like "2nd Monday" |
| INTERVAL | BYSETPOS |
| BYDAY (weekly) | Any other part of the standard |
| BYMONTHDAY (monthly, including -1 for the last day) | |
| COUNT, UNTIL | |

`tryParse` rejects anything outside the subset, so the Phase 3 language
parser can't produce a rule the engine would compute wrongly.

Repeats are worked out in the reminder's own timezone, on wall-clock time:
"8 AM daily" stays at 8 AM through daylight-saving changes. A date that
doesn't exist in a month, such as the 31st, is skipped, as RFC 5545
specifies. "Last day of the month" (`BYMONTHDAY=-1`) covers the common
intent.

**One rule for recurring reminders.** `start_at` is always the *next pending
occurrence*. When a reminder is done or missed, `start_at` moves forward and
`COUNT` goes down by one. "When is it due?" is therefore just
`snoozed_until ?? start_at`. That keeps the Today screen, sync and conflict
handling simple, because there is no separate table of occurrences.

**The state machine** (`ReminderLogic`) handles:
* complete
* snooze
* `reconcileMissed`: once the follow-up window has passed, an occurrence is
  logged as missed, the series moves on, and long absences fast-forward
  instead of logging hundreds of misses
* reschedule

Event ids for done and missed are deterministic (uuid v5 of reminder,
occurrence and type). Two devices logging the same miss produce one row,
not two.

**Planning alerts.** `planAlerts` is a pure function that produces the full
set of OS notifications that should be pending:
* each occurrence plus its follow-ups
* the next 4 occurrences of every repeating reminder, so a daily pill keeps
  ringing even if the app isn't opened for days
* only reminders that alert on this user's phone
* sorted and capped at 60, because iOS allows 64 pending notifications

**Applying the plan.** `LocalNotificationGateway.apply` compares the plan
with what is already pending. It cancels alerts that are no longer wanted
and adds or replaces the rest. It never cancels alerts already on screen.
Notification ids are a stable hash of reminder, occurrence and attempt.

**Keeping notifications in step.** `ReminderService.refresh()` reconciles
missed occurrences and then applies the plan. It runs:
* on any data change, including a sync pull
* when the app resumes
* once a minute while the app is in the foreground
* after any notification action

Overlapping calls are merged into one.

**Done and Snooze from a notification.** These buttons work while the app is
closed. A background isolate (`onBackgroundNotificationAction`):
1. opens the same SQLite database (Drift `shareAcrossIsolates`)
2. applies the action through the same `ReminderService`
3. re-plans the notifications
4. leaves the change in the outbox, which syncs on the next app run

**Platform details.**

| | Android | iOS |
|---|---|---|
| Channels and levels | One channel per category, plus Urgent, Quiet (low priority) and Vibrate-only | Time-sensitive for urgent, passive for low |
| Alarms | Exact alarms (`SCHEDULE_EXACT_ALARM`), inexact if the user declines | Rolling 60-notification window |
| After reboot or update | Plugin's boot receiver re-arms scheduled alerts | Not needed |
| Urgent | Full-screen intent; opens the alert screen after unlock | Time-sensitive alert |
| Actions | Done, 15 min, 1 h, Open | Same actions via a notification category |

**Timezone changes.** The app re-checks the device timezone each time it
resumes. Alerts are stored as absolute instants, so they still fire at the
right moment. Times on screen and new reminders follow the new zone.

**Known gaps (later phases)**
* Voice delivery and auto-fallback rules arrive in Phase 3. Until then,
  reminders set to voice arrive as text notifications.
* Default times, snooze length and follow-up settings become user settings
  in Phase 4.
* A dedicated lock-screen alert for urgent reminders, and per-brand Android
  battery guidance, come in Phases 4 and 8.

## 6. Voice

**Parsing.** Parsing is hybrid (`ParserService`):
1. **On-device rules first.** `RuleParser` runs on every utterance. Clear
   commands (query, done, snooze, delete, list item, note) and simple
   single reminders with a time are handled locally: instant, free and
   private.
2. **Claude for the rest.** Everything else goes to the `parse` Edge
   Function (`claude-haiku-5-5`, structured outputs via
   `messages.parse` and a Zod schema) with a 4-second budget.
3. **Double validation.** The function checks the output (RRULE subset,
   datetimes, ids the client didn't send are dropped). The app checks it
   again in `ParsedCommand.fromJson`.
4. **Fallback.** Offline, timeout, refusal, rate limit (20 per minute per
   user) or invalid output: the rule parser's result is used.

**Conversation.** `AssistantController` runs the talk sheet:
listen, parse, then show confirmation cards. You can tap ✓, or say "yes",
"no", or "make it 8 pm". Commands run immediately. Questions are answered
from local data.

**What Aria says.** `Phrases` covers 5 personalities × 3 languages, with
masculine or feminine Hindi verb forms depending on the voice. Phrasing
varies by a seed but stays deterministic, so rendered audio can be cached.

**Delivering voice reminders**

| | |
|---|---|
| Plan | `planAlerts` attaches `spoken` text when the effective mode is voice or both. The mode comes from the reminder, then its category, then the default. Quiet hours mark alerts `quiet`, so they are delivered silently, with an urgent exception. |
| iOS | The spoken line is rendered to `Library/Sounds/aria_<hash>.caf` (16-bit PCM, checked by an integration test) and used as the notification's sound. It plays while the app is closed and obeys the silent switch. |
| Android | Voice alerts post on a silent "Spoken reminders" channel. An exact alarm (`android_alarm_manager_plus`) runs `spokenAlarmCallback` in a background isolate. That callback checks the ringer mode and speaks via native TextToSpeech in `packages/aria_device`. |
| Fallback | Phone on silent or vibrate: Android skips the speech and iOS's silent switch mutes it. The text notification always remains. Calendar-busy and driving rules need extra permissions (Phase 8). |
| Briefings | Morning and night alerts are computed from the agenda on every refresh. The night wrap-up's "Move pending to tomorrow" action reschedules today's unfinished one-time reminders. |

**`aria_device`** is a local plugin, written for Swift Package Manager and
built-in Kotlin, so there is no CocoaPods or Kotlin Gradle plugin. It
covers ringer mode, `speak`, `stop`, and `synthesizeToFile` (iOS). It
replaced `flutter_tts`, which needed CocoaPods on iOS.

**Not yet verified on hardware:** Android spoken alarms; speech
recognition with a real microphone; how the iOS voice sounds in the real
notification sound.

## 7. Settings, simplification and entry points

**Where settings live.** There are three local settings objects:
`ThemeSettings`, `VoiceSettings` and `AppPrefs` (Simplify, Privacy and
reminder-style extras). Each is a Riverpod Notifier backed by
SharedPreferences, so it applies instantly and works offline.

**Settings sync.** `SettingsSync` maps the three objects onto the
`user_settings` columns (`SettingsMapping`, unit-tested against the
database's check constraints).
* **Push:** after a 2-second debounce.
* **Pull:** at sign-in, the server copy wins only if it is newer than this
  device's last local change.
* **Never synced:** state that belongs to this device, such as onboarding
  progress and dismissed tips. A name on the device is never replaced by an
  empty one from the server.
* **Legacy data:** `"HH:mm"` strings in older rows are accepted.

**Where each setting takes effect**

| Setting | Applied in |
|---|---|
| Simple Mode | `AriaApp` (XL text), `HomeShell` (no Lists tab), Today (no filters or search) |
| 12/24-hour format | `MediaQuery.alwaysUse24HourFormat` override |
| Date style | `PrefsScope` → `formatDate` |
| Default times | `RuleParser(dayParts)` and the editor's time chips |
| Defaults (snooze, category, priority, follow-up) | Editor, voice drafts, swipe-to-snooze |
| Lock-screen hiding, full-screen urgent | `GatewayOptions`; changes alter the payload, so affected alerts are rescheduled |

**Onboarding.** `authRedirect(onboarded:)` sends signed-in users to
`/onboarding` until they finish. The router refreshes on auth and
onboarding changes through `Listenable.merge`.

**Privacy and the session**
* **Sign-out** (`SessionService`): makes a final sync attempt, cancels
  every alert and spoken alarm, wipes the local database (`AppDatabase.wipe`),
  then signs out.
* **Account deletion:** `request_account_deletion()` sets a purge date
  7 days out. A daily `pg_cron` job runs `purge_deleted_accounts()`, and
  deleting the auth user cascades to all of their data. Signing in during
  the grace period shows a "Keep my account" banner.
* **App lock:** `AppLockGate` uses `local_auth` (biometrics with the device
  PIN as fallback). It locks at launch and after 30 seconds in the
  background.

**Reliability.** `runReliabilityChecks` covers notifications, exact alarms,
battery optimisation and the phone maker's own battery saver. Each check has
a one-tap fix, through `aria_device` on Android. The same checks drive the
onboarding permissions step and the troubleshooter, which also sends a test
reminder through the exact-alarm path.

**Entry points.** Widgets get their data from `WidgetSnapshot.build`
(pure, tested) through `home_widget`. Taps arrive as `aria:///…` links:
* widgets through the `home_widget` click stream
* the Quick Settings tile and shortcuts through the router

`/talk` goes to `/today?talk=1`, which opens the Talk sheet, including
when Today is already on screen.

## 8. Lists, notes, people, routines, progress

**Lists.** `lists` holds the list and `list_items` holds one row per item,
so sync merges item by item: two people adding to Grocery never conflict.
* Adding the same open item again bumps its quantity.
* `findOrCreate` matches spoken names by name or by type ("shopping" →
  Grocery).
* "Added by Neha" comes from a pull-only `users` mirror that holds names
  only. Phones and emails are never mirrored.

**Realtime.** `lists`, `list_items`, `notes`, `reminders` and `people` are
in the `supabase_realtime` publication. Postgres-changes respect RLS. The
app (`realtimeSyncProvider`) treats any event as "pull now" through the
existing sync engine, so there is a single write path.

**Notes search** combines two layers:
* **On-device:** keyword overlap with synonyms, possessives and phone-number
  awareness. Instant and offline.
* **Semantic:** the `notes-search` Edge Function embeds the question and any
  not-yet-embedded notes with built-in `gte-small` (384 dimensions), then
  calls `match_notes` (SECURITY INVOKER, so RLS applies) using an HNSW
  cosine index.

Results above 0.78 similarity come first; keyword hits fill the rest. A
notes-specific trigger stops embedding writes from bumping `updated_at`,
which would otherwise re-sync every note to every device.

**People.** Saving a person creates or updates up to three linked reminders
with deterministic ids:
* 🎂 birthday (yearly)
* 💍 anniversary (yearly)
* 📞 "Call Dad" (every N days)

The call reminder carries `contact_json.keep_in_touch`. Completing it, or
tapping Call, restarts the clock from now (`ReminderLogic._restartFrom`) and
not from the old schedule. Reminder details show Call, WhatsApp and SMS,
with a pre-filled wish on birthdays and anniversaries.

**Routines.** Steps are stored in `steps_json`. The time, days and run
history (for streaks) are in `trigger_json`. Timed routines become
`AlertKind.routine` notifications (next 2 on allowed weekdays). A tap or
"start morning mode" opens the runner, which speaks each step and records
the run.

**Progress.** `streakFor` counts consecutive done occurrences until the
first miss, using the deterministic events. `WeeklyReport` reports on-time
% (within 30 minutes), bills paid on time, the longest streak, and a 7-day
chart. Celebrations (confetti and a spoken line) happen at milestones
(3, 7, 14, 30 … days) and when everything due today is done. They respect
reduce motion and can be turned off.

**Testing note.** Inside widget tests, never use `watch…().first` on Drift
streams. It stalls under the fake clock. Use one-shot `get()` queries for
one-shot reads (`missed()`, `events()`, `allNotes()`, `RoutinesRepository.all()`).

## 9. Circles (Phase 6)

**Server.** Migrations `20261113000001_circles.sql` and
`20261113000002_circles_select_owner.sql`.
* `circles.settings_json` holds `members_can_assign`, and
  `memberships.settings_json` holds the dependent's `simple_lock`.
* Invites are single-use. `used_at` and `used_by` are stamped by
  `accept_invite`.
* `preview_invite(token)` shows the Circle, inviter and role before joining,
  without the person being a member.
* `accept_invite(token)` (SECURITY DEFINER) checks that the invite exists and
  is unexpired and unused, then upserts the membership.
  `memberships_guard` still applies the seat limit, raising P0001 with hint
  `upgrade_required`, so a free-plan Circle stays single-seat until billing
  upgrades it.
* `leave_circle` refuses owners. `transfer_ownership` demotes the old owner
  to admin and is audited.
* `can_assign`: owners and admins always; members only when
  `members_can_assign` is on. Dependents never.
* `reminders_audit` logs `reminder.assigned`.
* The circles SELECT policy also admits `owner_id = auth.uid()`, because the
  owner's membership is created by an AFTER trigger and
  `INSERT … RETURNING` would otherwise be rejected.

Verified by `05_circles.test.sql` (21 assertions) and the two-user
`integration_test/circles_test.dart`.

**Client.**
* `CircleRepository` reads the synced `circles`, `memberships` and `users`.
  Writes that need authority go through `CircleApi`, implemented on Supabase
  RPCs and tables with RLS. Every operation is followed by `syncNow()`.
* The active Circle is `AppPrefs.activeCircleId`, falling back to personal
  when you leave or are removed. It scopes new reminders, lists, notes and
  people.
* Ownership drives alerts: `Reminder.owner = assignedTo ?? createdBy`.
  Assigned reminders therefore leave the creator's Today and alert plan and
  appear on the assignee's phone after sync. Realtime triggers the pull.
* `assignedByMeProvider` powers "Reminders you assigned" (dependent
  monitoring).
* Assigned reminders stay `private`. RLS already shows them to creator and
  assignee, so "Share with Circle" is offered only for your own reminders.

**Dependents and the Simple Mode lock.**
* `simpleModeProvider = prefs.simpleMode || (lock != null && !unlocked)`.
* An admin stores a salted SHA-256 PIN hash on the dependent's membership.
  The dependent can read it, but RLS stops them changing it.
* Turning Simple Mode off asks for the PIN. A correct PIN unlocks it for the
  session (`simpleUnlockedProvider`), which resets on account change.
* This is a convenience lock, not a security boundary. The real restrictions
  (no managing members, no assigning) are enforced by RLS.

**Testing note.** `watchMyCircles` uses `asyncMap` with a one-shot count
query. An earlier `asyncExpand` over a second live stream buffered every
later emission forever, so new Circles never appeared. The widget tests
caught it.

**Deferred.**
* FCM push for assigned reminders.
* Joining from a deep link while signed out. The link is dropped after
  sign-in; enter the code under Circle › Join with a code.

## 10. Subscriptions and entitlements (Phase 7)

**Source of truth.** `circles.plan_id` is derived and never set by clients
(`circles_guard`).
* The `subscriptions_refresh` trigger runs `refresh_circle_plan()` after any
  subscription change. It picks the highest-ranked subscription that still
  entitles: `trialing`, `active`, `past_due` (store grace) or `canceled`
  with time left. Otherwise the Circle is on Free.
* So a cancelled Team purchase keeps Team until it ends, then falls back to
  a still-running Family trial, then to Free.

**Writes.**
* `apply_billing_event(jsonb)` (service role only) takes a normalised
  event, checks the purchaser owns the Circle, and upserts on
  `(provider, external_ref)`. It records `billing_events`, which is both
  the billing history and idempotency per `(provider, event_id)`.
* Edge Functions verify each provider before calling it:
  * `revenuecat-webhook` checks the Bearer secret. The app logs in to
    RevenueCat with the Supabase user id and sets the subscriber attribute
    `circle_id` before purchasing.
  * `razorpay-webhook` checks the HMAC-SHA256 of the raw body.
  * `razorpay-checkout` creates a hosted subscription for the owner.
* The webhook mapping is pure (`_shared/billing.ts`) and Deno-tested.
* Owner RPCs:
  * `start_trial`: 7 days, once per Circle via a unique index, and the plan
    must fit the Circle (Personal for personal Circles, Family or Team for
    shared ones).
  * `redeem_promo`: case-insensitive, with max redemptions and expiry, once
    per Circle.
* `circle_billing()` gives members the plan, status, dates and seats.
* `expire_subscriptions()` runs every 15 minutes via pg_cron.

Verified by `06_billing.test.sql` (27 assertions) and
`integration_test/billing_test.dart`.

**Client.**
* `plansProvider` serves the cached catalogue (bundled fallback on first
  run) and refreshes from `plans`.
* `entitlementProvider` is the best plan across my active Circles.
  `planOfCircle` gives a Circle's own plan, which governs seats,
  assigning, the Simple Mode lock and the activity log.
* `requireFeature` / `requireCircleFeature` open `/paywall?feature=…`
  unless the feature is unlocked.
* `StoreBilling` wraps RevenueCat, or `UnavailableStoreBilling` when no
  keys are set. A purchase never unlocks anything locally: the app waits
  for the webhook to change the plan and then syncs it (`_awaitPlan`).

**Graceful downgrade.**
* `downgradeGuardProvider` resets the premium voice, theme and accent only
  once `entitlementSettledProvider` holds: Circles loaded and every plan id
  known. A slow start therefore can't strip a paying user's choices.
* Data is never deleted. Seats above the limit stay; only new joins are
  blocked by `memberships_guard`.
* Owners get a billing notification (`AlertKind.billing`) at 10 AM, 3 days
  before a renewal or end. Tapping it opens Subscription.

**Not built.**
* Live store purchases. This needs store products, a RevenueCat project and
  real devices; the code path is written but unexercised.
* Razorpay end to end. This needs a merchant account; signature and mapping
  are unit-tested.
* Regional pricing beyond what the stores provide.
* Gates for smart suggestions, location reminders, WhatsApp and widgets.
  These features don't exist yet, or (widgets) can't be meaningfully gated.

## 11. Phase 8: places, calendar, WhatsApp, suggestions, Hindi, telemetry

**Location reminders.**
* `Reminder.location` (`location_json`) holds a `LocationTrigger`: place,
  coordinates, radius, and whether it fires on arrive or leave.
  `startAt` may be null.
* `geofenceSyncProvider` mirrors my active location reminders into OS
  geofences through the `aria_device` plugin:
  * **iOS:** `UNLocationNotificationTrigger`. iOS watches the region itself,
    needs only While-Using permission, and is capped at 20 regions. Its
    userInfo carries flutter_local_notifications' keys, so taps and
    Done/Snooze use the same Dart handler.
  * **Android:** Play services `GeofencingClient` → `GeofenceReceiver`
    posts the notification and deep-links `aria:///reminder/<id>`. Specs
    are saved so `GeofenceBootReceiver` restores them after a reboot or
    update. "Allow all the time" is asked separately, with an explanation.
* Places are saved in `AppPrefs.places`, so they sync with settings.
  `matchPlace` treats synonyms across languages as the same place
  (home = ghar = घर).

**Calendar.**
* Read-only through EventKit / CalendarContract, so events never leave the
  phone.
* `todayEventsProvider` feeds Today. `ReminderService` pre-fetches today and
  tomorrow so the morning briefing can add "On your calendar: …".

**WhatsApp.**
* `whatsapp_optins` records explicit consent. The number comes from
  `auth.users.phone`, never typed in.
* Every minute, pg_cron runs `kick_whatsapp_dispatch()`, which uses pg_net
  to call `whatsapp-dispatch`. URL and secret come from Vault.
* The dispatcher calls `claim_whatsapp_due()`: due within 10 minutes, the
  owner has the `whatsapp` feature, at most once per occurrence through a
  unique outbox row. It then sends the template.
* `whatsapp-webhook` verifies `X-Hub-Signature-256`, then records receipts.
  A "done" reply completes the reminder through `apply_whatsapp_inbound`.
* One-off reminders are marked done on the server. For recurring ones the
  server only sets `last_done_at`; the app's `catchUpRemoteDone` advances
  the series on the next refresh.

**Suggestions.**
* `computeSuggestions` is pure and on-device: repeated one-offs → repeat;
  done consistently late → move the time; missed often → follow-ups.
* Accepting a suggestion is one tap. Dismissals are stored in
  `dismissedTips`, so they never come back.

**Localisation.**
* `tr('English text', [args])` looks up `kHindi`, with `{0}`
  placeholders, and falls back to English.
* Display-only enum and table labels translate through getters.
* `L10n.lang` follows Appearance › App language, or the phone's language.
  A change calls `rebuildAll()`, which rebuilds elements in place, so
  navigation is kept. Material strings and `DateFormat` switch locale too.
* `test/l10n_test.dart` scans `lib/`: every `tr()` key needs a Hindi entry
  with the same placeholders, and enum labels must translate.
* Spoken lines follow the *voice* language (`Phrases`), not the UI
  language.

**Telemetry.**
* `Telemetry` is backed by `FirebaseTelemetry` (Crashlytics + Analytics),
  or a no-op when the build has no Firebase config.
* `DeferredTelemetry` captures errors from the first line of `main()` and
  buffers until Firebase attaches after the first frame.
* Consent: analytics opt-in and crash reports on, both set in Privacy and
  applied by `telemetryConsentProvider`.
* Events are an enum with non-identifying parameters only. A test asserts
  reminder titles never appear.

**Accessibility.**
* `test/a11y_test.dart` runs Flutter's tap-target, label and contrast
  guidelines on 20 routes in light and dark, and checks for overflow at
  200 % text in English and Hindi.
* `theme_test.dart` also requires primary text buttons to reach AA on the
  background and surface of every preset.

## 12. Admin safety, suspension and renewal reminders

**No hand-edits.**
* All admin changes go through `admin_*` SECURITY DEFINER functions.
* Each one resolves the caller with `admin_actor(roles)`:
  * an API user listed in `admins` with a sufficient role; or
  * the database console or service role, as break-glass, named by
    `set_config('aria.actor', …)`.
* Each one requires a reason (`admin_log`) and writes to `admin_actions`.
  Triggers make that table append-only: no update, delete or truncate,
  even for the console.

**Suspension, in three layers:**
1. `auth.users.banned_until`, plus deleting sessions and refresh tokens, so
   there's no sign-in or token refresh.
2. The PostgREST pre-request hook `check_request()` (set on the
   `authenticator` role) returns HTTP 403 for every table and RPC call.
3. A restrictive `not_suspended` RLS policy on every public table. This
   covers Realtime and any path that skips PostgREST.

A guard trigger stops clients editing their own suspension fields. The app
checks `account_status()` on start and resume, which also updates
`last_seen_at` at most hourly, and redirects to `/suspended`. Reminders
already scheduled on the phone keep ringing.

**Reports.**
* The `reports` schema holds views owned by `postgres`, granted only to
  `support_readonly` and `service_role`.
* `support_readonly` sessions are read-only by default, with a 15 s
  statement timeout.
* The views include no reminder, note, list or place text. The schema is
  not exposed through the REST API.

**Tenure and renewals.**
* `circle_paid_until`: the latest paid-until per Circle, its plan and
  provider, and whether it auto-renews (store or Razorpay, active, not
  cancelled).
* `renewal_step(ends, auto, status, now)` maps that onto day-wide windows:
  d7, d3, d1, d0, p3 and p7 for plans that won't renew; courtesy at 3 days
  for auto-renew; `payment_issue` for `past_due`.
* `claim_renewal_notices()` writes a row per (Circle, recipient, period
  end, step, channel), whose uniqueness means each is sent once, and
  returns what to send.
* `renewal-dispatch` (pg_cron 04:30 UTC → pg_net) sends by WhatsApp
  template or email (Resend), or logs.
* In the app, `planBillingAlerts` schedules the same steps as local
  notifications for owners.
* `renewalBannerFor()` (pure) picks the most urgent banner: payment issue,
  then ending, then ended, then member info. Dismissing hides it until the
  next step.
* `circle_billing()` now also returns `auto_renews` and the recently lapsed
  plan.
* Expiry runs every 5 minutes. A RevenueCat `CANCELLATION` with
  `cancel_reason = CUSTOMER_SUPPORT` (a store refund) expires the
  subscription immediately.

## 13. Admin panel (`admin/`, Flutter web)

**Gate** (`adminRedirect`, pure): signed in → `aal2` (authenticator app) →
admin role. Otherwise the panel shows sign-in, MFA enrolment or
verification, or "no admin access".

**Enforced in the database too:**
* `admin_actor()` refuses any API admin whose JWT isn't `aal2`.
* `admin_me()` works at `aal1`, so the panel can ask for the second factor.

**Read API.** These are SECURITY DEFINER functions, role-checked through
`admin_reader()`. The panel never touches tables.
* `admin_overview()`: KPIs. MRR is the monthly equivalent of non-manual
  active and past-due subscriptions, gross.
* `admin_report(name)`: a whitelisted gateway to the `reports.*` views.
* `admin_search_users(q)`.
* `admin_user_detail(id)`: logs `user.viewed`. Returns metadata, Circles
  and plans, billing for owned Circles, renewal messages and admin history.
  Never reminder or note text; a test asserts this.
* `admin_list_promos()`, and `admin_list_admins()` (super only).

**Writes** reuse the `admin_*` functions from §12. The UI makes every
action ask for a reason, and destructive ones also need a typed
confirmation word.

**UI.** Riverpod plus go_router, with a NavigationRail on wide screens and
a drawer on narrow ones. `AdminApi` and `AdminAuth` are interfaces with
fakes in widget tests. The build is static and the page carries `noindex`.
