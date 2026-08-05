-- 077 — Remove the playable-shelf scaffolding added in 076.
--
-- A shared shelf is a picture again: you look at it, you like it, you comment.
-- The founder's call after seeing the guessing game running — that level of
-- interaction was not wanted. Nothing in the app reads `posts.payload` or
-- `post_guesses` any more, so they come out rather than lingering as schema the
-- next session would have to reverse-engineer.
--
-- Safe to drop: both objects were created the same day, are written only by the
-- shelf-share flow, and the only rows in post_guesses were my own test answers.

drop function if exists public.post_guess_stats(uuid);
drop table    if exists public.post_guesses;
alter table   public.posts drop column if exists payload;
