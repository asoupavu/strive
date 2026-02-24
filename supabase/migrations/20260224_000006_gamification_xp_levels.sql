begin;

alter table public.profiles
  add column if not exists xp_total integer not null default 0;

alter table public.profiles
  add column if not exists level integer not null default 1;

alter table public.profiles
  drop constraint if exists profiles_xp_total_nonnegative;

alter table public.profiles
  add constraint profiles_xp_total_nonnegative
  check (xp_total >= 0);

alter table public.profiles
  drop constraint if exists profiles_level_min;

alter table public.profiles
  add constraint profiles_level_min
  check (level >= 1);

create or replace function public.level_from_xp(total_xp integer)
returns integer
language sql
immutable
as $$
  select greatest(1, (greatest(coalesce(total_xp, 0), 0) / 100) + 1);
$$;

with completed as (
  select user_id, (count(*)::integer * 10) as xp_total
  from public.habit_entries
  where completed = true
  group by user_id
),
normalized as (
  select p.user_id, coalesce(c.xp_total, 0) as xp_total
  from public.profiles p
  left join completed c on c.user_id = p.user_id
)
update public.profiles p
set xp_total = n.xp_total,
    level = public.level_from_xp(n.xp_total)
from normalized n
where p.user_id = n.user_id;

create or replace function public.apply_profile_xp_delta()
returns trigger
language plpgsql
as $$
declare
  xp_delta integer := 0;
begin
  if tg_op = 'INSERT' then
    xp_delta := case when new.completed then 10 else 0 end;
    if xp_delta <> 0 then
      update public.profiles p
      set xp_total = greatest(0, p.xp_total + xp_delta),
          level = public.level_from_xp(greatest(0, p.xp_total + xp_delta))
      where p.user_id = new.user_id;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    xp_delta := case when old.completed then -10 else 0 end;
    if xp_delta <> 0 then
      update public.profiles p
      set xp_total = greatest(0, p.xp_total + xp_delta),
          level = public.level_from_xp(greatest(0, p.xp_total + xp_delta))
      where p.user_id = old.user_id;
    end if;
    return old;
  end if;

  -- Update path
  if old.user_id is distinct from new.user_id then
    if old.completed then
      update public.profiles p
      set xp_total = greatest(0, p.xp_total - 10),
          level = public.level_from_xp(greatest(0, p.xp_total - 10))
      where p.user_id = old.user_id;
    end if;

    if new.completed then
      update public.profiles p
      set xp_total = greatest(0, p.xp_total + 10),
          level = public.level_from_xp(greatest(0, p.xp_total + 10))
      where p.user_id = new.user_id;
    end if;

    return new;
  end if;

  if old.completed is not distinct from new.completed then
    return new;
  end if;

  xp_delta := case when new.completed then 10 else -10 end;

  update public.profiles p
  set xp_total = greatest(0, p.xp_total + xp_delta),
      level = public.level_from_xp(greatest(0, p.xp_total + xp_delta))
  where p.user_id = new.user_id;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'apply_profile_xp_on_entry_change'
      and tgrelid = 'public.habit_entries'::regclass
  ) then
    create trigger apply_profile_xp_on_entry_change
    after insert or update or delete on public.habit_entries
    for each row execute function public.apply_profile_xp_delta();
  end if;
end $$;

commit;
