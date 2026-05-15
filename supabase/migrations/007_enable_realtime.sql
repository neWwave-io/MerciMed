-- Enable Supabase Realtime broadcasts on tables the client subscribes to via
-- `.stream()`. New tables created in later migrations are not automatically
-- added to the `supabase_realtime` publication, so insert/update/delete events
-- only reach clients after they're added here. The DO-block makes this safe to
-- re-run.

do $$
declare
  t text;
  tables text[] := array[
    'folders',
    'files',
    'profiles',
    'relationships',
    'chat_messages'
  ];
begin
  foreach t in array tables loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename  = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Ensure full row payloads on UPDATE/DELETE so the client receives the prior
-- row (default sends only the primary key, which breaks downstream filtering).
alter table public.folders       replica identity full;
alter table public.files         replica identity full;
alter table public.profiles      replica identity full;
alter table public.relationships replica identity full;
alter table public.chat_messages replica identity full;
