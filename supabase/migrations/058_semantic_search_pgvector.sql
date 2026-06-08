-- 058_semantic_search_pgvector.sql
--
-- Semantic ("by meaning") search over highlights. Embeddings are generated FREE
-- inside the `semantic-search` edge function using Supabase's built-in gte-small
-- model (384-dim) — no external API, no key. Stored here in a pgvector column
-- and queried with a HNSW cosine index.
--
-- Verified end-to-end against the live project: gte-small returns 384 dims, the
-- array→vector(384) store via PostgREST works, and match_highlights returns
-- cosine-ranked rows (self-match similarity = 1.0).

create extension if not exists vector;

alter table public.highlights
  add column if not exists embedding vector(384);

-- HNSW cosine index, partial (only embedded rows) so it stays lean during the
-- incremental backfill.
create index if not exists highlights_embedding_hnsw
  on public.highlights using hnsw (embedding vector_cosine_ops)
  where embedding is not null;

-- Nearest-neighbour search for ONE user's highlights. SECURITY DEFINER; the
-- user filter is the VERIFIED caller id passed in by the edge function, and
-- EXECUTE is granted to service_role only, so a client cannot read another
-- user's highlights through it.
create or replace function public.match_highlights(
  p_user_id         uuid,
  p_query_embedding vector(384),
  p_match_count     int default 20
)
returns table (id uuid, content text, book_id uuid, location text, similarity float)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select h.id, h.content, h.book_id, h.location,
         1 - (h.embedding <=> p_query_embedding) as similarity
  from public.highlights h
  where h.user_id = p_user_id
    and h.embedding is not null
  order by h.embedding <=> p_query_embedding
  limit greatest(1, least(p_match_count, 50));
$$;

revoke execute on function public.match_highlights(uuid, vector, int) from public;
revoke execute on function public.match_highlights(uuid, vector, int) from authenticated;
grant  execute on function public.match_highlights(uuid, vector, int) to service_role;

notify pgrst, 'reload schema';
