-- Profile avatars: add column + public storage bucket.

alter table public.profiles
  add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;
