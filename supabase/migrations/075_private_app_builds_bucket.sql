-- 075 — Make the orphaned `app-builds` storage bucket private (config drift).
--
-- Security audit (2026-07-17) found `app-builds` was the only bucket that was
-- BOTH public=true AND had zero storage.objects policies, and it is undocumented
-- (no migration created it, no code references it, empty). A policy-less public
-- bucket is never correct: while empty it leaks nothing, but its 78 MB limit fits
-- an app binary, so if a signed IPA/APK were ever dropped in it would become
-- world-readable with no gate. Flip it to private as the secure default; it's
-- empty so this has zero functional impact. If public build-download hosting is
-- wanted later, re-enable deliberately WITH an explicit read policy.

update storage.buckets set public = false where id = 'app-builds';
