-- ============================================================
-- Remove all RLS policies and disable RLS on all tables
-- ============================================================

-- Drop all policies on user tables
drop policy if exists "profiles: own read"          on public.profiles;
drop policy if exists "profiles: own update"        on public.profiles;

drop policy if exists "folders: own all"            on public.folders;

drop policy if exists "relationships: participants read"    on public.relationships;
drop policy if exists "relationships: requester insert"     on public.relationships;
drop policy if exists "relationships: target update status" on public.relationships;
drop policy if exists "relationships: participants delete"  on public.relationships;

drop policy if exists "files: own or approved family read"  on public.files;
drop policy if exists "files: own insert"                   on public.files;
drop policy if exists "files: own update"                   on public.files;
drop policy if exists "files: own delete"                   on public.files;

drop policy if exists "ai_chunks: own or approved family read" on public.ai_chunks;
drop policy if exists "ai_chunks: own insert"                  on public.ai_chunks;
drop policy if exists "ai_chunks: own delete"                  on public.ai_chunks;

drop policy if exists "hospitals: authenticated read" on public.hospitals;
drop policy if exists "doctors: authenticated read"   on public.doctors;

drop policy if exists "chat_messages: own all" on public.chat_messages;

-- Drop storage policies
drop policy if exists "storage: own upload"                  on storage.objects;
drop policy if exists "storage: own or approved family read" on storage.objects;
drop policy if exists "storage: own delete"                  on storage.objects;

-- Disable RLS on all tables
alter table public.profiles      disable row level security;
alter table public.folders       disable row level security;
alter table public.files         disable row level security;
alter table public.relationships disable row level security;
alter table public.ai_chunks     disable row level security;
alter table public.hospitals     disable row level security;
alter table public.doctors       disable row level security;
alter table public.chat_messages disable row level security;
