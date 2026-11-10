-- Local development only (supabase db reset). Never applied to production.
-- A student-discount style promo for trying the redeem flow.
insert into public.promo_codes (code, plan_id, days, max_redemptions, note)
select 'STUDENT30', id, 30, null, 'Local test: a month of Personal'
  from public.plans where code = 'personal'
on conflict (code) do nothing;

-- Cron → Edge Functions (WhatsApp + renewal dispatch) through the local API
-- gateway. Dev-only value; must match CRON_SECRET in supabase/functions/.env.
-- Production uses a real random secret via vault.create_secret().
select vault.create_secret('http://kong:8000/functions/v1', 'aria_functions_url')
 where not exists (select 1 from vault.secrets where name = 'aria_functions_url');
select vault.create_secret('local-dev-cron-secret', 'aria_cron_secret')
 where not exists (select 1 from vault.secrets where name = 'aria_cron_secret');
