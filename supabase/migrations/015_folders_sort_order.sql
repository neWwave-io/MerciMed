-- 015_folders_sort_order.sql
--
-- Tracks the column that powers the home-screen drag-to-reorder folder grid
-- (introduced alongside the reorderable grid + `persistFolderOrder()` helper
-- in `mercimed/lib/features/files/providers/files_provider.dart`).
--
-- Idempotent so it's safe to apply against the hosted project where the
-- column was added directly during early iteration.
--
-- Ordering semantics (matches `_ownerFoldersStreamProvider`):
--   • Rows with `sort_order IS NOT NULL` come first, ascending by sort_order.
--   • Rows where `sort_order IS NULL` (older rows, freshly created folders
--     that haven't been dragged yet) come after, ordered by `created_at`.
-- `persistFolderOrder` writes 1-based positions (top-left = 1).

alter table public.folders
  add column if not exists sort_order integer;

-- Composite index keeps the per-user ordering scan cheap; the (user_id,
-- sort_order NULLS LAST) shape matches the dominant access pattern.
create index if not exists folders_user_sort_idx
  on public.folders (user_id, sort_order nulls last);
