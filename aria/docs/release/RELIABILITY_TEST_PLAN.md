# OEM reliability test plan

Reminders are worthless if they don't ring. Run this matrix on **real
phones** before every release; emulators don't reproduce OEM battery
killers.

## Devices (minimum)

| Brand / skin | Why |
|---|---|
| Xiaomi / Redmi (HyperOS or MIUI) | Most aggressive autostart and battery killer; biggest share in India |
| Samsung (One UI) | "Sleeping apps" and "Deep sleeping apps" lists |
| Oppo / Realme (ColorOS) | Background freeze, auto-launch off by default |
| Vivo / iQOO (Funtouch / OriginOS) | i Manager autostart |
| OnePlus (OxygenOS) | Battery optimisation, recent-apps lock |
| Google Pixel (stock Android 15/16) | Baseline Doze behaviour |
| iPhone (iOS 18+) | 64 pending-notification limit, Focus modes |

Include at least one low-RAM device (3–4 GB) and one on Android 12 or older.

## Scenarios

For each, create a reminder 3 minutes ahead (Text mode) and a spoken one
(Voice mode).
- **Pass:** it alerts within ±1 minute.
- **Voice:** it is audible, or falls back to text when the phone is on
  silent or vibrate.

| # | Scenario | How |
|---|---|---|
| 1 | Screen off, phone idle 30 min | Lock the phone, leave it |
| 2 | Doze (forced) | `adb shell dumpsys deviceidle force-idle`, then wait for the alert |
| 3 | App swiped away from Recents | Swipe Aria away |
| 4 | Force-stopped by the OEM cleaner | Use the skin's "clean" button |
| 5 | After reboot | Reboot with reminders pending, don't open Aria |
| 6 | After app update | `adb install -r` a new build, don't open it |
| 7 | Battery saver on | Turn on Battery saver / Ultra power saving |
| 8 | Exact-alarm permission revoked | Settings › Apps › Aria › Alarms & reminders off. Troubleshooter must flag it |
| 9 | Notifications revoked | Today shows the banner; the Troubleshooter fixes it |
| 10 | Do Not Disturb / Focus | Urgent reminders break through only where allowed |
| 11 | Timezone change | Change the zone manually. A reminder set in IST keeps its IST instant; new reminders use the new zone |
| 12 | Clock change | `adb shell cmd alarm set-time …`; reminders don't fire early |
| 13 | Offline (flight mode) | Reminders still ring; changes sync later |
| 14 | Low memory | Open many heavy apps, wait for the reminder |
| 15 | Location reminder | Save Home, walk 300+ m away and back (arrive/leave). Repeat with the app closed |
| 16 | Morning briefing | Fires at the set time with today's items (and calendar events if on) |
| 17 | Follow-ups | Ignore a reminder; nudges every 10 min, max 3, then "missed" |
| 18 | Assigned reminder | Assign to a second phone; it alerts there, not on the creator's phone |
| 19 | 64+ pending (iOS) | 70 reminders in the next days; the nearest still ring (rolling window) |
| 20 | Simple Mode device | Large text, alerts audible, PIN lock holds after reboot |

## Useful adb commands

```bash
adb shell dumpsys deviceidle force-idle            # enter Doze now
adb shell dumpsys deviceidle unforce               # leave Doze
adb shell dumpsys alarm | grep -A3 com.aria.pa     # scheduled alarms
adb shell cmd appops get com.aria.pa SCHEDULE_EXACT_ALARM
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED -p com.aria.pa
adb shell dumpsys notification --noredact | grep -A5 com.aria.pa
```

## Recording results

One row per device and build: device, OS and skin version, scenario number,
pass/fail, and the delay (seconds). On failure, add a note: which setting
fixed it, and whether the in-app Troubleshooter detected it. Every new OEM
fix goes into `lib/features/help/application/reliability.dart`, so users
get the same guidance.
