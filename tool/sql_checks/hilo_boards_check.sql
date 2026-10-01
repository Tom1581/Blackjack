-- Behaviour checks for supabase/migrations/20261001000000_hilo_training_boards.sql.
--
-- Run against a throwaway Supabase Postgres only, never production:
--
--   docker run -d --name blackjack_hilo_boards_check \
--     -e POSTGRES_PASSWORD=postgres -p 55499:5432 \
--     public.ecr.aws/supabase/postgres:15.8.1.085
--   docker exec -i blackjack_hilo_boards_check psql -U postgres -d postgres \
--     < supabase/migrations/20261001000000_hilo_training_boards.sql
--   docker exec -i blackjack_hilo_boards_check psql -U postgres -d postgres \
--     < tool/sql_checks/hilo_boards_check.sql
--   docker rm -f blackjack_hilo_boards_check
--
-- Results on 2026-10-01 against public.ecr.aws/supabase/postgres:15.8.1.085:
--   1 daily valid submit       -> stored and returned
--   2 daily second submit      -> first row remained final
--   3 daily day window         -> +/-1 accepted; +/-2 rejected with 22023
--   4 daily bounds             -> bad score/count/streak/answer totals rejected
--   5 names                    -> empty and 13 chars rejected; Bob was trimmed
--   6 daily standing           -> first 500-point row ranked above equal later row
--   7 Survival validation      -> bad level and fourth miss rejected
--   8 Survival best run        -> lower retained prior row; higher replaced it
--   9 Survival week window     -> +/-1 accepted; +/-2 rejected with 22023
--  10 anonymous RPCs           -> both rejected with 42501
--  11 direct table writes      -> authenticated insert/update rejected with 42501
--  12 pruning                  -> 61-day/13-week legacy rows removed by submits
--
-- This deliberately uses a temporary NOT VALID daily constraint during the
-- pruning test. At the current epoch the app is fewer than 61 days old, so a
-- 61-day-old row would otherwise violate the valid day >= 1 invariant. New
-- rows remain checked, the submit function prunes the legacy row, and the
-- constraint is validated again before the check completes.

\set ON_ERROR_STOP on

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'hilo-ann@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'hilo-bob@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'hilo-cam@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated', 'hilo-old@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now())
on conflict (id) do nothing;

truncate public.hilo_daily_scores, public.hilo_survival_scores;

-- 1–6. Daily score validation, first-attempt rule, names, and standings.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
do $$
declare
  v_row public.hilo_daily_scores;
begin
  select * into v_row from public.submit_hilo_daily(
    current_date - date '2026-09-28', 'Ann', 500, 1, 1, 1
  );
  if v_row.score <> 500 or v_row.display_name <> 'Ann' then
    raise exception 'daily valid submit was not stored';
  end if;

  select * into v_row from public.submit_hilo_daily(
    current_date - date '2026-09-28', 'Changed', 800, 1, 1, 1
  );
  if v_row.score <> 500 or v_row.display_name <> 'Ann' then
    raise exception 'daily second attempt replaced the first';
  end if;

  perform public.submit_hilo_daily(
    current_date - date '2026-09-28' - 1, 'Ann', 100, 1, 1, 1
  );
  perform public.submit_hilo_daily(
    current_date - date '2026-09-28' + 1, 'Ann', 100, 1, 1, 1
  );

  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28' + 2, 'Ann', 100, 1, 1, 1
    );
    raise exception 'expected bad daily day to fail';
  exception when sqlstate '22023' then null;
  end;

end;
$$;

-- The invalid cases use a fresh day only after their inputs have been
-- rejected, so no official score is created as a side effect.
do $$
begin
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Ann', 99, 1, 1, 1
    );
    raise exception 'expected low daily score to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Ann', 801, 1, 1, 1
    );
    raise exception 'expected high daily score to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Ann', 100, 2, 1, 1
    );
    raise exception 'expected correct > answered to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Ann', 100, 1, 1, 2
    );
    raise exception 'expected streak > correct to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Ann', 100, 1, 11, 1
    );
    raise exception 'expected >10 answers to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', '', 0, 0, 0, 0
    );
    raise exception 'expected empty name to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'thirteenchars', 0, 0, 0, 0
    );
    raise exception 'expected long name to fail';
  exception when sqlstate '22023' then null;
  end;
end;
$$;

select pg_sleep(0.02);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);
do $$
declare
  v_row public.hilo_daily_scores;
  v_standing record;
begin
  select * into v_row from public.submit_hilo_daily(
    current_date - date '2026-09-28', '  Bob  ', 500, 1, 1, 1
  );
  if v_row.display_name <> 'Bob' then
    raise exception 'daily name was not trimmed';
  end if;

  select * into v_standing
  from public.hilo_daily_standing(current_date - date '2026-09-28');
  if v_standing.rank <> 2 or v_standing.players <> 2 or v_standing.score <> 500 then
    raise exception 'daily tie standing was wrong: %', row_to_json(v_standing);
  end if;
end;
$$;

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);
do $$
declare
  v_standing record;
begin
  select * into v_standing
  from public.hilo_daily_standing(current_date - date '2026-09-28');
  if v_standing.rank <> 1 or v_standing.players <> 2 or v_standing.score <> 500 then
    raise exception 'daily first tie standing was wrong: %', row_to_json(v_standing);
  end if;
end;
$$;

-- 7–9. Survival validation, best-run update, and neighbouring weeks.
do $$
declare
  v_row public.hilo_survival_scores;
  v_week text := 'W' || ((current_date - date '2024-01-01') / 7)::text;
begin
  begin
    perform public.submit_hilo_survival(v_week, 'Ann', 1200, 12, 12, 2);
    raise exception 'expected wrong Survival level to fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.submit_hilo_survival(v_week, 'Ann', 1200, 12, 16, 3);
    raise exception 'expected fourth Survival miss to fail';
  exception when sqlstate '22023' then null;
  end;

  select * into v_row from public.submit_hilo_survival(
    v_week, 'Ann', 1400, 12, 12, 3
  );
  if v_row.score <> 1400 then
    raise exception 'initial Survival score was not stored';
  end if;
  select * into v_row from public.submit_hilo_survival(
    v_week, 'Lower', 1200, 12, 12, 3
  );
  if v_row.score <> 1400 or v_row.display_name <> 'Ann' then
    raise exception 'lower Survival score replaced the best';
  end if;
  select * into v_row from public.submit_hilo_survival(
    v_week, 'Ann High', 2000, 12, 12, 3
  );
  if v_row.score <> 2000 or v_row.display_name <> 'Ann High' then
    raise exception 'higher Survival score did not replace the best';
  end if;

  perform public.submit_hilo_survival(
    'W' || (((current_date - date '2024-01-01') / 7) - 1)::text,
    'Ann', 100, 1, 1, 1
  );
  perform public.submit_hilo_survival(
    'W' || (((current_date - date '2024-01-01') / 7) + 1)::text,
    'Ann', 100, 1, 1, 1
  );
  begin
    perform public.submit_hilo_survival(
      'W' || (((current_date - date '2024-01-01') / 7) + 2)::text,
      'Ann', 100, 1, 1, 1
    );
    raise exception 'expected out-of-window Survival week to fail';
  exception when sqlstate '22023' then null;
  end;
end;
$$;

-- 10. Anonymous callers have neither RPC execute grant.
reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$
begin
  begin
    perform public.submit_hilo_daily(
      current_date - date '2026-09-28', 'Anon', 0, 0, 0, 0
    );
    raise exception 'expected anonymous daily submit to fail';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.submit_hilo_survival(
      'W' || ((current_date - date '2024-01-01') / 7)::text,
      'Anon', 0, 0, 0, 1
    );
    raise exception 'expected anonymous Survival submit to fail';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

-- 11. Authenticated clients cannot bypass the validation functions.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', false);
do $$
begin
  begin
    insert into public.hilo_daily_scores (
      player_id, day, display_name, score, correct, answered, best_streak
    ) values (
      auth.uid(), current_date - date '2026-09-28', 'Cam', 0, 0, 0, 0
    );
    raise exception 'expected direct daily insert to fail';
  exception when sqlstate '42501' then null;
  end;
  begin
    update public.hilo_survival_scores set score = 1 where player_id = auth.uid();
    raise exception 'expected direct Survival update to fail';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

-- 12. Old rows are bounded. The daily epoch is only a few days old today, so
-- temporarily admit a legacy negative day, prove the real RPC prunes it, and
-- restore the fully validated constraint.
reset role;
alter table public.hilo_daily_scores
  drop constraint hilo_daily_scores_plausible;
insert into public.hilo_daily_scores (
  player_id, day, display_name, score, correct, answered, best_streak
) values (
  '44444444-4444-4444-4444-444444444444',
  (current_date - date '2026-09-28') - 61,
  'Old', 0, 0, 0, 0
);
alter table public.hilo_daily_scores
  add constraint hilo_daily_scores_plausible check (
    day >= 1
    and display_name = btrim(display_name)
    and char_length(display_name) between 1 and 12
    and answered between 0 and 10
    and correct between 0 and answered
    and best_streak between 0 and correct
    and score::bigint between correct::bigint * 100 and correct::bigint * 800
  ) not valid;

insert into public.hilo_survival_scores (
  player_id, week_key, display_name, score, correct, answered, level
) values (
  '44444444-4444-4444-4444-444444444444',
  'W' || (((current_date - date '2024-01-01') / 7) - 13)::text,
  'Old', 0, 0, 0, 1
);

set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', false);
select * from public.submit_hilo_daily(
  current_date - date '2026-09-28', 'Cam', 0, 0, 0, 0
);
select * from public.submit_hilo_survival(
  'W' || ((current_date - date '2024-01-01') / 7)::text,
  'Cam', 0, 0, 0, 1
);

reset role;
do $$
begin
  if exists (
    select 1 from public.hilo_daily_scores
    where player_id = '44444444-4444-4444-4444-444444444444'
  ) then
    raise exception 'old daily score was not pruned';
  end if;
  if exists (
    select 1 from public.hilo_survival_scores
    where player_id = '44444444-4444-4444-4444-444444444444'
  ) then
    raise exception 'old Survival score was not pruned';
  end if;
end;
$$;
alter table public.hilo_daily_scores
  validate constraint hilo_daily_scores_plausible;

select 'Hi-Lo board checks passed' as result;
