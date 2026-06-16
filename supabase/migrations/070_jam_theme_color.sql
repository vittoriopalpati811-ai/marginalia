-- 070_jam_theme_color.sql
--
-- Per-jam theme colour. The jam owner can pick a colour and the whole jam
-- detail screen tints its cards / boxes / accents with it. Stored as a hex
-- string (e.g. "#C0CFB2"); NULL falls back to the default sage so existing
-- jams are unchanged. UPDATE on jams is already owner-only (migration 002),
-- so setting theme_color is owner-only too.
alter table public.jams add column if not exists theme_color text;
