# CLAUDE.md — MerciMed

Engineering brief for working on MerciMed. Read this once, keep it open the first day. Deep dives live under `docs/`.

Last verified against `33ebb4f` + an uncommitted Phase 1 ship covering UX issues 1–3, profile edit + SOS + OCIC directory, mascot swap-point prep, hospital directory migration 013, drift-backed folders cache, persistent blob cache, and the offline banner. See section 10 for the full ship log.

---

## 1. What MerciMed is

A personal medical-records app with an AI assistant ("Mercie").

- A patient signs up, uploads medical documents (PDFs / images of lab panels, scans, prescriptions) into folders.
- An OCR + extraction pipeline (OpenAI gpt-4o vision) pulls structured fields (diagnoses, medications, lab values, dates, doctors, symptoms) and a plain-English summary out of every file.
- Extracted text is chunked, embedded with `text-embedding-3-small`, and stored as `vector(1536)` rows in Postgres (`ai_chunks`) for RAG.
- The chat screen lets the patient hold **multiple** named conversations with Mercie. Each call to the chat Edge Function does vector search over the patient's chunks (plus any family who has shared records), grafts that context plus a full file-inventory and the hospital/doctor directory into a triage-tiered system prompt, and streams a gpt-4o reply back over Server-Sent Events.
- Inside chat the user can attach existing files (rendered as `[[file:Name.pdf]]` markers) or upload new ones on the spot; new uploads land in an auto-named "chat folder" via the `suggest-folder-name` Edge Function.
- Voice input on the chat composer (`speech_to_text` package, push-to-talk).
- Family sharing: a user invites a relative by email **or** user search; once both sides approve, the family member's avatar appears on the home screen and tapping it lets you view their records. RAG also draws from approved-family chunks.

Mobile-first Flutter UI (iOS + Android), Supabase backend.

---

## 2. Repo layout

```
.
├── CLAUDE.md                # this file
├── docs/                    # deeper docs — read on demand
│   ├── ARCHITECTURE.md      # end-to-end flows (upload, multi-chat, attachments, family)
│   ├── DATA_MODEL.md        # schema cheat sheet
│   ├── DEVELOPMENT.md       # setup, env vars, Supabase CLI, deploys
│   ├── SECURITY.md          # current posture + known issues (READ THIS)
│   └── ROADMAP.md           # known gaps + concrete next steps
├── image/                   # design artefacts (SVG architecture diagrams + PNG screen mocks)
├── mercimed/                # Flutter app (Dart >= 3.11)
│   ├── lib/
│   │   ├── main.dart        # Supabase.initialize + ProviderScope
│   │   ├── router.dart      # go_router + auth redirect + ShellRoute + cross-dissolve transitions
│   │   ├── supabase_config.dart  # ⚠ hardcoded URL + anon key — see SECURITY.md
│   │   ├── features/
│   │   │   ├── auth/        # login, register, AuthNotifier
│   │   │   ├── chat/        # Mercie — multi-conversation, SSE streaming, voice, attachments
│   │   │   ├── family/      # invite by email or user-search, relationships, activeOwner switcher
│   │   │   ├── files/       # home, folder, file detail, upload pipeline (incl. chat-folder branch)
│   │   │   └── profile/     # profile, avatar upload, saved hospitals/doctors, pending requests
│   │   └── shared/
│   │       ├── models/      # hand-written fromJson/toJson — no codegen
│   │       │   ├── conversation.dart   # NEW
│   │       │   ├── chat_message.dart   # now carries conversation_id
│   │       │   ├── profile.dart        # now carries avatar_url
│   │       │   ├── folder.dart         # now carries notes + is_chat
│   │       │   └── …                   # file_model, doctor, hospital, relationship
│   │       ├── theme/       # AppTheme (light only)
│   │       └── widgets/     # animated_background, app_bottom_nav, pill_text_field
│   ├── ios/Podfile          # CocoaPods file — committed
│   └── test/                # ⚠ only a placeholder test exists
└── supabase/
    ├── migrations/          # 001..012 — apply in order
    └── functions/           # Deno Edge Functions
        ├── chat/                  # RAG + multi-conversation + attachments + gpt-4o streaming
        ├── scan-medical-file/     # gpt-4o vision → JSON → embed → ai_chunks
        ├── revise-note/           # NEW — short note polishing (gpt-4o-mini)
        └── suggest-folder-name/   # NEW — 2–4 word folder name from chat context (gpt-4o-mini)
```

---

## 3. Tech stack

**Flutter app**
- Flutter / Dart SDK ^3.11
- State: `flutter_riverpod` ^2.6 (`Provider`, `StreamProvider`, `StateNotifier`)
- Routing: `go_router` ^14.8 with a single `ShellRoute`, auth redirect, custom cross-dissolve page transition (`_fadePage` in `router.dart`)
- Backend client: `supabase_flutter` ^2.9 (Auth + Postgres + Storage + Realtime)
- HTTP / SSE: `dio` ^5.8 (only used for the chat SSE stream)
- File handling: `file_picker`, `mime`, `path_provider`, `flutter_pdfview`, `cached_network_image`
- **Voice input**: `speech_to_text` ^7.0 + `permission_handler` ^11.3
- **Profile + dialer + emergency UX**: `image_picker` ^1.0 (avatar) + `url_launcher` ^6.2 (tel:/tg:/https for SOS + OCIC contact actions)
- **Local cache (offline)**: `drift` ^2.20 + `drift_flutter` + `sqlite3_flutter_libs` + `connectivity_plus` ^6.0 + `crypto`. Drift is the **only** place codegen is allowed in this repo — `dart run build_runner build --delete-conflicting-outputs` after schema changes.

**Backend (Supabase project `xoqrnubowganptouxiih`)**
- Postgres 15 with `pgvector` (IVFFlat index, cosine ops)
- Supabase Auth (email/password)
- Supabase Storage — `medical-files` (private), `avatars` (public)
- Supabase Realtime — drives every list in the app (publication membership explicit in migration 007)
- Deno Edge Functions (`chat`, `scan-medical-file`, `revise-note`, `suggest-folder-name`)
- OpenAI `gpt-4o` (chat + vision), `gpt-4o-mini` (note revision + folder naming), `text-embedding-3-small` (1536 dims)
- **Note**: `web_search_preview` was removed from the chat function — it's a Responses-API tool, not supported in the Chat Completions endpoint the function uses.

---

## 4. Run it

```bash
# Flutter app
cd mercimed
flutter pub get
flutter run                 # iOS sim, Android emulator, or attached device
flutter analyze             # lints — package:flutter_lints
flutter test                # only a placeholder test exists
```

The app points at the hosted Supabase project (URL + anon key are hardcoded in `lib/supabase_config.dart`). It just works against that project; no `.env` is needed to run locally — but see SECURITY.md before shipping.

Backend changes (migrations + Edge Functions) need the Supabase CLI — see `docs/DEVELOPMENT.md`.

---

## 5. Architecture in 60 seconds

```
┌──────────────┐    Supabase SDK     ┌──────────────────────┐
│  Flutter app │ ──────────────────▶ │  Auth / Postgres /   │
│              │ ◀── Realtime ────── │  Storage / Edge Fns  │
└──────┬───────┘                     └──────────┬───────────┘
       │ POST SSE                                │
       │ /functions/v1/chat                      │ service_role
       │ /functions/v1/scan-medical-file         │
       │ /functions/v1/revise-note               │
       │ /functions/v1/suggest-folder-name       │
       ▼                                          ▼
┌──────────────┐   RAG + tools     ┌──────────────────────┐
│ 4 edge fns   │ ─────────────────▶│  OpenAI              │
└──────────────┘                   │  • gpt-4o (chat+vis) │
                                   │  • gpt-4o-mini       │
                                   │  • embeddings        │
                                   └──────────────────────┘
```

Four flows you'll hit constantly. Full sequence walkthroughs are in `docs/ARCHITECTURE.md`.

**Upload + AI scan** (`features/files/providers/files_provider.dart` → `supabase/functions/scan-medical-file`)
1. `UploadNotifier.pickFile()` → `FileUploadDraft` → preview-and-notes sheet → `commitUpload(...)` validates size (≤ 20 MB) and uploads to Storage at `medical-files/{userId}/{uuid}/{name}`.
2. Inserts a row in `files` with `ai_scan_status='pending'` and optional `notes` from the picker dialog.
3. Fire-and-forget invokes the `scan-medical-file` Edge Function (passing `notes` in the payload). The function downloads the blob, base64-encodes, calls gpt-4o with `EXTRACTION_PROMPT` → JSON of `{diagnoses, medications, dates, doctor_names, lab_values, symptoms, summary}`, prepends the user's notes as the **first** RAG chunk so they're queryable, chunks the rest (~500 words), embeds each → inserts into `ai_chunks` → flips `ai_scan_status` to `done` (or `failed`).
4. UI never polls — Realtime on `files` delivers the badge update.

**Chat (Mercie)** (`features/chat/providers/chat_provider.dart` → `supabase/functions/chat`)
1. `ChatNotifier.sendMessage` ensures there's an active conversation (creates one if `activeConversationIdProvider` is null and no conversations exist for the user), shows an optimistic user bubble, opens a `dio` POST to `/functions/v1/chat` with `responseType: ResponseType.stream`. The payload now includes `conversation_id`.
2. The message string may contain `[[file:NameOfFile.pdf]]` markers from in-chat attachments. The persisted row keeps them (the bubble renders preview cards); the Edge Function strips them when building the prompt and resolves each attached file's full `extracted_text` into the system prompt.
3. The Edge Function: embeds the cleaned question → `supabase.rpc('match_chunks')` for top-8 cosine matches (own + approved family) → fetches hospitals/doctors → fetches the user's last 50 files for an **inventory block** (filename, folder, status, parsed summary/diagnoses/meds/labs) → builds a triage-tiered system prompt → streams gpt-4o tokens back as SSE `data: {token}\n\n`.
4. On `[DONE]`, the function inserts both user and assistant rows into `chat_messages` (stamped 1ms apart so the client sorts deterministically), then bumps `conversations.updated_at` and auto-titles the conversation from the first user message if `title` is null.
5. Realtime delivers the persisted rows back to Flutter. The optimistic bubble is hidden once its `role='user'` row appears in the persisted stream.

**Family sharing** (`features/family/providers/family_provider.dart`)
1. Two ways to invite: `sendInvite(email, type)` (case-insensitive lookup via `profiles.email`) or `sendInviteByUserId(targetUserId, type)` (used by the new user-search UI). Both check for an existing relationship in either direction before inserting a `pending` row.
2. Target sees the request via the incoming `relationships` stream → approves → status flips to `approved`.
3. `activeOwnerProvider` lets the user switch which user's records the home/folder/file screens show. `effectiveOwnerIdProvider` resolves it (override or `auth.currentUser.id`). All file/folder streams filter by that owner id.
4. **Chat does NOT switch on active owner.** It scopes by `effectiveConversationIdProvider` instead, which is per-user — when you're "viewing" family records on the home tab, chat is still your own conversations.

**Chat-side file upload + auto folder** (`features/chat/screens/chat_screen.dart::_pickAndUpload` → `suggest-folder-name`)
1. User taps the paperclip in the chat composer → `UploadNotifier.pickFile()` returns a `FileUploadDraft` (no preview sheet — chat uploads are silent).
2. App calls `suggest-folder-name` with the filename + last 6 history messages → 2-4 word folder name.
3. `ensureChatFolderForConversation(conversationId, name)` creates an `is_chat=true` folder if one doesn't exist for the conversation, and stamps `conversations.folder_id`.
4. Upload commits into that chat folder. The home screen renders chat folders in a separate section from manually-created folders.

---

## 6. Code conventions

Things the codebase consistently does — match them.

- **Riverpod patterns**: live data via `client.from('table').stream(primaryKey: ['id']).eq(...)` → wrap with `Provider.family.autoDispose` to derive filtered slices. Most paths now avoid `ref.invalidate` (the stream re-emits on insert/update/delete), but `FolderNotifier` explicitly invalidates `_ownerFoldersStreamProvider` after writes to keep folder-side mutations crisp during navigation transitions.
- **`.stream()` has a single `.eq()` limit** — filter further client-side (e.g. by `parent_folder_id`, by `status`, by `is_chat`).
- **Models**: plain Dart classes with manual `fromJson` / `toJson`. snake_case in DB/JSON, camelCase in Dart. No `freezed`, no `json_serializable`. Don't introduce codegen for one model; match the pattern.
- **Optimistic UI**: keep "in-flight" state in a `StateNotifier` (`ChatLive`, `UploadState`). Once the persisted Realtime stream re-emits with the real row, clear the optimistic slot. Pattern is in `chat_provider.dart`.
- **Edge Function invocation**: prefer `supabase.functions.invoke('name', body: {...})` from Flutter. Use raw `dio` only when you need streaming (chat is the sole case).
- **Errors**: silent fallbacks are intentional for notes auto-save (`file_detail_screen.dart`) and the post-upload scan invocation (`files_provider.dart`). Both rely on Realtime to surface the truth later. Don't add error UI here; do add it where the user is actively waiting.
- **Routing**: every authed route lives inside the `ShellRoute` in `router.dart`. The shell controls the bottom nav and the animated background. Hide-nav cases (chat, folder, file detail) are listed in `MainShell._hideNav`. Page transitions go through `_fadePage`; if you add a route, do the same so transitions stay consistent.
- **Theme**: only `AppTheme.lightTheme` exists. No dark mode. New screens should use `Scaffold(backgroundColor: Colors.transparent)` so the global `AnimatedBackground` shows through.
- **Markdown in chat**: the chat client renders **raw text**. The system prompt instructs the model never to emit markdown. If you change the UI, either keep the no-markdown rule or render markdown in the bubble — but the two must stay in sync.
- **Attachment markers**: `[[file:EXACT_FILENAME]]`. Filenames must match the row in `files.file_name` exactly. The model is instructed to cite filenames character-for-character so the client's `_refsIn` parser can render preview cards.
- **Lints**: `package:flutter_lints/flutter.yaml`. Don't disable rules globally; use `// ignore: <rule>` for surgical exceptions.

---

## 7. Critical things to know before changing anything

**Read [`docs/SECURITY.md`](docs/SECURITY.md) before any code change that touches data access. The summary:**

- 🚨 **RLS is OFF on every table.** Migration `002_remove_rls.sql` disabled RLS and dropped every policy. Migration `008_storage_policies.sql` then disabled storage-objects RLS and added a wide-open `storage: allow all` policy as a fallback for managed-Supabase environments where disabling RLS isn't permitted. The `activeOwner` "view family's records" feature trusts the client; there is no server-side enforcement of any kind today. Combined with the anon key being hardcoded in source, any authenticated user can read any other user's `files`, `chat_messages`, `conversations`, `ai_chunks`, `saved_*`, etc., via direct queries. **This is intentional dev-time posture, not a bug — but it must be re-enabled before production.**
- 🚨 **Edge Functions trust `user_id` from the request body.** None of the four functions validate the JWT to bind `user_id` to the caller. Bundled with the RLS state, this is the actual blast radius.
- 🚨 **Supabase URL + anon key are committed in `mercimed/lib/supabase_config.dart`.** Move to `--dart-define` / `String.fromEnvironment` before any real distribution.

**Other gotchas**

- **Realtime requires explicit publication membership.** Migration 007 made this a managed list (`folders`, `files`, `profiles`, `relationships`, `chat_messages`) and set `REPLICA IDENTITY FULL` on each so UPDATE/DELETE events carry the full prior row. New tables added later (`conversations`, `saved_hospitals`, `saved_doctors`) include their own `alter publication … add table …` in their migrations. **If a list looks frozen, that table isn't in the publication.**
- **Folder deletion still orphans files**: `files.folder_id` is `ON DELETE SET NULL`. Orphans (`folder_id=null`) don't render in any folder view and there's no "Unsorted" UI yet.
- **Chat folders are different from regular folders**: distinguished by `folders.is_chat=true`. The home screen renders them in a separate section. `FolderNotifier.create(...)` takes an `isChat:` flag; `ensureChatFolderForConversation` handles the chat-folder creation/linking handshake.
- **`scan-medical-file` is invoked from the client**, fire-and-forget. If the client dies between the upload and the invoke, the row stays `pending` forever. Re-invoking is non-idempotent — there's no `ai_chunks` cleanup before re-insert, so retries dupe chunks.
- **`scan-medical-file` PDF content-type fix**: the function uses `{type: 'file', file: {filename, file_data}}` for PDFs — the older Responses-API `input_file` shape doesn't work on Chat Completions. Don't revert it.
- **Chat history sent to gpt-4o is the full persisted history** of the active conversation — no truncation. Long conversations will eventually exceed context.
- **Chat formatting rule**: the system prompt is now strict ("no markdown — the client renders raw text"). If you change the prompt, keep this; the UI relies on it.
- **`scan` invocation is not idempotent**: re-invoking re-extracts, re-chunks, re-inserts into `ai_chunks`. Delete existing chunks first when adding a retry path.
- **`saved_hospitals` and `saved_doctors` use composite PKs** (`(user_id, hospital_id)` / `(user_id, doctor_id)`). Inserts will conflict gracefully if duplicated; use `upsert` rather than `insert` to be safe.
- **`hospitals.latitude` / `longitude` are nullable** and currently unpopulated. The chat surfaces hospitals as cards; map cards depend on coords. Seeding (see ROADMAP) needs to include them.

---

## 8. Where to look first for common tasks

| You want to…                              | Open this                                                         |
|------------------------------------------|-------------------------------------------------------------------|
| Add a new screen                          | `mercimed/lib/router.dart`, then a folder in `lib/features/`      |
| Add a new table or column                 | New file in `supabase/migrations/` (next: `013_...`)              |
| Change the AI assistant's behaviour       | `supabase/functions/chat/index.ts` (system prompt + RAG)          |
| Change what's extracted from documents    | `supabase/functions/scan-medical-file/index.ts` (`EXTRACTION_PROMPT`) |
| Change the AI note revision style         | `supabase/functions/revise-note/index.ts` (`SYSTEM_PROMPT`)       |
| Change auto-folder-naming behaviour       | `supabase/functions/suggest-folder-name/index.ts` (`SYSTEM_PROMPT`) |
| Change file upload validation             | `mercimed/lib/features/files/providers/files_provider.dart` (`UploadNotifier`) |
| Change the design tokens (colors, type)   | `mercimed/lib/shared/theme/app_theme.dart`                        |
| Adjust auth flow                          | `mercimed/lib/features/auth/` + `router.dart` redirect            |
| Tune RAG (chunk size, top-k, similarity)  | `scan-medical-file` (`chunkText`), `match_chunks` migration, `chat` (`match_count`) |
| Add chat features (attachments, voice)    | `mercimed/lib/features/chat/screens/chat_screen.dart`             |
| Manage conversations                      | `chat_provider.dart` — `ChatNotifier.{create,switchTo,delete,renameConversation}` |
| Wire up Realtime for a new table          | Add `alter publication supabase_realtime add table public.<X>;` to your migration + `REPLICA IDENTITY FULL`. |

---

## 9. Concrete improvements worth doing next

A prioritized punch list lives in [`docs/ROADMAP.md`](docs/ROADMAP.md). The top three:

1. **Re-enable RLS** (tables + storage) with the policies from migration 001 as the starting point, **and** verify the JWT inside each Edge Function to bind `user_id` to the caller.
2. **Replace client-invoked `scan-medical-file`** with a Storage webhook or DB trigger on `files` insert so scans always run even if the client dies mid-upload. Make scans idempotent (delete prior `ai_chunks` for the file before re-inserting).
3. **Seed `hospitals` and `doctors` (with coords)** — they're empty by default, which makes Mercie's "recommend a specialist / nearest hospital" branch useless. The new `latitude`/`longitude` columns from migration 012 are also unpopulated.

---

## 10. Recent ship log (Phase 1, on top of `33ebb4f`)

**Flutter UI**
- `lib/shared/widgets/app_bottom_sheet.dart` — `showAppBottomSheet<T>` helper with `kAppNavReservedHeight = 96` to clear the floating Merci pill. **Use this for every new bottom sheet.** Tall forms / search lists go to a full-screen `MaterialPageRoute(fullscreenDialog: true)` instead.
- `invite_family_sheet.dart` is now a full-screen `InviteFamilyPage`; chat history (`_openConversationsSheet`) and "all files" grid (`_AllFilesSheet`) are full-screen routes too.
- Home screen folder cards: 40 px rounded icon tile (Material icon chosen by keyword in `lib/features/files/util/folder_icon.dart`) + soft gradient background; `_kFolderColors` trimmed to the mint family.
- Home FAB: `_AddMenuFab` opens `showAddMenuSheet` (`lib/features/files/widgets/add_menu_sheet.dart`) with **New folder / Upload files / Create folder with files**. Multi-file picker via new additive `UploadNotifier.pickFiles({allowMultiple})`.
- `lib/features/profile/screens/edit_profile_screen.dart` at `/profile/edit` — avatar upload to `avatars/{uid}/avatar.jpg` (`image_picker`), edits to `full_name / date_of_birth / gender / phone`. Pencil affordance on the profile card.
- `lib/features/profile/widgets/emergency_sos_sheet.dart` — Cambodia 119 (Ambulance, highlighted), 117 (Police), 118 (Fire). Two-tap confirmation, opens system dialer via `url_launcher`'s `tel:` scheme. Tourist Police sub-dialog with PP + Siem Reap numbers (hard-coded; verified via TRC + GOV.UK).
- `lib/features/profile/widgets/care_providers_section.dart` — partner-hospitals list, reads `hospitals` table, filters `is_ocic_affiliated == true` client-side. Each card: phone, Telegram (`t.me/<handle>`), Maps directions.
- `lib/shared/widgets/app_bottom_nav.dart` — sparkle icon factored into `_MerciAvatar`; **MASCOT SWAP POINT** comment block. When artwork arrives, drop a Rive / SVG asset and swap (see `docs/MASCOT_BRIEF.md`).
- iOS Info.plist + Android queries intents added for `tel:`, `tg:`, `https:` and photo-library / camera usage.

**Backend**
- `supabase/migrations/013_hospital_directory.sql` — adds `telegram_handle, messenger_url, website, logo_url, is_ocic_affiliated` to `hospitals` (and `is_ocic_affiliated` to `doctors`), adds `hospitals_name_unique` index, seeds **Intercare Hospital** (the one verified OCIC-operated facility — see `docs/SECURITY.md` for the research note). Idempotent; `on conflict (name) do update`.
- `supabase/migrations/014_hospital_directory_expansion.sql` — adds `name_kh` column; updates Intercare with stronger verified data (24/7 emergency phone, Khmer name, logo URL); seeds **8 widely-used Phnom Penh hospitals** (Royal Phnom Penh, Sunrise Japan, Khema International, Calmette, Central, Hebron, Sen Sok IUH, Preah Kossamak) all with `is_ocic_affiliated = false` so they power the chat triage flow's hospital recommendations without polluting the Care Providers section on Profile. Header comment explains entries deliberately NOT seeded (closed facilities, unverified Olympia tenants, future-opening conglomerate hospital).

**Both migrations must be applied to the hosted Supabase project before the data shows up.** Run `supabase link --project-ref xoqrnubowganptouxiih` once, then `supabase db push` to apply 013 + 014 together. Until then, the Care Providers section will render "No partner hospitals configured yet."

**Offline (Phase 1 + 2)**
- `lib/shared/cache/local_db.dart` — drift schema for Folders, Files, Conversations, ChatMessages, BlobCache, Outbox. `AppDatabase` opens at `getApplicationSupportDirectory()/merci_med.sqlite`. Provider: `localDbProvider` (not autoDispose). Exposes watch/upsert/tombstone helpers per entity plus `wipeOwner(userId)`.
- `lib/shared/cache/blob_cache.dart` — persistent blob cache keyed by `storage_path`. Replaces the temp-dir + 30-min-signed-URL pattern in `file_detail_screen.dart`. Files persist under `app-support/blobs/<sha1>.<ext>` with `.nobackup` sibling (TODO: proper `NSURLIsExcludedFromBackupKey` channel).
- `lib/shared/cache/outbox.dart` — `OutboxWorker` with per-row exponential backoff (`min(2^attempts, 60)`s), drains FIFO on every online transition, clears `dirty` on success, broadcasts `OutboxConflict` on failure. `outboxWorkerProvider` is a non-autoDispose singleton; `main.dart` does `ref.watch(outboxWorkerProvider)` so it boots with the app.
- `lib/shared/providers/connectivity_provider.dart` — `isOnlineProvider` (defaults true until first emission).
- `lib/shared/widgets/offline_banner.dart` — thin amber banner wired into `MainShell` in `router.dart`. Visible across all routes when offline.
- `files_provider.dart`: **folders, files** providers now drift-backed via `_folderHydrationProvider` + `_fileHydrationProvider` (upsert + tombstone, both skipping `dirty` rows). `updateFileNotes(ref, id, notes)` is **write-through**: drift → online attempt → on failure/offline, enqueue in outbox. Folder create/rename/delete and file upload `throw OfflineMutationException` when offline (deferred to a future phase).
- `chat_provider.dart`: **conversations, chat_messages** drift-backed via `_conversationHydrationProvider` + `_messageHydrationProvider` (the latter re-subscribes on `effectiveConversationIdProvider` changes). SSE chat send remains online-only.
- `chat_screen.dart`: composer disabled offline; `_SendOrMicButton` greys to `#B0BAC4`.
- `auth_provider.dart`: `logout()` captures the user id pre-`signOut`, then calls `db.wipeOwner(id)` for owner-scoped local eviction.
- `file_detail_screen.dart`: subscribes to `outboxWorker.conflicts` and surfaces a red SnackBar when a conflict targets the open file.
- All entity models (`Folder`, `FileModel`, `Conversation`, `ChatMessage`) gained `fromDriftRow` + `toDriftCompanion({dirty})`.

**Docs**
- `docs/MASCOT_BRIEF.md` — designer-ready brief for "Pisey the Lotus Bud" (Phase 1 static SVG → Phase 2 Rive), palette pulled from `AppTheme`, references, budget, user-testing checklist.
- This section.

**Mascot artwork** is the only external blocker. Engineering is ready (swap point + brief).

## 11. Pointers

- **Design source of truth**: `image/screen/*.png` — Figma exports for each screen.
- **Architecture diagrams**: `image/mercimed_architecture.svg`, `image/mercimed_ai_pipeline_chat.svg`, `image/mercimed_ai_pipeline_upload.svg`.
- **Mascot brief**: `docs/MASCOT_BRIEF.md`.
- **Supabase project**: `xoqrnubowganptouxiih.supabase.co`.
- **GitHub**: `neWwave-io/MerciMed`.

When in doubt about how a piece fits, search the codebase before guessing — the patterns are consistent enough that finding one example is usually enough.
