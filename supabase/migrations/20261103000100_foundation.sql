-- Foundation: extensions, the unexposed private schema, and the shared updated_at trigger function.

create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_cron;

create schema if not exists private;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
