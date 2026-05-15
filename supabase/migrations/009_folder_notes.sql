-- ============================================================
-- Add optional notes column to folders so users can describe
-- what a folder is for at creation time.
-- ============================================================

alter table public.folders
  add column if not exists notes text;
