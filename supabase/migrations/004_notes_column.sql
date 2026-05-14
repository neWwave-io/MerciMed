-- ============================================================
-- Add user notes column to files
-- ============================================================
alter table public.files
  add column if not exists notes text;
