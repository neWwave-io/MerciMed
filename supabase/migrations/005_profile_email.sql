-- ============================================================
-- Add email column to profiles + sync from auth.users on signup
-- ============================================================

alter table public.profiles
  add column if not exists email text;

create unique index if not exists profiles_email_lower_unique
  on public.profiles (lower(email)) where email is not null;

-- Update the auto-create trigger to capture email on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

-- Backfill existing profiles from auth.users
update public.profiles p
   set email = u.email
  from auth.users u
 where p.id = u.id
   and p.email is null;
