begin;

update public.habits
set target_count = 7
where target_count > 7;

alter table public.habits
  drop constraint if exists habits_target_count_check;

alter table public.habits
  add constraint habits_target_count_check
  check (target_count between 1 and 7);

commit;
