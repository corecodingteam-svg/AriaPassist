# Aria Admin (web)

The internal admin panel: overview, users, subscriptions, revenue, promo
codes, messaging, the activity log and admins. A Flutter web app on the
same Supabase backend as the mobile app.

## Security model

- **Sign-in:** email or phone with a one-time code, for existing accounts
  only.
- **Authenticator app (TOTP) is mandatory.** Every admin function refuses
  calls whose session hasn't completed two-factor (JWT `aal2`). This is
  enforced in the database, not just in this UI.
- **Roles:** checked server-side on every call.
  - `super`: everything, including Admins and Delete now.
  - `support`: suspend, sign out, grant plans, promo codes.
  - `finance`: read-only.
- **No direct table access.** The panel calls role-checked database
  functions (`admin_overview`, `admin_report`, `admin_search_users`,
  `admin_user_detail`, `admin_*` actions…).
  - Metadata only: reminder, note, list and place text is never returned.
  - Every action needs a reason, and every action and every user profile
    opened is written to the append-only activity log.
  - Destructive actions also need you to type a confirmation word.

## Run locally

```bash
cd admin
flutter run -d web-server --web-port 5180 --dart-define-from-file=../env/dev.json
# or: flutter build web --dart-define-from-file=../env/dev.json && \
#     (cd build/web && python3 -m http.server 5180)
```

Open http://localhost:5180. The local stack has a super-admin
`admin@aria.local`; its sign-in code arrives in Mailpit
(http://127.0.0.1:54724). On first sign-in, scan the QR code with any
authenticator app.

To make someone an admin (the first one comes from the SQL console, see
`docs/ADMIN_RUNBOOK.md`):

```sql
select set_config('aria.actor', 'you@company', false);
select public.admin_set_role('<user-id>', 'super', 'first admin');
```

## Tests

```bash
cd admin && flutter analyze && flutter test   # gate, sign-in + MFA, actions, roles
cd .. && supabase test db                     # 10_admin_panel: MFA gate, roles, no content, view logging
```

## Deploy

1. Run `flutter build web --release --dart-define-from-file=../env/prod.json`.
2. Host `build/web` as static files on any static host (Vercel, Netlify,
   Cloudflare Pages, S3 + CloudFront…), on its own sub-domain, e.g.
   `admin.yourdomain`.
3. Recommended: put the host's access protection in front (Cloudflare
   Access, Vercel password, or an IP allow-list) as a second fence. The
   database rules are the real lock.
4. `index.html` carries `noindex`. Never link the panel from public pages.
