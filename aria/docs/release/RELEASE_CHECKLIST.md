# Release checklist

Everything that needs accounts, keys or real devices. The code is ready
for each item below. Keys live in git-ignored files or in
`supabase secrets` / Vault, never in the repo.

## 1. Backend (hosted Supabase)

- [ ] Create the project. Run `supabase link`, then `supabase db push`
      (all migrations).
- [ ] Auth:
  - [ ] Phone OTP provider (Twilio / MSG91).
  - [ ] Email templates: copy `supabase/templates/otp_code.html` (6-digit
        code).
  - [ ] Redirect URL `aria://login-callback`.
- [ ] Function secrets (`supabase secrets set …`):
      `ANTHROPIC_API_KEY`, `REVENUECAT_WEBHOOK_SECRET`,
      `RAZORPAY_*` (only for direct payments),
      `WHATSAPP_PROVIDER=meta`, `WHATSAPP_TOKEN`,
      `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TEMPLATE`,
      `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `CRON_SECRET`.
- [ ] Vault (for the WhatsApp cron job):
      `select vault.create_secret('https://<ref>.supabase.co/functions/v1','aria_functions_url');`
      and `select vault.create_secret('<CRON_SECRET>','aria_cron_secret');`
- [ ] Check the cron jobs exist: `select jobname from cron.job;`. Expect
      account purge, subscription expiry and WhatsApp dispatch.
- [ ] Promo codes for launch: use `admin_create_promo(...)` (see
      `docs/ADMIN_RUNBOOK.md`).
- [ ] Admin access:
  - [ ] Bootstrap the first super-admin.
  - [ ] Deploy `admin/` (static web, own sub-domain, host-level access
        protection in front). See `admin/README.md`.
  - [ ] Turn on TOTP MFA in hosted Supabase Auth: Authentication ›
        Multi-factor › Authenticator app.
  - [ ] Turn on MFA for every admin.
  - [ ] Set a password for the `support_readonly` login.
- [ ] **Point-in-time recovery** add-on on the hosted project, plus daily
      backups.
- [ ] A **staging** project (same migrations) for practising and testing.
- [ ] Renewal reminders:
  - [ ] Set `EMAIL_PROVIDER=resend`, `RESEND_API_KEY` and `EMAIL_FROM`
        (verified sender domain).
  - [ ] Get a WhatsApp template `aria_renewal` approved:
        "Aria {{1}}: {{2}}". Set `WHATSAPP_RENEWAL_TEMPLATE`.
- [ ] Terms: state "Payments are non-refundable. Purchases through Google
      Play or the App Store follow their refund policies." The app already
      shows this on the Subscription screen.

## 2. Payments

- [ ] Play Console and App Store Connect products: `aria_{personal,family,team}_{month,year}`
      with 7-day trials, if you also want store trials.
- [ ] RevenueCat:
  - [ ] Apps and offerings `personal`, `family`, `team` (monthly and
        annual).
  - [ ] Webhook URL `/functions/v1/revenuecat-webhook` with Bearer secret.
  - [ ] Public SDK keys in `env/prod.json`.
- [ ] Razorpay (web / allowed regions only): plans, webhook
      `/functions/v1/razorpay-webhook`, `ENABLE_RAZORPAY=true` in that
      build only.
- [ ] Sandbox purchase, restore, cancel and expiry on a real device per
      store.

## 3. WhatsApp (Meta Cloud API)

- [ ] Business verification, phone number and display name approved.
- [ ] Template `aria_reminder` (Utility):
      "⏰ Reminder: {{1}} ({{2}}). Reply DONE when it's done." Add a Hindi
      variant if needed.
- [ ] Webhook `/functions/v1/whatsapp-webhook` with your verify token;
      subscribe to `messages`.

## 4. Firebase (Crashlytics + Analytics)

- [ ] Create the project. Add Android app `com.aria.pa` and iOS app
      `com.aria.pa`.
- [ ] Put `android/app/google-services.json` in place. The Crashlytics
      Gradle plugin turns on automatically when it exists.
- [ ] Put `FIREBASE_*` values in `env/prod.json` (see README).
- [ ] iOS dSYM upload: add Crashlytics' run script, or upload in CI.

## 5. Builds and signing

- [ ] Android upload keystore and `android/key.properties`. Without it the
      release build is debug-signed and is rejected by Play.
- [ ] Version: bump `version:` in `pubspec.yaml` (name+code) per release.
- [ ] Build `flutter build appbundle --release --dart-define-from-file=env/prod.json`.
- [ ] Build `flutter build ipa --release --dart-define-from-file=env/prod.json`.
      Needs an Apple team and signing in Xcode.
- [ ] iOS home-screen widget target (README › iOS widget setup).

## 6. Store compliance

- [ ] Publish the privacy policy and terms; update `kPrivacyPolicyUrl` and
      `kTermsUrl`.
- [ ] Account deletion web form URL (Play requirement).
- [ ] Play declarations (see `PRIVACY_AND_DATA.md`):
  - [ ] Data safety.
  - [ ] Exact alarm (alarm/reminder app).
  - [ ] Full-screen intent.
  - [ ] Background location, with a demo video.
- [ ] App Store privacy labels (`PRIVACY_AND_DATA.md`).
      `PrivacyInfo.xcprivacy` is already in the bundle.
- [ ] Listings, screenshots and the Hindi copy (`STORE_LISTING.md`).
- [ ] **Native Hindi review** of `lib/l10n/hi.dart` and the store copy.

## 7. Quality gates (every release)

- [ ] `flutter analyze` clean and `flutter test` green.
- [ ] `supabase test db` green and the Deno tests green.
- [ ] Integration tests on a simulator and a real phone (README › Tests).
- [ ] `RELIABILITY_TEST_PLAN.md` on the device matrix.
- [ ] Cold start under 2 s on a mid-range Android, in a profile or release
      build. Read the `startup: first frame in … ms` log or the `app_start`
      analytics event.
- [ ] TalkBack and VoiceOver pass through onboarding, creating a reminder,
      Today and the alert screen.
