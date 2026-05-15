-- ============================================================
-- Multi-conversation support for chat.
--
-- Adds a conversations table so a user can have many separate
-- chats with Mercie, and links every chat_messages row to one
-- conversation. Existing messages are backfilled into a single
-- "Main" conversation per user so nothing is lost.
-- ============================================================

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists conversations_user_id_idx
  on public.conversations (user_id, updated_at desc);

alter table public.chat_messages
  add column if not exists conversation_id uuid
    references public.conversations(id) on delete cascade;

create index if not exists chat_messages_conv_idx
  on public.chat_messages (conversation_id, created_at);

-- Backfill: each user with orphan messages gets a "Main" conversation.
do $$
declare
  u uuid;
  conv uuid;
begin
  for u in
    select distinct user_id
    from public.chat_messages
    where conversation_id is null
  loop
    insert into public.conversations (user_id, title)
    values (u, 'Main')
    returning id into conv;

    update public.chat_messages
    set conversation_id = conv
    where user_id = u and conversation_id is null;
  end loop;
end $$;

-- RLS is off for the rest of the schema (per migration 002 + 008); match
-- that posture so the client can read/write directly.
alter table public.conversations disable row level security;

-- Enable realtime so new conversations + title edits push to the client.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
end $$;

alter table public.conversations replica identity full;
