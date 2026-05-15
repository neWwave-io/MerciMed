-- ============================================================
-- Chat folders.
--
-- Files uploaded *from the chat screen* land in their own folder
-- named after the conversation. The home screen renders these
-- separately from manually-created folders.
-- ============================================================

alter table public.folders
  add column if not exists is_chat boolean not null default false;

alter table public.conversations
  add column if not exists folder_id uuid
    references public.folders(id) on delete set null;

create index if not exists folders_is_chat_idx
  on public.folders (user_id, is_chat, created_at);
