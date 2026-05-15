# Architecture

Full sequence walkthroughs for the flows that matter. Visual versions live as SVGs under `image/`:
- `image/mercimed_architecture.svg` — system-level picture
- `image/mercimed_ai_pipeline_upload.svg` — scan pipeline
- `image/mercimed_ai_pipeline_chat.svg` — chat / RAG pipeline (pre-multi-conversation; treat the text below as authoritative)

This doc explains them at the code level. Last verified through commit `33ebb4f`.

---

## System overview

```
                      ┌─────────────────────┐
                      │  Flutter app        │
                      │  (iOS / Android)    │
                      └──────┬──────────────┘
                             │
            supabase_flutter │  (auth, postgrest, storage, realtime)
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│                       Supabase project                     │
│                                                            │
│  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────────────┐ │
│  │ Auth     │  │ Postgres │  │Storage │  │  Realtime     │ │
│  │(jwt/anon)│  │+ pgvector│  │medical-│  │ explicit pub  │ │
│  │          │  │          │  │ files  │  │ (mig 007)     │ │
│  │          │  │          │  │+avatars│  │               │ │
│  └──────────┘  └────┬─────┘  └────────┘  └──────────────┘ │
│                     │                                      │
│                     │ RPC: match_chunks(emb, uid, k)       │
│                     │                                      │
│   ┌─────────────────┴────────────────┐                     │
│   │           Edge Functions          │                    │
│   │  ┌─────────────────────────────┐ │                     │
│   │  │ chat              (SSE out) │ │  ──┐                │
│   │  │ scan-medical-file (HTTP)    │ │    │  service_role  │
│   │  │ revise-note       (HTTP)    │ │    │                │
│   │  │ suggest-folder-name (HTTP)  │ │    │                │
│   │  └─────────────────────────────┘ │    │                │
│   └───────────────────────────────────┘   │                │
└────────────────────────────────────────────│───────────────┘
                                             │
                                             ▼
                              ┌──────────────────────────┐
                              │ OpenAI API               │
                              │  • gpt-4o (chat + vision)│
                              │  • gpt-4o-mini           │
                              │  • text-embedding-3-small│
                              └──────────────────────────┘
```

**Auth model in one line:** Flutter holds a Supabase session (anon key + JWT). All Postgres + Storage access is via that JWT (RLS will be the source of truth once re-enabled — see [SECURITY.md](SECURITY.md)). Edge Functions run with `service_role` and bypass RLS, so they take on the responsibility of enforcing per-user access themselves.

---

## Flow 1 — Upload + AI scan

Files: `mercimed/lib/features/files/providers/files_provider.dart`, `supabase/functions/scan-medical-file/index.ts`.

```
User taps "+"                 Flutter                              Supabase                       OpenAI
─────────────                ─────────                            ──────────                      ────────

pickFile() ────────────────▶ FilePicker
                              ├─ size > 20 MB? → error
                              └─ return FileUploadDraft
                                  to the preview-and-notes sheet

commitUpload(folderId,
             notes,
             draft)        ▶
                              ├─ build storagePath
                              │   "{uid}/{uuid}/{name}"
                              ├─ storage.upload ─────────────────▶ medical-files (private)
                              ├─ files.insert  ──────────────────▶ files row (status=pending,
                              │                                    notes from picker)
                              │                                    ┐
                              │                                    │ Realtime row event
                              │                                    │ → UI sees the new card
                              │                                    │   immediately with a
                              │                                    │   "pending" badge
                              │                                    ┘
                              └─ functions.invoke ───────────────▶ scan-medical-file
                                  ("scan-medical-file",                │
                                   {record: {…, notes}})               │
                                                                       │
                                                                       ├─ storage.download
                                                                       ├─ base64 encode
                                                                       ├─ POST /chat/completions ─▶ gpt-4o vision
                                                                       │    EXTRACTION_PROMPT       (returns JSON
                                                                       │    PDFs: {type:'file',     of diagnoses,
                                                                       │      file:{filename,       meds, labs, …)
                                                                       │      file_data:b64}}
                                                                       │    Images: image_url
                                                                       ├─ JSON.parse (with
                                                                       │   markdown-fence strip
                                                                       │   fallback)
                                                                       ├─ chunkText(combined, 500)
                                                                       ├─ if notes present:
                                                                       │   unshift "Patient's own
                                                                       │     symptom notes
                                                                       │     (uploaded YYYY-MM-DD)
                                                                       │     attached to file
                                                                       │     'X': <notes>"
                                                                       │   as the first chunk
                                                                       ├─ for each chunk:
                                                                       │    POST /embeddings  ─────▶ text-embedding-3-small
                                                                       │    insert ai_chunks
                                                                       └─ update files
                                                                            extracted_text,
                                                                            ai_scan_status='done'
                                                                                                    ┐
                                                                                                    │ Realtime row event
                                                                                                    │ → UI flips badge
                                                                                                    │   to "done"
                                                                                                    ┘
```

### Things that surprise people

- **Invocation is fire-and-forget.** `_invokeScan` returns void; the UI never awaits it. State updates arrive via Realtime on `files`.
- **PDF content-type uses Chat-Completions shape** (`{type:'file', file:{filename, file_data}}`), not the Responses-API `input_file`. A previous version used the wrong shape; don't revert it.
- **The user's notes from the picker dialog become the first RAG chunk.** That's why "what did I write about this file?" can match in chat.
- **There is no Storage webhook or DB trigger.** If the client invocation never fires (crash, network drop), the file stays `ai_scan_status='pending'` indefinitely.
- **Re-invoking is non-idempotent.** Calling `scan-medical-file` twice on the same file produces duplicate `ai_chunks` rows. Any retry path should delete `ai_chunks where file_id = X` first.
- **Failure surface**: gpt-4o returning non-JSON → fence-strip fallback runs → if still bad, the entire raw response becomes `summary` and chunks are low-quality. The file is still marked `done`, not `failed`.
- **`failed` status is only set on thrown exceptions** in the Edge Function. The JSON-parse fallback above does NOT trigger it.
- **MIME inference is loose**: `file_type` is read from upload-time MIME, then the Edge Function regexes it for keywords ("pdf", "png", …). Anything else defaults to `image/jpeg`.

---

## Flow 2 — Chat (Mercie) with multi-conversation + attachments + RAG

Files: `mercimed/lib/features/chat/providers/chat_provider.dart`, `mercimed/lib/features/chat/screens/chat_screen.dart`, `supabase/functions/chat/index.ts`, `supabase/migrations/003_match_chunks_function.sql`, `supabase/migrations/010_conversations.sql`.

### Conversation lifecycle

```
conversationsStreamProvider   — live list of all conversations for user_id, ordered by updated_at desc
activeConversationIdProvider  — StateProvider<String?>; null means "use latest"
effectiveConversationIdProvider — resolves: explicit override > most recent > null (no conversations yet)

chatMessagesStreamProvider    — streams chat_messages WHERE conversation_id = effectiveId
```

The chat screen header lets the user pick from the list, rename, delete, or start a new conversation. `ChatNotifier` exposes `create()`, `switchTo(id)`, `deleteActive()`, `renameConversation(id, title)`.

### A single send

```
User types: "Does this look concerning?" with [[file:Echocardiogram_2024.pdf]] attached
            (the [[file:…]] marker is inserted by the composer when the user taps a file in
             the attachment tray — present in the persisted bubble too)

Flutter                                                    Supabase chat fn                    OpenAI
───────                                                    ────────────────                    ──────

ChatNotifier.sendMessage
 ├─ ensure activeConversationId — create one if list is empty and override is null
 ├─ build optimistic user bubble (ChatLive)
 ├─ pull persisted history from chatMessagesStreamProvider
 │   (already scoped to this conversation)
 ├─ dio.post('/functions/v1/chat',
 │           {user_id, conversation_id,
 │            message, history},
 │           responseType: stream)  ────────────────────▶  parse body
 │                                                         ├─ extract [[file:…]] markers from message
 │                                                         │   → attachmentNames[], cleanUserMessage
 │                                                         ├─ getEmbedding(cleanUserMessage) ───▶ text-embedding-3-small
 │                                                         ├─ rpc('match_chunks',           (RAG: top 8 chunks where
 │                                                         │      query_embedding,           user_id = me
 │                                                         │      requesting_user_id,        OR user_id in approved
 │                                                         │      8)                          family)
 │                                                         ├─ parallel:
 │                                                         │    select hospitals
 │                                                         │    select doctors
 │                                                         │    select files (last 50,
 │                                                         │      oldest first) for inventory
 │                                                         ├─ if attachments present:
 │                                                         │    select files where file_name in (…)
 │                                                         │    dedupe newest-per-name
 │                                                         │    format extracted_text + notes
 │                                                         │    into "ATTACHMENTS" block
 │                                                         ├─ build systemPrompt:
 │                                                         │   • fresh-session memory rule
 │                                                         │   • markdown-forbidden rule
 │                                                         │   • triage tiers (mild/mod/serious)
 │                                                         │   • chest-symptom safety rules
 │                                                         │   • attachments block (if any)
 │                                                         │   • file inventory (always)
 │                                                         │   • RAG context (always)
 │                                                         │   • hospital + doctor lists
 │                                                         └─ POST /chat/completions    ────▶ gpt-4o
 │                                                              stream: true                  (web_search_preview
 │                                                              max_tokens: 1000               REMOVED — not
 │                                                              messages: [sys, …hist,         supported in
 │                                                                         {user: clean}]      Chat Completions)
 │                                                                                            
 │                                                         SSE pump:
 │                                                         for each "data: {choices:[{delta:{content}}]}"
 │                                                           accumulate fullResponse
 │                                                           re-emit "data: {token: …}"  ──┐
 │                                                                                         │
 │  ◀───────── SSE: data: {"token":"That"} ───────────────────────────────────────────────┘
 │  ◀───────── SSE: data: {"token":" Echocardiogram_2024.pdf"} 
 │  ◀───────── …
 │  ◀───────── SSE: data: [DONE]
 │                                                         on [DONE]:
 │                                                         insert chat_messages (user + assistant,
 │                                                                               1ms-staggered created_at)
 │                                                         update conversations SET
 │                                                            updated_at = now(),
 │                                                            title = COALESCE(title,
 │                                                                             first-48-chars-of-user-msg)
 │                                                                                                ┐
 │                                                                                                │ Realtime delivers
 │                                                                                                │ both rows + the
 │                                                                                                │ updated conversation
 │  ◀───────────────────────────────────────────────────────────────────────────────────────────┘
 │
 └─ stream completes → _finalize() clears optimistic + buffer.
    Persisted bubbles take over; the bubble's _refsIn parser extracts file_name
    references and renders preview cards under the assistant message for each
    file the model named correctly.
```

### Important details

- **`history` is the full persisted history of the active conversation** — no truncation. Long conversations will eventually exceed context.
- **`[[file:Name]]` markers**: the client embeds them in the user message when the user attaches files. The persisted `chat_messages.content` keeps them (so the bubble renders preview cards on re-render). The chat function strips them before the model sees the message and looks up each attached file's `extracted_text` to inject into the system prompt.
- **File-citation contract**: the system prompt instructs the model to cite filenames "character-for-character". The client's `_refsIn` parser scans assistant responses for any string matching a known `file_name` and renders a tappable preview card.
- **No markdown allowed**: the bubble renders raw text. If the model emits `**bold**`, the user sees literal asterisks. The system prompt forbids markdown for this reason.
- **Auto-title**: when `conversations.title` is null on the first user message of a conversation, the chat function sets it to the first 48 chars (with ellipsis if truncated).
- **Web search removed**: previous versions enabled `web_search_preview` as a tool; that tool is a Responses-API feature and isn't supported by the `/chat/completions` endpoint the function uses. RAG context now does the work.
- **Cancellation note**: calling `ChatNotifier.cancelStreaming()` (or switching conversations mid-stream) cancels the client request and re-routes to a new conversation, but the Edge Function keeps generating and persists the result to the original conversation. Same constraint as before.

---

## Flow 3 — Chat-side file upload (auto chat folders)

Files: `mercimed/lib/features/chat/screens/chat_screen.dart::_pickAndUpload`, `files_provider.dart::ensureChatFolderForConversation`, `supabase/functions/suggest-folder-name/index.ts`.

```
User taps the paperclip in the chat composer

Flutter                                                Supabase                              OpenAI
───────                                                ─────────                             ──────

UploadNotifier.pickFile()
 └─ FilePicker → FileUploadDraft (no preview sheet — chat uploads are silent)

functions.invoke('suggest-folder-name',  ─────────▶ suggest-folder-name
   {file_name, message, history})                     ├─ build system prompt
                                                       │   ("2–4 word Title Case folder
                                                       │     name; reject 'Chat'/'Upload'…")
                                                       └─ POST /chat/completions ─────────▶ gpt-4o-mini
                                                                                            (returns "Heart
                                                                                             Symptoms"-style
                                                                                             name)

ensureChatFolderForConversation(conv, name)
 ├─ select conversations.folder_id where id=conv
 ├─ if folder_id exists → return it
 ├─ else insert folder (is_chat=true, name)
 └─ update conversations set folder_id=new
                                                       (no further server work)

commitUpload(folderId=chatFolder,
             notes=null,
             draft)
   → same as Flow 1 from this point on.

Composer then adds [[file:Name]] marker to the next message draft so it ships with
the user's question.
```

### Why this is split out

It keeps the records UI clean (no chat-only files mixed into Cardiology, Allergy, etc.) while still letting the chat reason over them. Home screen renders `is_chat=true` folders as a separate "Chat Folders" section.

---

## Flow 4 — Note revision

Files: `revise-note` Edge Function + the various dialogs that call it (folder-create sheet, file notes, etc).

```
Flutter                                Supabase                       OpenAI
───────                                ─────────                      ──────

functions.invoke('revise-note',   ──▶ revise-note
   {text, context?})                   ├─ trim → reject if empty/>800 chars
                                       └─ POST /chat/completions ──▶ gpt-4o-mini
                                                                    (returns 1–3 plain
                                                                     sentences, no
                                                                     markdown, no
                                                                     added facts)
                                       returns {revised}
 ◀───────────────────────────────────  
 swap field value with `revised`
```

Used today from the New Folder dialog and folder/file note editors. Trivial wrapper — no streaming, no history.

---

## Flow 5 — Family sharing + active-owner switching

Files: `mercimed/lib/features/family/providers/family_provider.dart`, `mercimed/lib/features/family/widgets/invite_family_sheet.dart`, `mercimed/lib/features/files/providers/files_provider.dart`.

```
Two parallel streams power this whole feature:

  _outgoingRelationshipsStreamProvider — relationships where requester_id = me
  _incomingRelationshipsStreamProvider — relationships where target_id    = me

From those we derive:
  pendingRequestsProvider        — incoming AND status=pending
  familyMembersForHomeProvider   — outgoing OR incoming, where status=approved → fetch the other profile

Invite (two entry points):
  Email path:
   FamilyNotifier.sendInvite(email, type)
     ├─ lookup target by profiles.email (ilike, case-insensitive)
     ├─ existing-relationship check (either direction)
     └─ insert relationships row (status=pending)

  User-search path (new):
   FamilyNotifier.sendInviteByUserId(targetUserId, type)
     ├─ existing-relationship check
     └─ insert relationships row (status=pending)

  Either path → other side's _incomingRelationshipsStreamProvider re-emits.

Approve:
  target taps approve
   └─ update relationships set status='approved' where id=…
         → both sides' familyMembersForHomeProvider re-emits with the new profile

Switch active owner:
  home screen avatar row shows You + approved family
   └─ tap an avatar → activeOwnerProvider.state = that.id
        → effectiveOwnerIdProvider re-resolves
        → _ownerFoldersStreamProvider re-subscribes with new user_id
        → _ownerFilesStreamProvider re-subscribes with new user_id
        → all derived providers (foldersProvider, filesProvider, folderStatsProvider) emit
        → "Viewing X's records" banner appears
```

### Pay attention to

- **Chat does NOT switch.** `chatMessagesStreamProvider` is scoped by `effectiveConversationIdProvider`, not by owner. You always chat as yourself, on your own conversation list.
- **Profile screen shows pending requests** — that's where invites get approved.
- **Two invite paths share validation logic.** When you change one (e.g. adding rate-limit), apply the same to the other.

---

## How Realtime is wired

Every list view in the app is a `client.from('table').stream(...)` — never a one-shot `.select()`. Migration 007 (and later migrations for new tables) explicitly adds each subscribed table to `publication supabase_realtime` and sets `REPLICA IDENTITY FULL` so UPDATE/DELETE events ship the full prior row.

The stack today:
- `auth.onAuthStateChange` → `_AuthChangeNotifier` → drives `GoRouter.refreshListenable`.
- `conversations.stream(eq:user_id)` → `conversationsStreamProvider`.
- `chat_messages.stream(eq:conversation_id)` → `chatMessagesStreamProvider`. Scoped by `effectiveConversationIdProvider`.
- `folders.stream(eq:user_id)` → `_ownerFoldersStreamProvider` → `foldersProvider(parentId)`.
- `files.stream(eq:user_id)` → `_ownerFilesStreamProvider` → `filesProvider(folderId)`, `folderStatsProvider`, `fileByIdProvider`.
- `relationships.stream(eq:requester_id|target_id)` → outgoing + incoming → `pendingRequestsProvider`, `familyMembersForHomeProvider`.
- `saved_hospitals.stream(eq:user_id)` and `saved_doctors.stream(eq:user_id)` → profile screen favourites.

**Single-`eq` limitation**: Supabase `.stream()` accepts exactly one `.eq()`. Filters on other columns happen client-side after the map (`parent_folder_id`, `status`, `is_chat`).

**Realtime must be in the publication for each table.** If a list looks frozen, that's the first thing to check — but with migrations 007/010/012 codifying the publication, this should be automatic for tables this repo defines.

---

## Storage layout

Two buckets:

```
medical-files (private)
  {user_uuid}/
    {timestampish-uuid}/
      {sanitized-filename}

avatars (public)
  {user_uuid}/...
```

- `medical-files` path is computed in `UploadNotifier.commitUpload`.
- `sanitizeName` replaces anything not `[A-Za-z0-9._-]` with `_`.
- The pseudo-UUID is `microsecondsSinceEpoch.toRadixString(36) + '-' + length.toRadixString(36)`.
- Original RLS policies enforced `(storage.foldername(name))[1] = auth.uid()::text` — keep this layout when re-enabling RLS.
- `medical-files` reads use short-lived signed URLs (`createSignedUrl(path, 1800)` — 30 minutes); `avatars` reads use the public URL directly.

---

## Where AI prompts live

- **Extraction prompt** (vision → JSON): `supabase/functions/scan-medical-file/index.ts` (`EXTRACTION_PROMPT`).
- **Chat system prompt** (RAG + inventory + directory + triage + safety): `supabase/functions/chat/index.ts` (built inline; the long `systemPrompt` string).
- **Note-revision prompt**: `supabase/functions/revise-note/index.ts` (`SYSTEM_PROMPT`).
- **Folder-name prompt**: `supabase/functions/suggest-folder-name/index.ts` (`SYSTEM_PROMPT`).

All are inline strings. If you iterate, add a `// v3 — added lab_values` comment style header so prompt changes are git-greppable.
