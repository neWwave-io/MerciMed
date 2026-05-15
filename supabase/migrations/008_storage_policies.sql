-- ============================================================
-- Fully remove RLS from storage (dev-only — re-add per-user
-- policies before going to production).
--
-- Migration 002 dropped every storage policy but RLS on
-- storage.objects stays enabled by default, which means "no
-- policy = deny all" and uploads return 403. This migration:
--   1. Drops any leftover storage policies.
--   2. Tries to disable RLS on storage.objects (works when the
--      migration role owns the table — usually the case on
--      self-hosted; on Supabase Cloud it may be a no-op).
--   3. Falls back to a wide-open policy so writes succeed even
--      when step 2 can't disable RLS.
-- ============================================================

-- 1) Drop any existing storage policies.
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
  loop
    execute format('drop policy if exists %I on storage.objects', pol.policyname);
  end loop;
end $$;

-- 2) Try to disable RLS on storage.objects.
do $$
begin
  execute 'alter table storage.objects disable row level security';
exception when others then
  -- Insufficient privilege on managed Supabase — fall through to step 3.
  null;
end $$;

-- 3) Wide-open catch-all policy. No-op when RLS is disabled, but lets
--    everything through when it isn't.
create policy "storage: allow all"
  on storage.objects
  for all
  using (true)
  with check (true);
