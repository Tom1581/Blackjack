-- Production follow-up for projects that already applied
-- 20260826000000_secure_online_and_rankings.sql.

create or replace function public.prune_stale_online_rooms()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.online_rooms
  where created_at < now() - interval '1 day';
  return new;
end;
$$;

drop trigger if exists online_rooms_prune_stale on public.online_rooms;
create trigger online_rooms_prune_stale
  before insert on public.online_rooms
  for each statement execute function public.prune_stale_online_rooms();
