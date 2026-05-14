-- ============================================================
-- MerciMed — Initial Schema Migration
-- ============================================================

-- Enable pgvector
create extension if not exists vector;

-- ============================================================
-- TABLES
-- ============================================================

-- profiles
create table public.profiles (
  id              uuid primary key references auth.users on delete cascade,
  full_name       text,
  date_of_birth   date,
  gender          text,
  phone           text,
  created_at      timestamptz not null default now()
);

-- folders (self-referencing for nested folders)
create table public.folders (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles on delete cascade,
  name             text not null,
  parent_folder_id uuid references public.folders on delete cascade,
  created_at       timestamptz not null default now()
);

-- files
create table public.files (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles on delete cascade,
  folder_id      uuid references public.folders on delete set null,
  file_name      text not null,
  file_type      text,
  storage_path   text not null,
  extracted_text text,
  ai_scan_status text not null default 'pending',
  created_at     timestamptz not null default now()
);

-- relationships (family sharing)
create table public.relationships (
  id                uuid primary key default gen_random_uuid(),
  requester_id      uuid not null references public.profiles on delete cascade,
  target_id         uuid not null references public.profiles on delete cascade,
  relationship_type text,
  status            text not null default 'pending',
  created_at        timestamptz not null default now(),
  constraint relationships_no_self_ref check (requester_id <> target_id)
);

-- ai_chunks (embeddings for RAG)
create table public.ai_chunks (
  id         uuid primary key default gen_random_uuid(),
  file_id    uuid not null references public.files on delete cascade,
  user_id    uuid not null references public.profiles on delete cascade,
  chunk_text text not null,
  embedding  vector(1536),
  created_at timestamptz not null default now()
);

-- hospitals (static reference data)
create table public.hospitals (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  address     text,
  phone       text,
  specialties text[],
  created_at  timestamptz not null default now()
);

-- doctors (static reference data)
create table public.doctors (
  id          uuid primary key default gen_random_uuid(),
  hospital_id uuid references public.hospitals on delete set null,
  name        text not null,
  specialty   text,
  phone       text,
  created_at  timestamptz not null default now()
);

-- chat_messages
create table public.chat_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles on delete cascade,
  role       text not null,
  content    text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- INDEXES
-- ============================================================

create index on public.folders (user_id);
create index on public.folders (parent_folder_id);
create index on public.files (user_id);
create index on public.files (folder_id);
create index on public.ai_chunks (file_id);
create index on public.ai_chunks (user_id);
create index on public.chat_messages (user_id);
create index on public.relationships (requester_id);
create index on public.relationships (target_id);

-- IVFFlat index for cosine similarity search on embeddings
create index on public.ai_chunks
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGN-UP
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles       enable row level security;
alter table public.folders        enable row level security;
alter table public.files          enable row level security;
alter table public.relationships  enable row level security;
alter table public.ai_chunks      enable row level security;
alter table public.hospitals      enable row level security;
alter table public.doctors        enable row level security;
alter table public.chat_messages  enable row level security;

-- ── profiles ────────────────────────────────────────────────
create policy "profiles: own read"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: own update"
  on public.profiles for update
  using (auth.uid() = id);

-- ── folders ─────────────────────────────────────────────────
create policy "folders: own all"
  on public.folders for all
  using (auth.uid() = user_id);

-- ── relationships ────────────────────────────────────────────
create policy "relationships: participants read"
  on public.relationships for select
  using (auth.uid() = requester_id or auth.uid() = target_id);

create policy "relationships: requester insert"
  on public.relationships for insert
  with check (auth.uid() = requester_id);

create policy "relationships: target update status"
  on public.relationships for update
  using (auth.uid() = target_id);

create policy "relationships: participants delete"
  on public.relationships for delete
  using (auth.uid() = requester_id or auth.uid() = target_id);

-- ── files ───────────────────────────────────────────────────
-- Helper: returns true if the calling user has approved access to owner's records
create or replace function public.has_approved_relationship(owner_id uuid)
returns boolean
language sql
security definer stable
as $$
  select exists (
    select 1 from public.relationships
    where status = 'approved'
      and (
        (requester_id = auth.uid() and target_id = owner_id)
        or
        (requester_id = owner_id   and target_id = auth.uid())
      )
  );
$$;

create policy "files: own or approved family read"
  on public.files for select
  using (
    auth.uid() = user_id
    or public.has_approved_relationship(user_id)
  );

create policy "files: own insert"
  on public.files for insert
  with check (auth.uid() = user_id);

create policy "files: own update"
  on public.files for update
  using (auth.uid() = user_id);

create policy "files: own delete"
  on public.files for delete
  using (auth.uid() = user_id);

-- ── ai_chunks ────────────────────────────────────────────────
create policy "ai_chunks: own or approved family read"
  on public.ai_chunks for select
  using (
    auth.uid() = user_id
    or public.has_approved_relationship(user_id)
  );

create policy "ai_chunks: own insert"
  on public.ai_chunks for insert
  with check (auth.uid() = user_id);

create policy "ai_chunks: own delete"
  on public.ai_chunks for delete
  using (auth.uid() = user_id);

-- ── hospitals & doctors (public read, no client writes) ─────
create policy "hospitals: authenticated read"
  on public.hospitals for select
  using (auth.role() = 'authenticated');

create policy "doctors: authenticated read"
  on public.doctors for select
  using (auth.role() = 'authenticated');

-- ── chat_messages ────────────────────────────────────────────
create policy "chat_messages: own all"
  on public.chat_messages for all
  using (auth.uid() = user_id);

-- ============================================================
-- STORAGE BUCKET
-- ============================================================

insert into storage.buckets (id, name, public)
values ('medical-files', 'medical-files', false)
on conflict (id) do nothing;

-- Authenticated users can upload their own files
create policy "storage: own upload"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'medical-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner or approved family can read
create policy "storage: own or approved family read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'medical-files'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.has_approved_relationship(
           ((storage.foldername(name))[1])::uuid
         )
    )
  );

-- Owner can delete their own files
create policy "storage: own delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'medical-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
