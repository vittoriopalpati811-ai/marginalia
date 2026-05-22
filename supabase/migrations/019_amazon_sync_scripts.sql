-- ─── 019: Remote Amazon sync scripts ─────────────────────────────────────────
--
-- Stores the JS extractor for Amazon Kindle sync in Supabase.
-- This lets us hot-fix the extractor without an App Store review:
-- just UPDATE the active row's `script` column and all users get
-- the fix on their next sync.
--
-- The app fetches the script at sync time, caches it in SharedPreferences,
-- and falls back to the compiled-in extractor if the network call fails.

CREATE TABLE IF NOT EXISTS public.amazon_sync_scripts (
  id         SERIAL      PRIMARY KEY,
  version    INT         NOT NULL,
  script     TEXT        NOT NULL,
  is_active  BOOLEAN     NOT NULL DEFAULT true,
  notes      TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only authenticated users (admins) can write; anonymous can read active scripts.
ALTER TABLE public.amazon_sync_scripts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "amazon_scripts_select" ON public.amazon_sync_scripts;
CREATE POLICY "amazon_scripts_select"
  ON public.amazon_sync_scripts FOR SELECT
  USING (is_active = true);

-- Seed with the current extractor JS (v1).
-- To hot-fix: UPDATE amazon_sync_scripts SET script = '<new JS>', updated_at = now() WHERE version = <n>;
-- Or: INSERT a new version and set is_active = true, deactivate the old one.
INSERT INTO public.amazon_sync_scripts (version, script, is_active, notes)
VALUES (
  1,
  $JS$(function() {
  const results = [];

  // Each book section in the notebook
  const sections = document.querySelectorAll('#kp-notebook-annotations .a-section');

  sections.forEach(function(section) {
    const titleEl = section.querySelector('h2.kp-notebook-searchable, .kp-notebook-lib-title');
    const authorEl = section.querySelector('.kp-notebook-metadata .a-color-secondary');
    if (!titleEl) return;

    const bookTitle = (titleEl.innerText || '').trim();
    const bookAuthor = authorEl ? (authorEl.innerText || '').replace(/^by\s+/i, '').trim() : '';

    const highlightBlocks = section.querySelectorAll('[id^="highlight-"]');

    highlightBlocks.forEach(function(hlBlock) {
      const contentEl = hlBlock.querySelector('.kp-notebook-highlight');
      const locationEl = hlBlock.querySelector('.kp-notebook-highlight-location, .kp-notebook-metadata');
      const colorAttr = hlBlock.getAttribute('data-highlight-color') || (hlBlock.className.match(/kp-notebook-highlight-(\w+)/) || [])[1];

      if (!contentEl) return;

      const content = (contentEl.innerText || '').trim();
      if (!content) return;

      const locationText = locationEl ? (locationEl.innerText || '') : '';
      const locationMatch = locationText.match(/(?:location|posizione)\s+([\d\-]+)/i);

      results.push({
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        content: content,
        location: locationMatch ? locationMatch[1] : null,
        color: colorAttr || null
      });
    });
  });

  // Sanity check: if we found no highlights and there are annotation sections,
  // Amazon may have changed their DOM. Throw so the app shows a clear error
  // instead of silently importing 0 highlights.
  if (results.length === 0 && sections.length > 0) {
    throw new Error('SELECTOR_MISMATCH: found ' + sections.length + ' sections but 0 highlights. Amazon may have updated their DOM.');
  }

  return JSON.stringify(results);
})();$JS$,
  true,
  'Initial extractor — tested against read.amazon.com/kp/notebook as of 2026-05'
)
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';
