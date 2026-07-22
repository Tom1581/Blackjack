-- Free-tier activity heartbeat.
-- This RPC performs a tiny database query and returns the server timestamp.
-- It is safe to call with the app's publishable key and stores no user data.

create or replace function public.keep_alive()
returns timestamptz
language sql
security invoker
set search_path = ''
as $$
  select now();
$$;

grant execute on function public.keep_alive() to anon, authenticated;
