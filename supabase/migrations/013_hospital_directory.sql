-- ============================================================
-- 013_hospital_directory.sql
--
-- Hospital directory enhancements for the OCIC-affiliated
-- profile-page directory and the chat function's triage path.
--
-- What this migration does:
--   1. Adds contact / branding columns to public.hospitals
--      (telegram_handle, messenger_url, website, logo_url) so
--      the Flutter Hospital model can render a directory card.
--   2. Adds an `is_ocic_affiliated boolean` flag to BOTH
--      `hospitals` and `doctors`. The chat Edge Function pulls
--      OCIC-only rows when triage calls for it, and the profile
--      page lists OCIC-affiliated hospitals as a curated
--      directory. The flag pattern (rather than a join table)
--      keeps the chat function's directory query a single
--      cheap `select`.
--   3. Adds a unique index on hospitals.name so we can seed
--      idempotently with `on conflict (name) do update`.
--   4. Seeds Intercare Hospital, the only verified
--      OCIC-operated hospital in the Olympia Medical Hub at
--      time of writing. OCIC affiliation is sourced from
--      primary research: OCIC.com.kh "About" page and
--      Intercare Hospital's own website
--      (https://intercarehospital.com). Other Olympia-tenant
--      clinics — Hospicare, Forever Young, Singapore Medical
--      Concierge, Olinpiy, IMEC, ABSC — were NOT seeded
--      because their OCIC affiliation is unverified at this
--      time.
--   5. Adds public.hospitals to the supabase_realtime
--      publication (migration 007 didn't include it) and
--      sets replica identity full so UPDATE/DELETE events
--      ship the full prior row.
--
-- RLS posture: this migration intentionally does NOT touch RLS.
-- RLS is currently off project-wide — see docs/SECURITY.md.
-- Re-enabling RLS is a separate, larger task.
-- ============================================================

-- 1) Hospital contact / branding columns
alter table public.hospitals
  add column if not exists telegram_handle    text,
  add column if not exists messenger_url      text,
  add column if not exists website            text,
  add column if not exists logo_url           text,
  add column if not exists is_ocic_affiliated boolean not null default false;

-- 2) Doctor OCIC flag (parallel to the hospital flag so chat
--    triage can pull OCIC-only doctors with a single filter).
alter table public.doctors
  add column if not exists is_ocic_affiliated boolean not null default false;

-- 3) Unique index on hospitals.name to support idempotent seeding.
create unique index if not exists hospitals_name_unique
  on public.hospitals (name);

-- 4) Seed Intercare Hospital (only verified OCIC-operated hospital).
--    Lat/lng below are approximate centre of the Olympia Medical Hub
--    area in Phnom Penh.
--    TODO: verify exact coords against an authoritative source
--          (Google Maps pin / OpenStreetMap) before public launch.
insert into public.hospitals (
  name, address, phone, specialties, latitude, longitude,
  telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Intercare Hospital',
  'Olympia Medical Hub, Bldg C5, St 161, Veal Vong, 7 Makara, Phnom Penh',
  '+855 23 996 900',
  array['General Medicine','Emergency','Pediatrics','Internal Medicine']::text[],
  11.5563,  -- TODO: verify exact coords
  104.9070, -- TODO: verify exact coords
  'intercarehospital',
  'https://m.me/intercarehospital',
  'https://intercarehospital.com',
  true
)
on conflict (name) do update set
  address            = excluded.address,
  phone              = excluded.phone,
  specialties        = excluded.specialties,
  latitude           = excluded.latitude,
  longitude          = excluded.longitude,
  telegram_handle    = excluded.telegram_handle,
  messenger_url      = excluded.messenger_url,
  website            = excluded.website,
  is_ocic_affiliated = excluded.is_ocic_affiliated;

-- 5) Realtime publication membership for hospitals (the chat
--    flow doesn't need this, but the profile-page directory
--    benefits from live updates when admins seed new rows).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'hospitals'
  ) then
    alter publication supabase_realtime add table public.hospitals;
  end if;
end $$;

alter table public.hospitals replica identity full;
