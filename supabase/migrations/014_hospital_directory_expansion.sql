-- ============================================================
-- 014_hospital_directory_expansion.sql
--
-- Expands the hospital directory beyond the OCIC-operated
-- Intercare entry seeded in 013. Adds:
--   * Re-affirmation / update of Intercare (Khmer name, logo URL,
--     verified 24/7 emergency phone — confirmed in 2026 research
--     pass against intercarehospital.com + ocic.com.kh).
--   * 8 widely-used Phnom Penh hospitals/clinics for the chat
--     triage flow. All `is_ocic_affiliated = false` so they do
--     NOT appear in the Profile screen's "Care providers"
--     section (which filters on the OCIC flag) but ARE available
--     to the `chat` Edge Function when it builds its hospital
--     directory block.
--
-- Notes on entries NOT seeded (so future contributors don't
-- mistakenly add them):
--   * Hospicare & Theara Consulting, Forever Young Group
--     Cambodia, Singapore Medical Concierge — Olympia Medical
--     Hub tenants but independent operators; no OCIC equity link
--     found in public materials.
--   * Olinpiy Reproductive Medical Center — listed only on
--     Olympia Medical Hub's own tenant page; no independent web
--     presence. Possibly an OCIC sub-brand of Intercare.
--     [UNVERIFIED] — pending direct confirmation with OCIC.
--   * Royal Rattanak Hospital — closed; consolidated into Royal
--     Phnom Penh Hospital.
--   * Naga Clinic — closed Oct 2019; replaced by AEMC. Needs
--     separate verification before seeding.
--   * $300M Royal Group + Chip Mong conglomerate hospital — not
--     OCIC; opens 2028, no operating data yet.
--
-- Coordinates below are 4-decimal approximations from each
-- hospital's published contact page. Verify against Google Maps
-- pins before launch.
--
-- Idempotent: `add column if not exists`, `on conflict (name)
-- do update` on every insert. Safe to re-run.
-- See docs/SECURITY.md for the RLS-off project posture.
-- ============================================================

-- Add Khmer-name column (013 didn't).
alter table public.hospitals
  add column if not exists name_kh text;

-- 1) Update Intercare with stronger verified data.
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude,
  telegram_handle, messenger_url, website, logo_url,
  is_ocic_affiliated
) values (
  'Intercare Hospital',
  'មន្ទីរពេទ្យ អុីនធ័រឃែរ',
  'Olympia Medical Hub, Bldg C5 Tower A, St 161, Sangkat Veal Vong, Khan 7 Makara, Phnom Penh',
  '+855 96 811 9119',
  array[
    'Emergency 24/7','General Practice','Maternity','Pediatrics',
    'Surgery','Physiotherapy','Aesthetics','Imaging','Laboratory',
    'Visa Health Check'
  ]::text[],
  11.5563, 104.9070, -- TODO: verify Google Maps pin
  'intercarehospital',
  'https://m.me/intercarehospital',
  'https://intercarehospital.com',
  'https://intercarehospital.com/wp-content/uploads/2026/01/ICH_H-2.png',
  true
)
on conflict (name) do update set
  name_kh = excluded.name_kh,
  address = excluded.address, phone = excluded.phone,
  specialties = excluded.specialties,
  latitude = excluded.latitude, longitude = excluded.longitude,
  telegram_handle = excluded.telegram_handle,
  messenger_url = excluded.messenger_url,
  website = excluded.website, logo_url = excluded.logo_url,
  is_ocic_affiliated = excluded.is_ocic_affiliated;

-- 2) Royal Phnom Penh Hospital (BDMS / Royal Group)
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Royal Phnom Penh Hospital', null,
  'No. 888, Russian Federation Blvd (110), Sangkat Toeuk Thla, Khan Sen Sok, Phnom Penh',
  '+855 23 991 000',
  array['Emergency 24/7','Cardiology','Oncology','Surgery','OB-GYN','IVF','Pediatrics','Internal Medicine']::text[],
  11.5660, 104.8870,
  'royalphnompenhhospitalofficial',
  'https://www.facebook.com/RoyalphnompenhhospitalOfficial/',
  'https://www.royalphnompenhhospital.com',
  false
) on conflict (name) do update set
  address=excluded.address, phone=excluded.phone, specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 3) Sunrise Japan Hospital
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Sunrise Japan Hospital', 'មន្ទីរពេទ្យជប៉ុនសាន់រ៉ាយស៍ភ្នំពេញ',
  '#177E, Kola Loum St, Phum 2, Sangkat Chroy Changvar, Khan Chroy Changvar, Phnom Penh',
  '+855 23 260 152',
  array['Neurosurgery','Stroke','Emergency','OB-GYN','Pediatrics','Cardiology','Gastroenterology','Health Screening']::text[],
  11.5950, 104.9410,
  'SunriseJapanHospital',
  'https://www.facebook.com/sunrise.jhpp/',
  'https://www.sunrise-hs.com.kh',
  false
) on conflict (name) do update set
  name_kh=excluded.name_kh, address=excluded.address, phone=excluded.phone,
  specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 4) Khema International Polyclinic (BKK1)
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Khema International Polyclinic', 'មន្ទីរពហុព្យាបាលអន្តរជាតិខេមា',
  'Building 28, Street 294, Sangkat Boeung Keng Kang 1, Khan Chamkar Mon, Phnom Penh',
  '+855 89 911 911',
  array['General Practice','Pediatrics','OB-GYN','Dermatology','Dental','Imaging','Laboratory']::text[],
  11.5470, 104.9230,
  'khemacares',
  'https://www.facebook.com/khemainternational/',
  'https://khemahospital.com',
  false
) on conflict (name) do update set
  name_kh=excluded.name_kh, address=excluded.address, phone=excluded.phone,
  specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 5) Calmette Hospital (public, MoH; Cambodia–France cooperation)
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Calmette Hospital', 'មន្ទីរពេទ្យកាល់ម៉ែត',
  'No. 3, Monivong Blvd, Sangkat Sras Chok, Khan Daun Penh, Phnom Penh',
  '+855 23 426 948',
  array['General Surgery','Internal Medicine','Cardiology','Oncology','Emergency','Trauma','Public Health']::text[],
  11.5810, 104.9220,
  null,
  'https://www.facebook.com/hospitalcalmette/',
  'https://www.calmette.gov.kh',
  false
) on conflict (name) do update set
  name_kh=excluded.name_kh, address=excluded.address, phone=excluded.phone,
  specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 6) Central Hospital
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Central Hospital', 'មន្ទីរពេទ្យ សង់ត្រាល់',
  '#82A Street 154, Sangkat Phsar Thmey 3, Khan Daun Penh, Phnom Penh',
  '+855 23 214 955',
  array['Cardiology','General Medicine','Surgery','Internal Medicine','Imaging','Laboratory']::text[],
  11.5720, 104.9210,
  null,
  'https://www.facebook.com/centralhospitalphnompenh/',
  'https://central-hospital.com',
  false
) on conflict (name) do update set
  name_kh=excluded.name_kh, address=excluded.address, phone=excluded.phone,
  specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 7) Hebron Medical Center (Korean-missionary, non-profit)
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Hebron Medical Center', null,
  '#102, Street 68K, Phum Prey Sala, Sangkat Kakab 2, Khan Por Senchey, Phnom Penh',
  '+855 15 336 119',
  array['General Practice','Pediatrics','Ophthalmology','Surgery','Dialysis','Charity Care']::text[],
  11.5450, 104.8550,
  null,
  'https://www.facebook.com/HebronMedicalCenterOfficial/',
  'https://www.hebronmc.org',
  false
) on conflict (name) do update set
  address=excluded.address, phone=excluded.phone, specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 8) Sen Sok International University Hospital
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Sen Sok International University Hospital', null,
  'Buildings 91-96, Street 1986, Sangkat Phnom Penh Thmei, Khan Sen Sok, Phnom Penh',
  '+855 17 575 593',
  array['Emergency 24/7','Cardiology','Oncology','OB-GYN','Pediatrics','Surgery','Internal Medicine']::text[],
  11.5870, 104.8810,
  null,
  'https://www.facebook.com/SenSokIUhospital/',
  'http://www.sensokiuh.com',
  false
) on conflict (name) do update set
  address=excluded.address, phone=excluded.phone, specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;

-- 9) Preah Kossamak Hospital (Cambodia–China Friendship; public)
insert into public.hospitals (
  name, name_kh, address, phone, specialties,
  latitude, longitude, telegram_handle, messenger_url, website, is_ocic_affiliated
) values (
  'Preah Kossamak Hospital', 'មន្ទីរពេទ្យមិត្តភាពកម្ពុជា-ចិន ព្រះកុសុមៈ',
  'No. 28C, Yothapol Khemarak Phoumin Blvd (271), Phnom Penh',
  '+855 23 882 947',
  array['General Medicine','Surgery','Emergency','Internal Medicine','Public Health']::text[],
  11.5380, 104.8950,
  null,
  'https://www.facebook.com/ccpkhospital/',
  null,
  false
) on conflict (name) do update set
  name_kh=excluded.name_kh, address=excluded.address, phone=excluded.phone,
  specialties=excluded.specialties,
  latitude=excluded.latitude, longitude=excluded.longitude,
  telegram_handle=excluded.telegram_handle, messenger_url=excluded.messenger_url,
  website=excluded.website, is_ocic_affiliated=excluded.is_ocic_affiliated;
