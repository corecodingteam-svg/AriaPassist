-- Aria — catalogue data. In a migration (not seed.sql) because production
-- needs it too. Prices and limits are edited here / in the dashboard, never
-- hard-coded in the app. Idempotent.

insert into public.plans (code, name, max_seats, price_month_inr, price_year_inr, trial_days, sort, features_json) values
  ('free', 'Free', 1, 0, 0, 0, 0,
   '{"voices": ["aria", "device"], "max_lists": 2, "themes": ["lavender", "ocean", "mint"],
     "morning_briefing": true, "routines": false, "location_reminders": false,
     "smart_suggestions": false, "weekly_report": false, "widgets": false,
     "custom_accent": false, "shared_circle": false, "whatsapp": false, "audit_log": false}'),
  ('personal', 'Personal', 1, 99, 999, 7, 1,
   '{"voices": "all", "max_lists": null, "themes": "all",
     "morning_briefing": true, "routines": true, "location_reminders": true,
     "smart_suggestions": true, "weekly_report": true, "widgets": true,
     "custom_accent": true, "shared_circle": false, "whatsapp": false, "audit_log": false}'),
  ('family', 'Family', 5, 199, 1999, 7, 2,
   '{"voices": "all", "max_lists": null, "themes": "all",
     "morning_briefing": true, "routines": true, "location_reminders": true,
     "smart_suggestions": true, "weekly_report": true, "widgets": true,
     "custom_accent": true, "shared_circle": true, "dependents": true, "simple_mode_lock": true,
     "assign_reminders": true, "whatsapp": true, "audit_log": false, "most_popular": true}'),
  ('team', 'Team', 15, 499, 4999, 7, 3,
   '{"voices": "all", "max_lists": null, "themes": "all",
     "morning_briefing": true, "routines": true, "location_reminders": true,
     "smart_suggestions": true, "weekly_report": true, "widgets": true,
     "custom_accent": true, "shared_circle": true, "dependents": true, "simple_mode_lock": true,
     "assign_reminders": true, "whatsapp": true, "audit_log": true, "admin_dashboard": true,
     "priority_support": true}')
on conflict (code) do update set
  name = excluded.name, max_seats = excluded.max_seats,
  price_month_inr = excluded.price_month_inr, price_year_inr = excluded.price_year_inr,
  trial_days = excluded.trial_days, sort = excluded.sort, features_json = excluded.features_json;

insert into public.voices (id, name, language, gender, description, provider, provider_voice_name, is_free, sort) values
  ('aria',   'Aria',         'en-IN',    'female', 'Indian English · warm',                 'google', 'en-IN-Neural2-A', true,  0),
  ('meera',  'Meera',        'hi-IN',    'female', 'Hindi · soft',                          'google', 'hi-IN-Neural2-A', false, 1),
  ('sia',    'Sia',          'en-IN',    'female', 'Indian English · cheerful & energetic', 'google', 'en-IN-Neural2-D', false, 2),
  ('grace',  'Grace',        'en-GB',    'female', 'British English · calm',                'google', 'en-GB-Neural2-A', false, 3),
  ('kavya',  'Kavya',        'hinglish', 'female', 'Hinglish · friendly',                   'google', 'hi-IN-Neural2-D', false, 4),
  ('arjun',  'Arjun',        'en-IN',    'male',   'Indian English · calm',                 'google', 'en-IN-Neural2-B', false, 5),
  ('device', 'Device voice', 'device',   'any',    'Works offline · free',                  'device', null,              true,  6)
on conflict (id) do update set
  name = excluded.name, language = excluded.language, gender = excluded.gender,
  description = excluded.description, provider = excluded.provider,
  provider_voice_name = excluded.provider_voice_name, is_free = excluded.is_free, sort = excluded.sort;

-- Generated from lib/core/theme/presets.dart (keep in sync; a test checks ids).
insert into public.theme_presets (id, label, tokens_json, is_free, sort) values
  ('lavender', 'Lavender', '{"light": {"primary": "#7C4DFF", "secondary": "#FF6FAE", "background": "#F7F3FC", "surface": "#FFFFFF", "text": "#1F1633", "muted": "#6E6487"}, "dark": {"primary": "#B39DFF", "secondary": "#FF8DC0", "background": "#15111F", "surface": "#211B2E", "text": "#F3EEFB", "muted": "#ABA1C2"}}'::jsonb, true, 0),
  ('ocean', 'Ocean Blue', '{"light": {"primary": "#1E6FD9", "secondary": "#00B3C7", "background": "#F2F7FD", "surface": "#FFFFFF", "text": "#0F1C2E", "muted": "#56667B"}, "dark": {"primary": "#7FB2FF", "secondary": "#4FD8E8", "background": "#0D1520", "surface": "#172231", "text": "#EAF2FC", "muted": "#9FB0C4"}}'::jsonb, true, 1),
  ('mint', 'Mint Green', '{"light": {"primary": "#0F7F60", "secondary": "#7BD389", "background": "#F1FAF6", "surface": "#FFFFFF", "text": "#10241D", "muted": "#4F6A63"}, "dark": {"primary": "#5FD3AE", "secondary": "#A5E8B0", "background": "#0C1714", "surface": "#15241F", "text": "#E6F6F0", "muted": "#9DB8B0"}}'::jsonb, true, 2),
  ('sunset', 'Sunset Orange', '{"light": {"primary": "#C2410C", "secondary": "#FFB347", "background": "#FFF6EF", "surface": "#FFFFFF", "text": "#2A160C", "muted": "#74594C"}, "dark": {"primary": "#FF9A5C", "secondary": "#FFC978", "background": "#1A110C", "surface": "#271A13", "text": "#FBEDE4", "muted": "#C2A799"}}'::jsonb, false, 3),
  ('rose', 'Rose Pink', '{"light": {"primary": "#C2185B", "secondary": "#FF8FB1", "background": "#FFF3F7", "surface": "#FFFFFF", "text": "#2B0F1C", "muted": "#775564"}, "dark": {"primary": "#FF8FB8", "secondary": "#FFB3CB", "background": "#1B0E14", "surface": "#2A1720", "text": "#FBE9F0", "muted": "#C4A2B1"}}'::jsonb, false, 4),
  ('midnight', 'Midnight', '{"light": {"primary": "#3D5AFE", "secondary": "#00B8D4", "background": "#EEF0F8", "surface": "#FFFFFF", "text": "#0E1330", "muted": "#555B7B"}, "dark": {"primary": "#8C9EFF", "secondary": "#5CE1F5", "background": "#0A0D1C", "surface": "#141A30", "text": "#E8EBFA", "muted": "#A3A9C8"}}'::jsonb, false, 5),
  ('sand', 'Sand', '{"light": {"primary": "#8A5A2B", "secondary": "#D9A55B", "background": "#FBF7F0", "surface": "#FFFFFF", "text": "#2B2116", "muted": "#6F604A"}, "dark": {"primary": "#E0B784", "secondary": "#EBC98F", "background": "#17130D", "surface": "#241E16", "text": "#F5EDE1", "muted": "#BFB09A"}}'::jsonb, false, 6),
  ('monochrome', 'Monochrome', '{"light": {"primary": "#2B2B2B", "secondary": "#6B6B6B", "background": "#F5F5F5", "surface": "#FFFFFF", "text": "#111111", "muted": "#5B5B5B"}, "dark": {"primary": "#E6E6E6", "secondary": "#B0B0B0", "background": "#0F0F0F", "surface": "#1C1C1C", "text": "#F2F2F2", "muted": "#A8A8A8"}}'::jsonb, false, 7)
on conflict (id) do update set
  label = excluded.label, tokens_json = excluded.tokens_json,
  is_free = excluded.is_free, sort = excluded.sort;
