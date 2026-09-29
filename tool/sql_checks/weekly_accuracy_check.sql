-- Behaviour checks for supabase/migrations/20260929000000_weekly_accuracy.sql.
--
-- Run against a throwaway Supabase Postgres (never production), after the
-- 20260825 rankings migration, the rankings part of 20260826000000, and the
-- accuracy migration, with two rows in auth.users:
--   11111111-1111-1111-1111-111111111111 and 22222222-2222-2222-2222-222222222222
--
--   docker run -d --name bj_check -e POSTGRES_PASSWORD=postgres \
--     -p 55499:5432 public.ecr.aws/supabase/postgres:15.8.1.085
--   psql ... < this file
--
-- Results on 2026-09-29 (all as intended):
--   1 v1 after migration      -> works, decisions stay 0
--   2 v2                      -> decisions 30/27, accuracy_bp 9000
--   3 correct > decisions     -> "Decision counts are outside the accepted range"
--   4 decisions backwards     -> "Decision counts cannot move backwards"
--   5 > 40 per hand           -> "Decision count is not plausible for the hands played"
--   6 wrong week (via v1)     -> "Scores may only be submitted for the current week"
--   7 hands backwards (v1)    -> "Hands played cannot move backwards"
--   8 anon                    -> permission denied for both score functions
--   9 ordering                -> Bob 9500 above Ann 9000
--  10 direct update/insert    -> permission denied for table
--  11 write accuracy_bp       -> "can only be updated to DEFAULT"

\set ON_ERROR_STOP 0
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', false);
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
\set wk '''W'' || ((current_date - date ''2024-01-01'') / 7)::text'
-- 1. old client after the migration still works, decisions untouched
select 'v1 after' as t, profit, hands_played, decisions, correct_decisions, accuracy_bp from public.submit_weekly_ranking('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 150, 6);
-- 2. v2 writes decisions and the generated accuracy
select 'v2 ok' as t, profit, hands_played, decisions, correct_decisions, accuracy_bp from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 8, 30, 27);
-- 3. correct > decisions refused
select 'bad correct' as t, * from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 8, 30, 31);
-- 4. decisions backwards refused
select 'backwards' as t, * from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 9, 20, 18);
-- 5. implausible decisions refused (8 hands * 40 = 320)
select 'too many' as t, * from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 8, 321, 300);
-- 6. v1 rules still enforced through v2: wrong week
select 'wrong week' as t, * from public.submit_weekly_ranking_v2('W1', 'Ann', 200, 9, 31, 28);
-- 7. v1 rules through v2: hands backwards (decisions ok)
select 'hands back' as t, * from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 7, 31, 28);
-- 8. anon cannot call v2
reset role;
set role anon;
select set_config('request.jwt.claim.sub','', false);
select 'anon v1' as t, * from public.submit_weekly_ranking('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 9);
select 'anon' as t, * from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Ann', 200, 9, 31, 28);
reset role;
-- 9. second player, and the accuracy ordering / filtering
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222', false);
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
select 'bob' as t, decisions, correct_decisions, accuracy_bp from public.submit_weekly_ranking_v2('W' || ((current_date - date '2024-01-01') / 7)::text, 'Bob', -50, 20, 60, 57);
select 'board' as t, display_name, decisions, correct_decisions, accuracy_bp from public.weekly_rankings order by accuracy_bp desc, decisions desc;
-- 10. direct writes still revoked
update public.weekly_rankings set correct_decisions = 60 where display_name = 'Bob';
insert into public.weekly_rankings (player_id, week_key, display_name, decisions, correct_decisions) values ('22222222-2222-2222-2222-222222222222','W1','x',1,1);
-- 11. the generated column cannot be written
reset role;
update public.weekly_rankings set accuracy_bp = 1;
select 'final' as t, display_name, profit, hands_played, decisions, correct_decisions, accuracy_bp from public.weekly_rankings order by display_name;
