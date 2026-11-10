# Aria — voice-first personal assistant

Flutter (Android + iOS) + Supabase. This repo is built in phases:

* **Phase 1 (foundation):** done. Design system, navigation, auth,
  multi-tenant schema with RLS, and the offline-first local DB + sync.
* **Phase 2 (reminders core):** done. Today timeline, create/edit, repeats,
  categories, priority, local notifications with Done/Snooze actions,
  follow-ups, snooze, the missed list and search.
* **Phase 3 (voice):** done. Talk to Aria (speech-to-text plus a keyboard
  fallback), Claude-powered parsing with an on-device fallback, confirmation
  cards, 7 voices with preview, 5 personalities, English, Hindi and
  Hinglish, voice reminders, reminder style (voice, text, both, vibrate or
  silent, per category), quiet hours, and the morning briefing and night
  wrap-up.
* **Phase 4 (settings and simplification):** done.
  * Onboarding: 8 steps, skippable after the first.
  * Every settings group from section 6, plus settings search.
  * Simple Mode, quick actions, configurable swipes, one-handed mode, and
    12/24-hour and date formats.
  * App lock, hiding reminders on the lock screen, data export, and account
    deletion with a 7-day grace period.
  * The "Reminders not ringing?" troubleshooter with phone-brand guidance.
  * Settings sync across devices.
  * Home-screen widgets, app shortcuts, and an Android Quick Settings tile.
* **Phase 5 (lists, notes, people, routines):** done.
  * Lists with quantities, reordering, and "added by" labels.
  * Shared lists update in realtime across your Circle.
  * A Bills view with this month's totals.
  * Notes you can ask for ("what's the Wi-Fi password?"), with on-device
    and semantic search.
  * People: birthdays, anniversaries and "call Dad every 2 weeks" nudges,
    with one-tap Call, WhatsApp and SMS.
  * Routines with spoken step-by-step guidance.
  * Streaks, a weekly report card and celebrations.
* **Phase 6 (Circles):** done.
  * Create Family or Team Circles and switch between them (Me › Circle).
  * Invite by share link (WhatsApp, SMS), QR code or code. Invites are
    single-use, expire after 7 days and set the role.
  * Roles: owner, admin, member and dependent. Owners and admins manage
    members, change roles, transfer ownership, and see an activity log.
  * Assign reminders to members ("For: Dad"). Assigned reminders ring only on
    the assignee's phone, and the assigner sees whether each is pending, done
    or missed.
  * "From Asha" labels, plus "Share with Circle" for reminders, lists, notes
    and people.
  * Dependents start in Simple Mode. An admin can lock it with a 4-digit
    PIN; only a salted hash is stored.
  * Seat limits come from the plan. The free plan has 1 seat, so joining
    someone's Circle needs Family or Team, which arrive with Phase 7 billing.
  * Not included: push notifications for assigned reminders (FCM needs a
    Firebase project). Assigned reminders arrive through realtime sync and
    are scheduled locally on the assignee's phone.
* **Phase 7 (subscriptions):** done, apart from store and payment accounts
  (see Production setup).
  * Plans (Free, Personal ₹99, Family ₹199, Team ₹499) come from the
    `plans` table, so prices and limits change without an app update.
  * Subscription screen: current plan, renewal date and seats, a
    Monthly/Yearly toggle ("save 16%"), plan cards with per-person prices
    ("just ₹40/person/month"), a comparison table, FAQ, Restore purchases,
    promo codes, Terms and Privacy.
  * A contextual paywall when you tap something locked. It shows that
    feature and the cheapest plan with it, and is always dismissible.
  * Gated features: premium voices, themes and custom accent, routines,
    weekly report, more than 2 lists (also by voice), Circle seats,
    assigning reminders, the Simple Mode lock and the activity log.
    Reminders are never gated.
  * A 7-day free trial on paid plans, once per Circle, with no payment
    needed.
  * Store purchases through RevenueCat (Play Billing and App Store). The
    RevenueCat and Razorpay webhooks are the only way a paid plan starts.
  * The plan belongs to the Circle: the owner pays and every member gets it.
  * Graceful downgrade: on expiry, nothing is deleted. Premium voice, theme
    and accent fall back to free defaults, and new joins are blocked over
    the seat limit. Owners get a notification 3 days before renewal or
    expiry.
  * Billing history, cancel and manage (opens the store's subscription
    page).
* **Phase 8 (polish and release):** done in code. Store, Meta and Firebase
  accounts plus real-device checks remain; see
  `docs/release/RELEASE_CHECKLIST.md`.
  * **Location reminders** ("buy milk when I leave work"):
    * Save Home, Work and other places from where you're standing, under
      Settings › Places.
    * Geofences are watched by the phone itself: iOS location
      notifications, Android geofencing that is restored after a reboot.
    * Works by voice in English, Hinglish and Hindi.
  * **Calendar sync** (read-only, on the device): today's events on Today
    and in the morning briefing.
  * **WhatsApp reminders** (Family/Team) via the Meta Cloud API:
    * Opt in with the verified sign-in number; a reminder that comes due is
      also sent on WhatsApp.
    * Reply "Done" (or "ho gaya") to tick it off.
    * Log-only until Meta keys are set.
  * **Smart suggestions** (Personal+), computed on the phone from your own
    history:
    * "You've set Pay rent 3 times, repeat monthly?"
    * "You usually do this an hour late, move it?"
    * "Missed often, turn on follow-ups?"
  * **Hindi UI:**
    * Every screen is translated (about 890 strings). It switches instantly
      and keeps your place.
    * Choose it under Appearance › App language; picking Hindi in onboarding
      also switches the UI.
    * A test fails if any string lacks a translation.
    * **Needs a native-speaker review.**
  * **Accessibility audit:**
    * Tap-target, label and contrast guidelines pass on 20 screens in light
      and dark, plus 200 % text in English and Hindi.
    * Fixes: Lavender, Ocean and Midnight primaries darkened to AA, plus
      four layout fixes for large text.
  * **Crash reporting and analytics:** Firebase Crashlytics and Analytics.
    * Analytics is opt-in; crash reports can be switched off.
    * Events never carry reminder content.
    * Firebase starts after the first frame.
  * **Performance:** a shorter start-up critical path, and the time to
    first frame is logged.
  * **Release:**
    * Android release signing from `key.properties`, R8 shrinking, and no
      cloud backup of sign-in tokens.
    * iOS `PrivacyInfo.xcprivacy` and the export-compliance key.
    * Store listings (English and Hindi), data safety, permissions,
      reliability test plan and acceptance evidence in `docs/release/`.

## Prerequisites

| Tool | Version used |
|---|---|
| Flutter | 3.47 (Dart 3.13) |
| Supabase CLI | 2.120+ |
| Docker | running (for local Supabase) |
| Xcode | for iOS builds |
| Android SDK | for Android builds |

## Run locally

```bash
# 1. Start the backend (applies migrations from supabase/migrations)
supabase start            # Studio: http://127.0.0.1:54723

# 2. Configure the app
cp env/dev.example.json env/dev.json
#    paste the Publishable key from `supabase status` into env/dev.json
#    Android emulator: use env/dev.android.json with SUPABASE_URL=http://10.0.2.2:54721

# 3. Generate code (Drift) and run
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=env/dev.json
```

**Sign in locally:** choose *Phone*, enter `9999999999` (or `9888888888`),
code `123456`. These test numbers (in `supabase/config.toml`) never send an
SMS. Email codes appear in Mailpit at http://127.0.0.1:54724.

> Local Supabase uses ports **547xx** (not the default 543xx) so it can run
> alongside other local Supabase projects.

## Natural-language parsing (Claude)

The `parse` Edge Function turns speech into structured reminders.
Without an API key, the app falls back to its on-device parser, which
handles English, Hinglish and common phrasings offline.

```bash
cp supabase/functions/.env.example supabase/functions/.env   # add ANTHROPIC_API_KEY
supabase start   # local: also serves every function in supabase/functions
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...            # production
supabase functions deploy parse
```

The default model is `claude-haiku-5-5`, because your spec asks for a
small, fast model with a 4-second budget. Set `PARSER_MODEL` to change it.

> Locally, `supabase start` already serves the functions. Only run
> `supabase functions serve` for hot reload while editing a function. It
> replaces the stack's edge runtime, so keep it running, or run
> `supabase stop && supabase start` afterwards.

The `notes-search` function uses Supabase's built-in `gte-small`
embedding model, so it needs no API key. Its first call after a restart is
slow (the model loads). The app answers from on-device keyword search in
the meantime.

## Environment variables (`--dart-define-from-file`)

| Key | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase API URL |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable (anon) key; safe to ship, RLS protects data |
| `ENABLE_GOOGLE_SIGN_IN` | `true` once Google OAuth is configured in Supabase |
| `ENABLE_APPLE_SIGN_IN` | `true` once Apple sign-in is configured |
| `REVENUECAT_ANDROID_KEY` / `REVENUECAT_IOS_KEY` | RevenueCat public SDK keys. Empty means store purchases are off; trials and promo codes still work |
| `ENABLE_RAZORPAY` | `true` only where direct UPI/card payments are allowed (web, or alternative-billing regions) |
| `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_BUNDLE_ID` | Crashlytics and Analytics. All empty means telemetry is off. Android also needs `android/app/google-services.json` |

`env/*.json` is git-ignored; only `env/dev.example.json` is committed.

## Tests

```bash
flutter test                                   # unit + widget + a11y + l10n (328 tests)
supabase test db                               # pgTAP RLS, events, deletion, people, circles, billing, WhatsApp, admin, renewals, admin panel (189)
(cd admin && flutter test)                     # admin panel: gate, sign-in + MFA, actions, roles (8)
docker run --rm --entrypoint deno -v "$PWD/supabase/functions:/fn" -w /fn \
  denoland/deno:2.5.6 test --allow-all parse/ _shared/  # parser schema, billing/WhatsApp/renewal messages (14)
flutter test integration_test -d <device> \
  --dart-define-from-file=env/dev.json         # E2E: sign-in + sync;
                                               # create → scheduled → Done → synced;
                                               # TTS + voice notification sounds;
                                               # realtime lists + semantic notes

# Two-user Circle flow (invite → seat limit → upgrade → join → assign → done)
# and billing (trial → signed RevenueCat webhooks → cancel → expiry → promo).
# The local service-role key is used only for set-up and to run the expiry job.
KEY=$(supabase status -o env | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p')
RC=$(sed -n 's/^REVENUECAT_WEBHOOK_SECRET=//p' supabase/functions/.env)
flutter test integration_test/circles_test.dart -d <device> \
  --dart-define-from-file=env/dev.json --dart-define=SUPABASE_SERVICE_ROLE_KEY=$KEY
flutter test integration_test/billing_test.dart -d <device> \
  --dart-define-from-file=env/dev.json --dart-define=SUPABASE_SERVICE_ROLE_KEY=$KEY \
  --dart-define=REVENUECAT_WEBHOOK_SECRET=$RC
```

The billing test needs `REVENUECAT_WEBHOOK_SECRET` in `supabase/functions/.env`
(copy `.env.example`, use any random value, then `supabase stop && supabase start`).

```bash
# WhatsApp: opt-in → due reminder dispatched (log mode) → signed "Done" reply.
CRON=$(sed -n 's/^CRON_SECRET=//p' supabase/functions/.env)
APP=$(sed -n 's/^WHATSAPP_APP_SECRET=//p' supabase/functions/.env)
flutter test integration_test/whatsapp_test.dart -d <device> \
  --dart-define-from-file=env/dev.json --dart-define=SUPABASE_SERVICE_ROLE_KEY=$KEY \
  --dart-define=CRON_SECRET=$CRON --dart-define=WHATSAPP_APP_SECRET=$APP
```

`supabase/seed.sql` stores the local cron secret in Vault on `supabase db reset`.
After a reset, put the same value in `supabase/functions/.env` as
`CRON_SECRET`.

## Project layout

```
lib/
  app.dart, main.dart
  core/        theme (tokens, presets), router, shared widgets, config
  data/        local/ (Drift DB), sync/ (outbox, engine, remote), providers
  features/    auth, shell, today, lists, profile, settings, placeholders
supabase/
  migrations/  schema → tenancy & RLS → catalogue data (plans, voices, themes)
  tests/       pgTAP tests
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for sync, tenancy and theming design.

## Testing reminders on a device

* **iOS Simulator:** if notifications never appear, reset the app's
  permission state with `xcrun simctl privacy <device> reset all com.aria.pa`.
  iOS silently drops scheduling requests from apps without permission, so
  Today shows a "Notifications are off" banner in that case.
* **Android 12+:** allow *Alarms & reminders* when Today asks. Without it,
  reminders fall back to inexact alarms and may be a few minutes late.
* Some Android brands (Xiaomi, Oppo, Vivo and others) kill background apps
  aggressively. The per-brand guidance comes with onboarding in Phase 4.

## Voice notes

* Voices currently use the phone's own text-to-speech engine. Each voice
  has its own language, pitch and rate, so they sound distinct. Neural
  voices (Google, Azure or ElevenLabs) slot in behind the same `Speaker`
  interface once there's an API key.
* **iOS:** a voice reminder's speech is rendered to a `.caf` file in
  `Library/Sounds` and used as the notification's sound. It plays with the
  app closed and obeys the silent switch.
* **Android:** an exact alarm wakes a background isolate that speaks
  through native TextToSpeech. It stays quiet when the ringer is on silent
  or vibrate, unless you turn on "Speak even on silent".

## Widgets, shortcuts and deep links

| Entry point | Android | iOS |
|---|---|---|
| Next reminder, Today and Mic widgets | Ready (`AriaWidgets.kt`) | Source ready. Needs a one-time Xcode setup (below). |
| Long-press shortcuts (New reminder, Talk, Lists) | Ready | Ready |
| Quick Settings tile ("Talk to Aria") | Ready (`TalkTileService.kt`) | Not available on iOS |

Deep links use three slashes, so the path is preserved:
`aria:///talk`, `aria:///today`, `aria:///reminder/<id>` and
`aria:///join/<code>` (Circle invites).

### iOS widget setup (one time, about 2 minutes, needs your Apple team)

1. Open `ios/Runner.xcworkspace` in Xcode. Choose File › New › Target ›
   Widget Extension, name it `AriaWidget`, and leave "Include
   Configuration App Intent" unticked.
2. Replace the generated Swift file with `ios/AriaWidget/AriaWidget.swift`.
3. Add the App Group `group.com.aria.pa` to both the Runner and the
   AriaWidget targets (Signing & Capabilities › + App Groups).
4. Set the widget's deployment target to iOS 17 or later.

## Admin, suspension and renewals

The web **admin panel** lives in [`admin/`](admin/README.md) (Flutter web).
Admins sign in with a one-time code plus a mandatory authenticator app; the
database refuses admin calls without two-factor. Operations are described in
[`docs/ADMIN_RUNBOOK.md`](docs/ADMIN_RUNBOOK.md).
* **Roles and logging:** admin roles (super, support, finance). Every
  change goes through an `admin_*` function that requires a reason and is
  logged in an append-only `admin_actions` table.
* **Suspension:** an auth ban, plus a PostgREST pre-request 403 and
  restrictive RLS, so it takes effect immediately. The app shows "Your
  account is suspended". Reminders already on the phone keep ringing.
* **Reports:** a read-only `support_readonly` login over `reports.*`
  (tenure, expiring, lapsed, revenue, renewal rate, trial conversion,
  messaging, admin activity). It has no access to reminder content.
* **Renewal reminders** (daily 10:00 IST, sent once per step):
  * Plans that won't renew by themselves: 7, 3 and 1 day before, on the
    day, then 3 and 7 days after.
  * Auto-renewing plans: one courtesy note.
  * Failed payment: "update your payment".
  * Channels: WhatsApp and email (log mode until accounts exist), phone
    notifications, and a banner on Today and Me.
* **Expiry and refunds:** premium stops within 5 minutes of the paid-until
  time. Payments are non-refundable; store-issued refunds end access
  immediately.

```bash
# End-to-end: suspend → locked out → unsuspend; renewal reminder once; plan grant logged.
flutter test integration_test/admin_test.dart -d <device> \
  --dart-define-from-file=env/dev.json --dart-define=SUPABASE_SERVICE_ROLE_KEY=$KEY \
  --dart-define=CRON_SECRET=$CRON
```

## Production setup (later)

The full list, with store compliance, is in
[`docs/release/RELEASE_CHECKLIST.md`](docs/release/RELEASE_CHECKLIST.md).

* Create a hosted Supabase project, then `supabase link` and `supabase db push`.
* Configure an SMS provider (Twilio / MSG91) for phone OTP in the dashboard.
  The Twilio values in `config.toml` are local-only placeholders.
* Add `aria://login-callback` to the auth redirect allow-list.
* **Subscriptions:**
  1. Create the products in Play Console and App Store Connect:
     `aria_personal_month`, `aria_personal_year`, `aria_family_month`,
     `aria_family_year`, `aria_team_month`, `aria_team_year`. Play base plans
     like `aria_family:monthly` also work.
  2. In RevenueCat, add one offering per plan (ids `personal`, `family`,
     `team`) with monthly and annual packages. Put the public SDK keys in
     `env/prod.json` as `REVENUECAT_ANDROID_KEY` and `REVENUECAT_IOS_KEY`.
  3. Add a RevenueCat webhook to
     `https://<project>.supabase.co/functions/v1/revenuecat-webhook` with
     Authorization header `Bearer <secret>`, then run
     `supabase secrets set REVENUECAT_WEBHOOK_SECRET=<secret>`.
  4. Razorpay (only for builds where direct payments are allowed):
     * Create the plans and set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and
       `RAZORPAY_PLAN_<PLAN>_<MONTH|YEAR>`.
     * Add a webhook to `/functions/v1/razorpay-webhook` and set
       `RAZORPAY_WEBHOOK_SECRET`.
     * Build with `ENABLE_RAZORPAY=true`.
  5. Promo codes are rows in `public.promo_codes` (for example a student
     month on Personal). `STUDENT30` exists only in the local `seed.sql`.
  6. Publish real Terms and Privacy pages. `kTermsUrl` and
     `kPrivacyPolicyUrl` are placeholders.
# PAssist
