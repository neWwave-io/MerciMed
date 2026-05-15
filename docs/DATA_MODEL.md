# Data model

A cheat sheet derived from `supabase/migrations/*.sql`. When the migrations and this doc disagree, the migrations win — update this file.

Last verified through migration `012_locations_and_saved.sql`.

All tables live in `public`. Ids are `uuid` with `gen_random_uuid()` defaults unless noted. RLS is currently disabled everywhere — see [SECURITY.md](SECURITY.md).

---

## Tables

### `profiles`

One row per signed-up user. Auto-created via a trigger on `auth.users` insert (see [Triggers](#triggers)).

| Column          | Type          | Notes |
|-----------------|---------------|-------|
| `id`            | `uuid` PK     | FK → `auth.users(id)` ON DELETE CASCADE. |
| `email`         | `text`        | Added in migration 005. Unique on `lower(email)` where not null. |
| `full_name`     | `text`        | Set by `RegisterScreen` via an explicit upsert (auth trigger doesn't capture it). |
| `avatar_url`    | `text`        | Added in migration 006. Public URL in the `avatars` Storage bucket. |
| `date_of_birth` | `date`        | Nullable. Not yet edited in the UI. |
| `gender`        | `text`        | Free text. Nullable. |
| `phone`         | `text`        | Nullable. Not yet edited in the UI. |
| `created_at`    | `timestamptz` | Defaults to `now()`. |

---

### `folders`

Self-referencing. Also used for "chat folders" via `is_chat`.

| Column              | Type          | Notes |
|---------------------|---------------|-------|
| `id`                | `uuid` PK     | |
| `user_id`           | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. |
| `name`              | `text`        | NOT NULL. |
| `parent_folder_id`  | `uuid`        | FK → `folders(id)` ON DELETE CASCADE (subfolders die with the parent). |
| `notes`             | `text`        | Added in migration 009. Optional folder-level description, often AI-revised via `revise-note`. |
| `is_chat`           | `boolean`     | Added in migration 011. `true` for folders auto-created from an in-chat upload. Home screen renders these separately. |
| `created_at`        | `timestamptz` | |

Indexes: `user_id`, `parent_folder_id`, `(user_id, is_chat, created_at)`.

Chat folders are created via `ensureChatFolderForConversation(...)` in `files_provider.dart`; the linked conversation gets its `folder_id` stamped to point back.

---

### `files`

| Column           | Type          | Notes |
|------------------|---------------|-------|
| `id`             | `uuid` PK     | |
| `user_id`        | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. |
| `folder_id`      | `uuid`        | FK → `folders(id)` **ON DELETE SET NULL**. Orphans have `folder_id=null` and are invisible to the current UI. |
| `file_name`      | `text`        | Display name (sanitized version goes into storage path). |
| `file_type`      | `text`        | MIME at upload time. |
| `storage_path`   | `text`        | `medical-files/{user_id}/{uuid}/{name}`. |
| `extracted_text` | `text`        | JSON-stringified extraction output from `scan-medical-file`. Read by the chat function to build the inventory block. |
| `notes`          | `text`        | Added in migration 004. Free-text user note, autosaved with 800ms debounce. Also passed to `scan-medical-file` so it becomes the first RAG chunk. |
| `ai_scan_status` | `text`        | `'pending' \| 'done' \| 'failed'`. NOT NULL, default `'pending'`. |
| `created_at`     | `timestamptz` | |

Indexes: `user_id`, `folder_id`.

---

### `conversations` (migration 010)

One row per named chat with Mercie. A user can have many.

| Column        | Type          | Notes |
|---------------|---------------|-------|
| `id`          | `uuid` PK     | |
| `user_id`     | `uuid`        | FK → `auth.users(id)` ON DELETE CASCADE. |
| `title`       | `text`        | Nullable. Auto-set by the chat function from the first user message if null. |
| `folder_id`   | `uuid`        | Added in migration 011. FK → `folders(id)` ON DELETE SET NULL. Points to the auto-created `is_chat=true` folder for files uploaded in this chat. |
| `created_at`  | `timestamptz` | |
| `updated_at`  | `timestamptz` | Bumped by the chat function on every `[DONE]` so the conversation list sorts newest-first. |

Index: `(user_id, updated_at desc)`.

---

### `chat_messages`

| Column           | Type          | Notes |
|------------------|---------------|-------|
| `id`             | `uuid` PK     | |
| `user_id`        | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. Always the signed-in user. |
| `conversation_id`| `uuid`        | Added in migration 010. FK → `conversations(id)` ON DELETE CASCADE. Backfilled into a "Main" conversation per user. |
| `role`           | `text`        | `'user' \| 'assistant'`. NOT NULL. |
| `content`        | `text`        | NOT NULL. May contain `[[file:NAME]]` attachment markers in user messages. |
| `created_at`     | `timestamptz` | Ordering field. The chat function staggers paired user/assistant inserts by 1ms so the client can sort deterministically. |

Index: `(conversation_id, created_at)`.

Inserted only by the `chat` Edge Function after the OpenAI stream completes (both messages in one `.insert(...)`).

---

### `ai_chunks`

Embeddings for RAG. One row per ~500-word chunk extracted from each file, plus a leading chunk for the user's notes when present.

| Column       | Type          | Notes |
|--------------|---------------|-------|
| `id`         | `uuid` PK     | |
| `file_id`    | `uuid`        | FK → `files(id)` ON DELETE CASCADE. Cleanup is automatic on file delete. |
| `user_id`    | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. Denormalized for fast filtering. |
| `chunk_text` | `text`        | NOT NULL. |
| `embedding`  | `vector(1536)`| `text-embedding-3-small`. |
| `created_at` | `timestamptz` | |

Indexes: `file_id`, `user_id`, **IVFFlat on `embedding` with `vector_cosine_ops`** (`lists = 100`).

---

### `relationships`

Bidirectional family-sharing edges.

| Column              | Type          | Notes |
|---------------------|---------------|-------|
| `id`                | `uuid` PK     | |
| `requester_id`      | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. |
| `target_id`         | `uuid`        | FK → `profiles(id)` ON DELETE CASCADE. |
| `relationship_type` | `text`        | `Mom / Dad / Sister / Brother / Spouse / Other` (free text). |
| `status`            | `text`        | `'pending' \| 'approved'`. Declines are deletes. |
| `created_at`        | `timestamptz` | |

Constraints: `CHECK (requester_id <> target_id)`. Indexes: `requester_id`, `target_id`.

Helper SQL function:

```sql
public.has_approved_relationship(owner_id uuid) returns boolean
```

Used by the (currently disabled) RLS policies on `files` and `ai_chunks`, and by the (currently disabled) storage policy for `medical-files`.

---

### `hospitals` and `doctors`

Reference data injected into the chat system prompt.

`hospitals`: `id, name, address, phone, specialties text[], latitude double precision, longitude double precision, created_at`.

`doctors`: `id, hospital_id (FK → hospitals, ON DELETE SET NULL), name, specialty, phone, created_at`.

**Both tables are empty by default.** No seed file in the repo yet. Adding seed data (including coords) is high-leverage — see [ROADMAP.md](ROADMAP.md).

---

### `saved_hospitals` and `saved_doctors` (migration 012)

User-starred favourites. Composite primary keys, no surrogate `id`.

`saved_hospitals`:
| Column        | Type          | Notes |
|---------------|---------------|-------|
| `user_id`     | `uuid` (PK)   | FK → `auth.users(id)` ON DELETE CASCADE. |
| `hospital_id` | `uuid` (PK)   | FK → `hospitals(id)` ON DELETE CASCADE. |
| `created_at`  | `timestamptz` | |

`saved_doctors`:
| Column      | Type          | Notes |
|-------------|---------------|-------|
| `user_id`   | `uuid` (PK)   | FK → `auth.users(id)` ON DELETE CASCADE. |
| `doctor_id` | `uuid` (PK)   | FK → `doctors(id)` ON DELETE CASCADE. |
| `created_at`| `timestamptz` | |

Use `upsert` (not `insert`) to avoid conflicts on the composite PK. Both tables are on the realtime publication so the profile screen reflects saves instantly.

---

## Storage

Two buckets:

- **`medical-files`** (private, created in 001). Path layout: `medical-files/{user_id}/{uuid}/{sanitized_name}`. Reads use 30-minute signed URLs from `file_detail_screen.dart::_signedUrl`.
- **`avatars`** (public, created in 006). Profile images, exposed via the public URL directly.

Storage RLS is currently disabled (migration 008) with a wide-open `storage: allow all` policy as a catchall. See [SECURITY.md](SECURITY.md).

---

## Triggers

`public.handle_new_user()` is attached to `auth.users` AFTER INSERT. It inserts a row into `profiles` with `(id, email)`. The function is `SECURITY DEFINER` with `set search_path = public`.

```sql
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
```

The Flutter register flow follows up with an explicit `profiles.upsert({id, email, full_name})` because the trigger doesn't capture `full_name`.

---

## RPC functions

### `match_chunks(query_embedding vector(1536), requesting_user_id uuid, match_count int default 8)`

Defined in migration `003_match_chunks_function.sql`. Returns `(chunk_text text, similarity float)` ordered by cosine distance ascending (highest similarity first).

Filters to chunks where:
- `c.user_id = requesting_user_id` (own records), **or**
- `c.user_id` is the "other side" of an approved relationship with `requesting_user_id`.

Called by the `chat` Edge Function. Trusts the `requesting_user_id` argument — caller (Edge Function with `service_role`) is responsible for ensuring authenticity.

---

## Realtime

Migration 007 added every client-subscribed table to the `supabase_realtime` publication and set `REPLICA IDENTITY FULL` so UPDATE/DELETE events ship the full prior row. Subsequent migrations follow the pattern:

| Table             | In publication since |
|-------------------|----------------------|
| `folders`         | 007                  |
| `files`           | 007                  |
| `profiles`        | 007                  |
| `relationships`   | 007                  |
| `chat_messages`   | 007                  |
| `conversations`   | 010                  |
| `saved_hospitals` | 012                  |
| `saved_doctors`   | 012                  |

When adding a new table the client streams from, follow the same pattern in your migration:

```sql
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime'
                   and schemaname='public'
                   and tablename='YOUR_TABLE') then
    alter publication supabase_realtime add table public.YOUR_TABLE;
  end if;
end $$;

alter table public.YOUR_TABLE replica identity full;
```

---

## RLS

Disabled on every table today. The original policy set (the right starting point for re-enabling) is in migration `001_initial_schema.sql` from line 137 onwards. Migration 008 explicitly disables storage RLS as well. See [SECURITY.md](SECURITY.md).

---

## Migration history

| File                                | What it does |
|-------------------------------------|--------------|
| `001_initial_schema.sql`            | All initial tables, indexes, auth-user trigger, full RLS policy set, storage bucket + policies. |
| `002_remove_rls.sql`                | Drops every policy and disables RLS on every table. ⚠ Intentional dev-time posture — see SECURITY.md. |
| `003_match_chunks_function.sql`     | Adds the `match_chunks` RPC for RAG. |
| `004_notes_column.sql`              | Adds `files.notes`. |
| `005_profile_email.sql`             | Adds `profiles.email`, unique index, updates the trigger, backfills from `auth.users`. |
| `006_profile_avatar.sql`            | Adds `profiles.avatar_url`, creates public `avatars` Storage bucket. |
| `007_enable_realtime.sql`           | Explicit publication membership + `REPLICA IDENTITY FULL` for the realtime-subscribed tables. |
| `008_storage_policies.sql`          | Drops storage policies, tries to disable storage-objects RLS, falls back to a wide-open allow-all policy. |
| `009_folder_notes.sql`              | Adds `folders.notes`. |
| `010_conversations.sql`             | Adds `conversations` table + `chat_messages.conversation_id`. Backfills existing messages into a per-user "Main" conversation. |
| `011_chat_folders.sql`              | Adds `folders.is_chat` and `conversations.folder_id`. |
| `012_locations_and_saved.sql`       | Adds `hospitals.latitude/longitude` and the `saved_hospitals` / `saved_doctors` tables. |

New migrations should be sequentially numbered (`013_...`).
