# Development

How to get a working dev loop on both the Flutter app and the Supabase backend.

---

## Prereqs

- **Flutter** ≥ 3.11 (matches `pubspec.yaml`'s `sdk: ^3.11.0`). `flutter doctor` should be all green for at least one mobile target.
- **Xcode** (iOS sim) and/or **Android Studio + an emulator**.
- **Supabase CLI** — for working on migrations / Edge Functions. `brew install supabase/tap/supabase` on macOS.
- **Deno** is bundled with the Supabase CLI; you don't need to install it separately.
- A login on the shared Supabase project (`xoqrnubowganptouxiih`) if you need to deploy changes to the hosted backend.

---

## Run the Flutter app

```bash
cd mercimed
flutter pub get
flutter run            # picks the connected device / running sim
flutter run -d ios     # explicit iOS sim
flutter run -d android # explicit Android
```

The app reads the Supabase URL + anon key from `lib/supabase_config.dart` (hardcoded today — see [SECURITY.md](SECURITY.md) for why that should change). No `.env` setup is needed to run against the hosted project.

Quality gates:

```bash
flutter analyze        # static analysis; uses package:flutter_lints
flutter test           # the only test is a placeholder — see ROADMAP.md
```

Hot reload works as usual (`r` in the terminal). Most state lives in Riverpod providers, which survive hot reload.

---

## Working on the backend

Two things you can change: **migrations** (Postgres schema, functions, policies) and **Edge Functions** (`chat`, `scan-medical-file`).

### Local Supabase

```bash
cd supabase
supabase start                 # boots Postgres + Studio + Edge runtime locally
supabase status                # prints local URLs + anon key
supabase db reset              # apply ALL migrations cleanly to local DB
```

`supabase db reset` replays `migrations/*.sql` in order. Use it freely while iterating — your local DB is ephemeral.

To point the Flutter app at local Supabase:
- temporarily edit `mercimed/lib/supabase_config.dart` with the URL + anon key from `supabase status`,
- or (better) plumb `--dart-define` support in (see SECURITY.md #3) and use `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.

### Migrations

Create a new file in `supabase/migrations/`, named `NNN_short_description.sql` where `NNN` is the next sequential number (next would be `006`).

```bash
# scaffold
touch supabase/migrations/006_my_change.sql

# verify locally
supabase db reset

# deploy to hosted project
supabase link --project-ref xoqrnubowganptouxiih    # one-time per machine
supabase db push                                     # applies new migrations to remote
```

Migrations should be **idempotent on retry where safe** (`create extension if not exists`, `add column if not exists`, etc.) but irreversible operations should fail loudly if assumptions don't hold.

### Edge Functions

```bash
# run locally with hot reload
supabase functions serve chat --env-file ./supabase/.env.local
supabase functions serve scan-medical-file --env-file ./supabase/.env.local

# deploy
supabase functions deploy chat
supabase functions deploy scan-medical-file
```

You'll need a `supabase/.env.local` (gitignored) with:

```env
OPENAI_API_KEY=sk-...
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<from `supabase status`>
```

For the hosted project, set these via the dashboard → Project Settings → Edge Functions → Secrets.

The Flutter app reaches functions via `$supabaseUrl/functions/v1/<name>`. For `scan-medical-file` it uses `supabase.functions.invoke('scan-medical-file', ...)`. For chat it uses raw `dio` because it needs to read the SSE stream (see `chat_provider.dart`).

---

## Useful commands

```bash
# Flutter
flutter clean && flutter pub get              # nuke build caches
flutter pub outdated                          # check for dep updates
flutter build apk --release                   # Android release build
flutter build ios --release                   # iOS release build (needs signing)

# Supabase
supabase migration new <name>                 # scaffolds a timestamped migration (won't match NNN_ convention — rename)
supabase db diff -f <name>                    # diff local schema → new migration
supabase gen types typescript --linked        # generate TS types for the Edge Functions (currently unused)
supabase functions logs chat --since 1h       # tail hosted function logs
```

---

## Project tour for a new contributor

1. Read [`CLAUDE.md`](../CLAUDE.md) end to end — 5 minutes, covers the lay of the land.
2. Skim [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) sections 1-2.
3. Run `flutter run` against the hosted project, sign up, upload an image of a lab report, wait for the badge to flip to "done", and ask Mercie a question about it. If that works end-to-end, your environment is set up.
4. If you're touching the backend, run `supabase start` and `supabase db reset` and confirm the local DB matches the live schema (Studio at `http://127.0.0.1:54323`).
5. Skim [`docs/SECURITY.md`](SECURITY.md) so you don't accidentally make the RLS problem worse.

---

## Debugging tips

- **"My change didn't show up in the UI"** — almost always means Realtime isn't enabled for that table. Supabase dashboard → Database → Replication → check the box. The app does not poll.
- **`ai_scan_status` stuck on `pending`** — open `supabase functions logs scan-medical-file`. Common causes: bad MIME type, gpt-4o non-JSON response, embedding API quota.
- **Chat "Mercie is unavailable right now."** — `supabase functions logs chat`. Common cause: stale OpenAI key, or a model returning a 4xx (e.g. content filter on uploaded text).
- **`409 conflict` on storage upload** — the file at that exact storage path already exists. The pseudo-UUID in the path includes `microsecondsSinceEpoch` so true collisions are rare; this usually means the user retried after a partial success.
- **Folders/files show for the wrong owner** — check `activeOwnerProvider`. The home screen "Viewing X's records" banner shows when an override is set; `effectiveOwnerIdProvider` is the single source of truth.

---

## Things you don't need to do

- You don't need to install Deno separately — Supabase CLI bundles it.
- You don't need to set up `freezed` / `json_serializable` / `build_runner` — models are hand-written. Don't add codegen for a single model.
- You don't need to maintain TypeScript types for Edge Function ↔ Flutter contracts — payloads are small and reviewed inline. Keep it that way unless they grow.
- You don't need to commit `pubspec.lock` changes if you only ran `flutter pub get` (no version change). Do commit them on actual dep changes.
