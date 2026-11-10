# Admin runbook

How to run Aria day to day **without hand-editing live data**. Every change
goes through an `admin_*` database function: it checks inputs, changes one
thing, needs a reason, and is written to the append-only `admin_actions`
log, which no one can edit or delete. Admins see account metadata, never
reminder, note, list or place text.

## The admin panel

Day-to-day work happens in the **web admin panel** (`admin/`, see
`admin/README.md`). Every page and button calls the functions below, so the
same rules, reasons and audit log apply.

| Page | What you can do |
|---|---|
| Overview | Users, active users, paying Circles, MRR (gross), revenue this month, ending in 7 days, lapsed, payment problems, 30-day charts |
| Users | Search, then open a profile (logged). Suspend or unsuspend, sign out everywhere, cancel deletion, grant months, delete now (super, type DELETE) |
| Subscriptions | Ending soon, lapsed (win-back), all paid Circles with tenure |
| Revenue | By month, renewal rate, trial conversion, live subscriptions |
| Promo codes | Create and stop codes |
| Messaging | WhatsApp and renewal messages by status |
| Activity log | Every admin action and profile view |
| Admins (super) | Add, change and remove admins |

Admins must sign in with **two-factor authentication** (an authenticator
app). The database refuses admin calls without it. The SQL commands below
remain for break-glass use and scripting.

## Roles

| Role | Can |
|---|---|
| `super` | Everything, including managing admins and deleting accounts immediately |
| `support` | Suspend/unsuspend, sign out everywhere, grant or extend plans, cancel a pending deletion, promo codes |
| `finance` | Read-only reports |

Admins are app users listed in `public.admins`. Turn on two-factor sign-in
(MFA) for every admin account in Supabase Auth.

## First-time setup (once per environment)

In the SQL editor, using the break-glass connection:

```sql
-- Name yourself: console actions are logged as console:<name>.
select set_config('aria.actor', 'you@yourcompany.com', false);
-- The user id comes from Studio › Authentication, or reports.users.
select public.admin_set_role('<user-uuid>', 'super', 'bootstrap first super-admin');
```

Read-only login for support and finance (SQL clients, Metabase…):

```sql
alter role support_readonly with login password '<strong password>';
```

It can only read the `reports` views, and every session is read-only with a
15-second query limit.

## Everyday tasks

Run these as an admin user through the API (the admin panel, later) or from
the SQL editor after `set_config('aria.actor', …)`. The reason is
mandatory and saved.

| Task | SQL |
|---|---|
| Find a user | `select * from reports.users where phone = '+91…' or email = '…';` |
| Suspend | `select admin_suspend_user('<user>', 'spam invites reported in ticket #123');` |
| Unsuspend | `select admin_unsuspend_user('<user>', 'appeal accepted, ticket #123');` |
| Sign out of all devices | `select admin_sign_out_everywhere('<user>', 'lost phone, ticket #124');` |
| Give or extend a plan | `select admin_grant_plan('<circle>', 'family', 30, 'goodwill after outage');` |
| Cancel a pending deletion | `select admin_cancel_deletion('<user>', 'user changed mind by email');` |
| Delete now (super) | `select admin_delete_now('<user>', 'verified web deletion request #55');` |
| New promo code | `select admin_create_promo('DIWALI30', 'personal', 30, 1000, '2026-11-30', 'Diwali', 'campaign');` |
| Stop a promo code | `select admin_disable_promo('DIWALI30', 'campaign over');` |
| Add, change or remove an admin (super) | `select admin_set_role('<user>', 'support', 'new hire');` (`null` removes) |

**What suspension does:**
- Blocks sign-in, ends every session, and makes every API call return
  403 straight away.
- The app shows "Your account is suspended".
- Data is kept.
- Reminders already on the phone keep ringing, so nobody misses a medicine
  because of a suspension.
- Unsuspending restores everything.

**Plan grants:**
- They never auto-renew.
- A second grant extends from the end of the first.
- They show as "added by Aria support" in the user's billing history.

## Reports (read-only)

| View | Shows |
|---|---|
| `reports.activity_daily` | Sign-ups, active users, reminders created / done / missed (90 days) |
| `reports.users` | Profile metadata, plan rank, counts, suspension, pending deletion, admin role |
| `reports.circle_tenure` | Plan, first paid, **paid until**, provider, auto-renew, payments, renewals, total paid, members |
| `reports.expiring` | Paid plans ending in the next 30 days, with `days_left` |
| `reports.lapsed` | Ended in the last 60 days and not renewed (win-back list) |
| `reports.subscriptions_overview` | Live subscriptions by plan, provider and status |
| `reports.revenue_monthly` | Payments and gross ₹ by month, plan and provider |
| `reports.renewal_rate_monthly` | Renewed vs ended, renewal % |
| `reports.trial_conversion` | Trials per month and how many paid within 30 days |
| `reports.messaging_daily` | WhatsApp reminders and renewal messages by status |
| `reports.admin_activity` | Every admin action: who, what, why, when |

Revenue here is **gross** and excludes store fees (15–30 %) and GST.
RevenueCat (and Razorpay) remain the source of truth for net revenue.

## Subscriptions: what happens on its own

- **Paid until:** set by the store, RevenueCat or Razorpay webhooks, or a
  trial, promo or grant.
- **Expiry:** premium stops within 5 minutes of that time (pg_cron), and
  the Circle drops to Free.
  - Data stays, and basic reminders keep working.
  - New joins over the seat limit are blocked.
- **Renewal reminders:** sent daily at 10:00 IST (pg_cron →
  `renewal-dispatch`). The sent-reminder log means each step goes out only
  once.
  - **Plans that won't renew by themselves** (trial, promo, grant,
    auto-renew off) get the full sequence:
    - 7, 3 and 1 day before, and when it ends: owner. Members also get
      the "ended" notice.
    - 3 and 7 days after: owner (win-back).
  - **Auto-renewing store or Razorpay plans** get one courtesy note 3 days
    before.
  - **Failed renewal payment:** an "update your payment method" reminder.
  - **Channels:**
    - WhatsApp (opted-in users) and email, from the server.
    - Phone notifications and the Today / Me banner, in the app.
- **Refunds:** none. Payments are non-refundable, as the Subscription
  screen and FAQ say. If Google or Apple refund someone themselves, the
  webhook ends access immediately.

## Break-glass (direct SQL on live data)

Only when no `admin_*` function fits, and only by a super-admin:

1. Try it on **staging** first.
2. `begin;` → run the statement → check the row count it reports → only
   then `commit;` (otherwise `rollback;`).
3. Log it afterwards:
   `insert into admin_actions (actor, action, reason, details) values ('console:you', 'manual.sql', 'why…', '{"sql":"…"}');`
4. If something goes wrong, use **point-in-time recovery** (hosted
   Supabase): restore a copy to just before the change and copy the
   affected rows back.

Through the API, an `UPDATE` or `DELETE` without a `WHERE` is refused
(`safeupdate`). The SQL editor has no such guard, hence the steps above.
