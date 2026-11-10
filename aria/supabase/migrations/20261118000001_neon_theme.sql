-- The Neon look (2026-11): Neon (dark slate with a blue accent) is added as the default preset, and the existing
-- presets become Neon skins under the same ids, so plans and saved choices still apply. "nav" is the skin's header and
-- navigation colour. Generated from lib/core/theme/presets.dart (keep in sync; a test checks ids and labels).
insert into public.theme_presets (id, label, tokens_json, is_free, sort) values
  ('neon', 'Neon', '{"light": {"primary": "#303641", "secondary": "#21A9E1", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#2B303A", "muted": "#5F6570", "nav": "#303641"}, "dark": {"primary": "#5CC0EA", "secondary": "#8FD3F0", "background": "#1A1E24", "surface": "#262B33", "text": "#ECEEF1", "muted": "#A8ADB5", "nav": "#303641"}}'::jsonb, true, 0),
  ('lavender', 'Lavender', '{"light": {"primary": "#643590", "secondary": "#BA79CB", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#2B2433", "muted": "#635C6C", "nav": "#522B76"}, "dark": {"primary": "#CFA8EE", "secondary": "#E0BDF0", "background": "#1C1822", "surface": "#29232F", "text": "#F1EDF5", "muted": "#B1A8BB", "nav": "#522B76"}}'::jsonb, true, 1),
  ('ocean', 'Ocean Blue', '{"light": {"primary": "#063D7D", "secondary": "#21A9E1", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#13243A", "muted": "#56657A", "nav": "#003471"}, "dark": {"primary": "#86B9F2", "secondary": "#8FD3F0", "background": "#111A26", "surface": "#1B2635", "text": "#EAF1FA", "muted": "#A2B1C4", "nav": "#003471"}}'::jsonb, true, 2),
  ('mint', 'Mint Green', '{"light": {"primary": "#00733A", "secondary": "#00A651", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#122A1D", "muted": "#526459", "nav": "#00843F"}, "dark": {"primary": "#5FD39A", "secondary": "#8FE3B8", "background": "#0F1A14", "surface": "#18261E", "text": "#E7F5ED", "muted": "#9FB7A9", "nav": "#00843F"}}'::jsonb, true, 3),
  ('sunset', 'Sunset Orange', '{"light": {"primary": "#A8530A", "secondary": "#FFA812", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#2E1C0C", "muted": "#6E5B4B", "nav": "#F89D00"}, "dark": {"primary": "#FFB35C", "secondary": "#FFC97A", "background": "#1C140C", "surface": "#2A1F14", "text": "#FBEFE2", "muted": "#C4AB95", "nav": "#F89D00"}}'::jsonb, false, 4),
  ('rose', 'Rose Pink', '{"light": {"primary": "#A22424", "secondary": "#F56954", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#2E1414", "muted": "#6C5656", "nav": "#981B1B"}, "dark": {"primary": "#FF9488", "secondary": "#FFB3A8", "background": "#1D1212", "surface": "#2B1B1B", "text": "#FBECEC", "muted": "#C4A6A6", "nav": "#981B1B"}}'::jsonb, false, 5),
  ('midnight', 'Midnight', '{"light": {"primary": "#222222", "secondary": "#21A9E1", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#1F1F1F", "muted": "#5C5C5C", "nav": "#222222"}, "dark": {"primary": "#7CC8EE", "secondary": "#A6DBF5", "background": "#141414", "surface": "#1F1F1F", "text": "#F0F0F0", "muted": "#A9A9A9", "nav": "#222222"}}'::jsonb, false, 6),
  ('sand', 'Sand', '{"light": {"primary": "#5B4632", "secondary": "#A5876B", "background": "#FBF1DF", "surface": "#FFFFFF", "text": "#2B2116", "muted": "#6A5A48", "nav": "#31271E"}, "dark": {"primary": "#E3C6A2", "secondary": "#EAD3B5", "background": "#19140F", "surface": "#262019", "text": "#F6EEE3", "muted": "#BFB09C", "nav": "#31271E"}}'::jsonb, false, 7),
  ('monochrome', 'Monochrome', '{"light": {"primary": "#51555D", "secondary": "#8A8F97", "background": "#F3F3F3", "surface": "#FFFFFF", "text": "#26282C", "muted": "#5B5F66", "nav": "#FFFFFF"}, "dark": {"primary": "#E6E6E6", "secondary": "#BDBDBD", "background": "#121212", "surface": "#1E1E1E", "text": "#F2F2F2", "muted": "#A8A8A8", "nav": "#303030"}}'::jsonb, false, 8)
on conflict (id) do update set
  label = excluded.label, tokens_json = excluded.tokens_json,
  is_free = excluded.is_free, sort = excluded.sort;

-- Neon is the default look, so the free plan includes it (with the three it already had).
update public.plans
set features_json = jsonb_set(features_json, '{themes}', '["neon", "lavender", "ocean", "mint"]'::jsonb)
where code = 'free';
