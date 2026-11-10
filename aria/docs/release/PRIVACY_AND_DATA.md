# Privacy, data safety and permissions

Use this file to fill in the Play Console Data safety form, the App Store
privacy labels and the permission declarations. It must match
`ios/Runner/PrivacyInfo.xcprivacy` and the privacy policy.

## Data collected

| Data | Why | Linked to user | Shared with third parties | Optional |
|---|---|---|---|---|
| Phone number or email | Sign-in, WhatsApp delivery | Yes | No (SMS/OTP provider processes it) | Required (one of them) |
| Name (optional) | Greetings | Yes | No | Optional |
| Reminders, lists, notes, people, places | App functionality and sync | Yes | No | User content |
| Purchase history | Subscriptions | Yes | RevenueCat / Razorpay (processors) | Paid plans only |
| Crash logs | Fixing bugs (Crashlytics) | No | Google (processor) | On by default; switch in Privacy |
| Product interaction (analytics) | Improving features (Firebase Analytics) | No | Google (processor) | **Opt-in**, off by default |

**Not collected:**
- **Voice audio:** speech is turned into text on the device.
- **Precise location:** geofences are watched on the device and coordinates
  of saved places stay in the user's settings.
- **Calendar events:** read on the device only.
- **Contacts:** not accessed.

**No** tracking, advertising IDs or data sale.

**Encryption and deletion:**
- Encrypted in transit (TLS) and at rest (Supabase/Postgres).
- In-app account deletion: Settings › Privacy › Delete account, with a
  7-day grace period, then a purge by `pg_cron`.
- **Play also requires a web URL for deletion requests.** Publish one
  (TODO) and list it in the Data safety form.

## Permissions and their justification

| Permission | Platform | Why Aria needs it | When it's asked |
|---|---|---|---|
| Notifications (`POST_NOTIFICATIONS`) | Android 13+, iOS | Showing reminders | First time a reminder is saved |
| Exact alarms (`SCHEDULE_EXACT_ALARM`) | Android 12+ | Reminders must ring at the set minute. Aria is a reminder/alarm app, which Play's policy allows. | Onboarding, Troubleshooter |
| Full-screen intent (`USE_FULL_SCREEN_INTENT`) | Android 14+ | Urgent reminders (medicines) take over the screen, like an alarm clock | Only for reminders marked Urgent |
| Ignore battery optimisation | Android | OEM battery savers kill reminders (Xiaomi, Oppo, Vivo…) | Troubleshooter, after explaining |
| Boot completed | Android | Re-schedule reminders and geofences after a restart | Not a prompt |
| Microphone, speech recognition | Both | Setting reminders by voice (processed on the device) | First tap on the mic |
| Location (while using) | Both | Saving a place and location reminders ("when I leave work") | Saving a place |
| Background location (`ACCESS_BACKGROUND_LOCATION`) | Android 10+ | Geofences while the app is closed. **Needs a Play declaration and a demo video.** | After a place is saved, with an explanation card |
| Calendar (read) | Both | Showing today's events and the morning briefing | Turning on Connected apps › Phone calendar |
| Face ID / biometrics | Both | Optional App lock | Turning App lock on |

## Play Data safety answers (summary)

- **Data collected:**
  - Personal info: phone number, email address, name.
  - App activity: app interactions (analytics, optional).
  - App info and performance: crash logs.
  - Financial info: purchase history.
  - Messages: none.
  - Location: none leaves the device. Collection is defined as sending data
    off the device.
- **Shared:** no.
- **Processed ephemerally:** no.
- **Required or optional:** analytics optional; the rest required for
  functionality.
- **Users can request deletion:** yes, in-app and via a web form (to
  publish).
- **Encrypted in transit:** yes.

## App Store privacy label (summary)

- **Data linked to you:**
  - Contact info (phone, email): App functionality.
  - User content: App functionality.
  - Purchases: App functionality.
- **Data not linked to you:**
  - Diagnostics (crash data): App functionality.
  - Usage data (product interaction): Analytics.
- **Tracking:** none.

## Subscriptions disclosure (both stores)

The paywall and Subscription screen show:
- Price per period.
- That the trial is 7 days and needs no payment.
- That the plan renews automatically through Play or App Store billing until
  cancelled.
- Restore purchases, plus Terms and Privacy links.

`kTermsUrl` and `kPrivacyPolicyUrl` must point to real pages before
submission.
