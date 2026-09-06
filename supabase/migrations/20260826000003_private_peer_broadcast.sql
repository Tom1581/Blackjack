-- The managed database Broadcast publication in this project stores messages
-- but does not deliver its WAL stream. Keep room admission in Postgres and
-- allow only admitted authenticated members to exchange private peer traffic.

drop policy if exists "Hi-Lo online publish presence" on realtime.messages;
create policy "Hi-Lo online publish private room traffic"
  on realtime.messages for insert to authenticated
  with check (
    realtime.messages.extension in ('presence', 'broadcast')
    and public.can_access_online_topic((select realtime.topic()))
  );
