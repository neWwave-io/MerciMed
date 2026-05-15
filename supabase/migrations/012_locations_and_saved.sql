-- ============================================================
-- Hospital coordinates + per-user saved hospitals / doctors.
--
-- Lets the chat render a hospital-with-location card and a
-- doctor card, and lets the user star them so they show up on
-- the profile page.
-- ============================================================

alter table public.hospitals
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

create table if not exists public.saved_hospitals (
  user_id uuid not null references auth.users(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  primary key (user_id, hospital_id)
);

create table if not exists public.saved_doctors (
  user_id uuid not null references auth.users(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  primary key (user_id, doctor_id)
);

alter table public.saved_hospitals disable row level security;
alter table public.saved_doctors disable row level security;

-- Realtime so the profile page reflects new saves instantly.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='saved_hospitals') then
    alter publication supabase_realtime add table public.saved_hospitals;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='saved_doctors') then
    alter publication supabase_realtime add table public.saved_doctors;
  end if;
end $$;

alter table public.saved_hospitals replica identity full;
alter table public.saved_doctors  replica identity full;
