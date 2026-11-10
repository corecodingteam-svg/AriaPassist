# Acceptance criteria (spec §15) — status and evidence

✅ = verified by automated tests.
🟡 = verified in tests or on the simulator, but a real-device or
real-account check is still needed.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Create a reminder by voice in one sentence; it fires on time with the selected voice | 🟡 | `test/assistant/*` (rule parser), `parse/schema_test.ts`, `integration_test/voice_test.dart` (TTS + rendered voice notification sound, iOS simulator). Android native TTS alarm path needs a real phone. |
| 2 | "Text notification only" stops all speech; Done/Snooze actions work | ✅ / 🟡 | `test/reminders/reminder_service_test.dart` (mode → channel, no voice), `integration_test/reminder_lifecycle_test.dart`. Notification action buttons need a manual check on a device. |
| 3 | Per-category override (Health = Voice, Bills = Text) | ✅ | `talk_sheet_test.dart` "Reminder style: per-category override persists", service mode tests |
| 4 | Every voice can be previewed; locked voices open the paywall | ✅ | `talk_sheet_test.dart` "Voice settings: preview, lock…" |
| 5 | Theme / dark mode / font size update the whole app instantly | ✅ | `test/core/theme_test.dart`, settings UI tests |
| 6 | Simple Mode reduces the UI to Today + mic with large controls | ✅ | `test/phase4/settings_ui_test.dart`, `test/a11y_test.dart` (Simple Mode guidelines) |
| 7 | Reminders fire offline, after reboot and after a timezone change | 🟡 | Local scheduling only, so offline works by design. Boot receivers (notifications, alarms, geofences) and `rescheduleOnReboot`. Timezone handling unit-tested (`reminder_logic_test.dart`). **Real-device matrix:** `RELIABILITY_TEST_PLAN.md` #5, #11, #13. |
| 8 | Circle A never sees Circle B's data (RLS tests) | ✅ | `supabase/tests/database/01_tenancy_rls.test.sql` and `05_circles` (`supabase test db`, 126 assertions in total) |
| 9 | Family owner pays once; all members premium; seat limit enforced | ✅ | `06_billing.test.sql`, `integration_test/circles_test.dart` and `billing_test.dart` |
| 10 | Purchase, restore, cancel and expiry downgrade all work | 🟡 | Server path end to end with signed RevenueCat webhooks (`billing_test.dart`): purchase → cancel → expiry → downgrade. A store sandbox purchase needs Play / App Store / RevenueCat accounts. |
| 11 | WCAG AA contrast; works with TalkBack / VoiceOver | ✅ / 🟡 | `test/a11y_test.dart`: tap-target, label and contrast guidelines on 20 screens in light and dark, and 200 % text in English and Hindi. `theme_test.dart`: AA on every preset. A manual screen-reader pass is still needed. |
| 12 | Cold start < 2 s on a mid-range Android | 🟡 | Critical path trimmed (Firebase after first frame, parallel init). The `startup: first frame in … ms` log and the `app_start` event measure it. **Not yet measured on a mid-range Android device in a profile build.** |
