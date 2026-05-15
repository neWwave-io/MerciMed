# Roadmap — concrete next steps

A prioritized punch list of things that would meaningfully improve the codebase, derived from reading every file in the repo. Each item names the files you'd touch and roughly what shape the fix takes, so a contributor can pick one up cold.

The list is ordered roughly by impact-per-effort.

---

## ✅ Recently shipped (Phase 1)

See `CLAUDE.md` §10 for full file-level detail.

- ✅ `showAppBottomSheet` helper + bottom-sheet reclassification (issue 1)
- ✅ Google-Drive-style add menu with New folder / Upload files / Create folder with files (issue 2)
- ✅ Folder cards now use keyword-matched Material icons + mint gradient (issue 3)
- ✅ Edit Profile screen + avatar upload via `image_picker` (item 5a)
- ✅ Emergency SOS sheet — Cambodia 119/117/118 + Tourist Police, two-tap dialer-based confirmation (item 5b)
- ✅ OCIC care providers section on profile (item 5c) + migration 013 seeding Intercare
- ✅ Mascot swap point in `app_bottom_nav.dart` + designer brief at `docs/MASCOT_BRIEF.md` (item 4 — art commission is the only remaining blocker)
- ✅ Offline Phase 1: drift cache, persistent blob cache replacing the signed-URL temp-dir pattern, `OfflineBanner` wired into `MainShell`, **folders** provider drift-backed with Supabase→drift reconcile.
- ✅ Offline Phase 2: **files / conversations / chat_messages** providers converted to drift; `OutboxWorker` with exponential backoff drains pending file-notes edits on reconnect; conflict toasts in `file_detail_screen.dart`; folder mutations + uploads + chat send gated on `isOnlineProvider` (throw `OfflineMutationException` offline); `db.wipeOwner` on signOut for per-user eviction.

## 🟡 Still pending (Phase 3+, smaller items)

- Folder create/rename/delete offline (needs new outbox op set + tombstone semantics for deletes).
- File upload offline (needs persistent pending-uploads blob queue + reconnect retry; tied to the 20 MB cap + iCloud-exclusion handling).
- Migration `014_files_updated_at.sql` adding `files.updated_at` so the outbox can do real LWW. Today's outbox does "server exists → push wins, server gone → drop with conflict toast"; a concurrent web-side edit could be overwritten.
- BlobCache LRU eviction (`totalBytes()` is there, no trim policy yet).
- Proper `NSURLIsExcludedFromBackupKey` via platform channel (today uses a `.nobackup` sibling-file placeholder).
- Mascot artwork (Pisey the Lotus Bud) — commission externally per `docs/MASCOT_BRIEF.md`; engineering swap point ready in `app_bottom_nav.dart`.
- Khmer-language voice input — current `speech_to_text` is device-native and may struggle with Khmer. Switch to Whisper (~$0.006/min) or Deepgram if user testing confirms quality issues.

---

## Tier 1 — production blockers

### 1. Re-enable Row Level Security (and storage policies)

**Why**: see [SECURITY.md](SECURITY.md) §1 and §2. Today any authenticated user can read any other user's data.

**Where**: new migration `supabase/migrations/006_restore_rls.sql`. Use `001_initial_schema.sql` lines 137–283 as the starting point. Verify with a manual two-user test pass.

**Don't forget**: the storage bucket policies were dropped too. Re-add all three.

---

### 2. Verify JWT inside Edge Functions and use the verified `user.id`

**Why**: [SECURITY.md](SECURITY.md) §4. Today the `chat` function trusts a `user_id` field in the request body.

**Where**: `supabase/functions/chat/index.ts` (top of `Deno.serve`).

**Shape**:
```ts
const authHeader = req.headers.get('Authorization') ?? ''
const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: { Authorization: authHeader } },
})
const { data: { user }, error } = await userClient.auth.getUser()
if (error || !user) return new Response('Unauthorized', { status: 401, headers: CORS_HEADERS })

// then use user.id instead of the body's user_id
```

Apply the same pattern to `scan-medical-file` if/when it stops being invoked exclusively from the trusted client path.

---

### 3. Trigger `scan-medical-file` from the server, not the client

**Why**: today the Flutter app fires `_invokeScan` as fire-and-forget after `files.insert`. If the network drops, the row stays `ai_scan_status='pending'` forever. The fix also removes the duplicate-chunks risk on retries.

**Where**:
- Add a Postgres trigger on `files` insert that calls a small wrapper (using `pg_net` or `supabase_functions.http_request`) to invoke `scan-medical-file`.
- Or use a Storage webhook on the `medical-files` bucket.
- In `scan-medical-file/index.ts`, **delete any existing `ai_chunks` for `file_id` before inserting** so retries are idempotent.
- Remove `_invokeScan` from `files_provider.dart`.

---

### 4. Move Supabase creds out of source

**Where**: `mercimed/lib/supabase_config.dart`.

**Shape**:
```dart
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

Add `.env.example`, a `tool/run.sh` that reads `.env` and shells out to `flutter run` with `--dart-define`s, and document it in [DEVELOPMENT.md](DEVELOPMENT.md).

---

## Tier 2 — high-leverage usability

### 5. Seed `hospitals` and `doctors` (with coordinates) — Phnom Penh directory shipped, provinces pending

**Status**: Migration 013 + 014 now seed 9 verified hospitals: Intercare Hospital (OCIC-affiliated) + Royal Phnom Penh, Sunrise Japan, Khema International, Calmette, Central, Hebron, Sen Sok IUH, Preah Kossamak (all `is_ocic_affiliated = false`, used by chat triage). Phnom Penh coverage is solid.

**Pending**:
- Provincial coverage — no Siem Reap / Sihanoukville / Battambang hospitals seeded yet. Add in a `015_provincial_hospitals.sql`.
- `doctors` table is still empty. Seed a list of verified specialists at each hospital so the chat function's "recommend a specific doctor" branch has real names.
- Replace 4-decimal-approximation lat/lng with verified 6-decimal Google Maps pins for every entry.
- Confirm with OCIC reception whether Olinpiy Reproductive Medical Center is an Intercare sub-brand; if yes, flip `is_ocic_affiliated = true` for it.

---

### 6. Truncate chat history before sending to gpt-4o

**Why**: `chat_provider.dart` sends the **full** persisted history of the active conversation. Long-running conversations will eventually exceed context, and you'll pay tokens for irrelevant turns. The new file-inventory + attachments blocks in the system prompt also add token weight on every turn.

**Where**: `supabase/functions/chat/index.ts`. Take the last N (say 20) turns or implement rolling summary. Cap by token count, not message count. Consider also trimming the 50-file inventory to the most relevant subset when conversations grow.

---

### 7. Add a "root" / "all files" view

**Why**: deleting a folder sets `files.folder_id = NULL` (migration 001 line 35). Those orphans become invisible. There's no UI today that shows files without a folder.

**Where**:
- `mercimed/lib/features/files/screens/home_screen.dart` — add an "Unsorted" pseudo-folder card that links to a screen showing `folder_id IS NULL` files.
- Or: change FK to `ON DELETE CASCADE` so deleting a folder deletes its files (different product decision — confirm with design before doing this).

---

### 8. Verify the time-aware greeting

**Where**: `mercimed/lib/features/files/screens/home_screen.dart`. In the previous codebase the data path hardcoded `"Good evening,"` ignoring the time-aware `_greeting` getter. The screen was substantially rewritten in commit `18e3f18` — confirm whether this regression survived. If it did, swap the hardcoded literal for `_greeting`.

---

### 9. Real `FamilyScreen` (or remove the route)

**Why**: `mercimed/lib/features/family/screens/family_screen.dart` may still be a placeholder. The family UX is split between `home_screen.dart` (avatar row + add + the new user-search invite path), `profile_screen.dart` (pending requests), and `invite_family_sheet.dart`. Either consolidate into a real `FamilyScreen`, or delete the route from `router.dart` so the dead path doesn't ship.

---

## Tier 3 — quality + maintenance

### 10. Write tests

**Where**: `mercimed/test/widget_test.dart` is a placeholder. Targets ordered by ROI:
- Unit-test the `match_chunks` SQL function (call via the Supabase test runner; verify family inclusion).
- Widget-test `UploadNotifier` with a mocked `SupabaseClient` — size cap, error propagation, optimistic state.
- Widget-test `ChatNotifier`'s SSE parser — feed a recorded byte stream of `data:` frames and assert the buffer accumulates correctly and clears on `[DONE]`.
- Golden tests for `HomeScreen` and `FolderScreen` (the design is the spec — golden tests prevent visual regressions).

### 11. Error handling on the upload retry path

The snackbar in `folder_screen.dart::_onUploadTap` has a Retry action, but `clearError()` is called before retrying — the user never sees a second error if it fails again. Tighten the loop.

### 12. Set `ai_scan_status='failed'` on JSON parse fallback

In `scan-medical-file/index.ts` lines 136-151, if gpt-4o returns invalid JSON twice, the function still marks the file `done`. Mark `failed` (or a new `degraded` status) so the UI can surface that the extraction was lossy.

### 13. Address the chat-cancel-but-server-continues issue

When the user cancels (`ChatNotifier.cancelStreaming`), the Edge Function keeps generating and then inserts both rows into `chat_messages`. The persisted history then contains a message the user thought they cancelled. Either:
- Send a cancel signal to the server (harder; needs request correlation), or
- Don't persist on the function side until the Flutter client confirms it received the full stream.

### 14. Move static prompts into versioned files

Inline strings in `index.ts` make it hard to diff prompt changes. Move `EXTRACTION_PROMPT` and the chat `systemPrompt` template into `supabase/functions/_shared/prompts.ts` and import them. Keep a `// v3 — added lab_values` comment style header.

### 15. Index health for ivfflat

The IVFFlat index on `ai_chunks.embedding` is created with `lists = 100`. For very low row counts (< 1k chunks), this can be slower than a sequential scan. Once you have real data, run `ANALYZE ai_chunks;` and reconsider `lists`. Rule of thumb: `lists ≈ sqrt(N)` where `N` is total rows.

### 16. Use HNSW instead of IVFFlat (pgvector ≥ 0.5)

pgvector now supports HNSW, which gives better recall and avoids the "rebuild on data growth" awkwardness of IVFFlat. If your Supabase project's pgvector version supports it:

```sql
create index on ai_chunks using hnsw (embedding vector_cosine_ops);
```

(Replace, don't add — keep one ANN index per column.)

### 17. Make the "Viewing X's records" banner show on more screens

Today it only appears on the home screen. If you `activeOwnerProvider` to a family member, then navigate to a folder, you can forget whose records you're looking at. Lift the banner up to `MainShell` in `router.dart`.

### 18. Make `chat_messages` switch on active owner (or explicitly don't)

Decide and document: should `/chat` show the family member's chat history when viewing their records, or always your own? The current behaviour ("always your own") is intentional but undocumented in the UI — at minimum, dim the chat tab or surface a hint when an active owner is set.

### 19. Add a "Re-scan" action on the file detail screen

If `ai_scan_status='failed'` (or after a prompt tweak), the user needs a way to re-run extraction without re-uploading. Plumb an action that:
1. Deletes existing `ai_chunks where file_id = X`.
2. Sets `ai_scan_status = 'pending'`.
3. Triggers the scan (via the trigger added in #3, or a direct invoke as a stopgap).

### 20. Consider a darker theme

Pure design call — current `AppTheme` is light-only. Medical records are often viewed at night. Cheap win if you're already touching the theme.

### 21. Idempotent + race-safe `ensureChatFolderForConversation`

`files_provider.dart::ensureChatFolderForConversation` does a `select` → `insert folder` → `update conversation.folder_id`. Two near-simultaneous chat uploads in the same fresh conversation race-condition each other and can create two chat folders. Wrap the whole thing in a Postgres function (or use `INSERT … ON CONFLICT`) so only one folder ever wins.

### 22. Cancel server-side on conversation switch

`ChatNotifier.switchTo` / `create` calls `_cancel?.cancel('switching-conversation')` to drop the dio request, but the Edge Function keeps generating and persists the reply to the *original* conversation. Either send a cancel signal (needs request correlation) or delay `chat_messages.insert` until the client ACKs the full stream.

### 23. Voice-input fallback

`speech_to_text` + `permission_handler` were added for push-to-talk. Confirm graceful handling when the user denies microphone permission, and when the platform's STT engine isn't available (older Android, locale not installed). At minimum, hide the mic button instead of failing on tap.

---

## Things explicitly NOT recommended

- **Don't add codegen for models** (freezed / json_serializable). The pattern is consistent, the models are small, and codegen drag isn't worth it for ~7 classes.
- **Don't introduce a separate API server** between Flutter and Supabase. The Edge Functions + RPC layer is the right boundary; adding Node/Express in front of it doubles the deploy surface for no gain.
- **Don't try to do `.eq()` chaining on Supabase `.stream()`** — the SDK only allows one. Filter client-side after `.map()`, as `files_provider.dart` does today.
