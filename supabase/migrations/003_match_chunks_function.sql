-- ============================================================
-- match_chunks: vector similarity search with family access
-- Called by the chat edge function via supabase.rpc()
-- ============================================================

create or replace function match_chunks(
  query_embedding  vector(1536),
  requesting_user_id uuid,
  match_count      int default 8
)
returns table (chunk_text text, similarity float)
language sql stable
as $$
  select
    c.chunk_text,
    1 - (c.embedding <=> query_embedding) as similarity
  from ai_chunks c
  where
    c.user_id = requesting_user_id
    or c.user_id in (
      select
        case
          when r.requester_id = requesting_user_id then r.target_id
          else r.requester_id
        end
      from relationships r
      where
        (r.requester_id = requesting_user_id or r.target_id = requesting_user_id)
        and r.status = 'approved'
    )
  order by c.embedding <=> query_embedding
  limit match_count;
$$;
