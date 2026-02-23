-- Production-safe schema migration for STRIVE habit tracker.
-- Safe to re-run: no DROP TABLE / DROP COLUMN / DROP DATA statements.

begin;

create extension if not exists pgcrypto;

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) <= 80),
  description text,
  start_date date not null,
  end_date date not null,
  target_per_week integer not null default 5 check (target_per_week between 1 and 7),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.habit_entries (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  completed boolean not null default true,
  created_at timestamptz not null default now(),
  unique (habit_id, user_id, entry_date)
);

create index if not exists habits_user_created_idx
  on public.habits(user_id, created_at desc);

create index if not exists habit_entries_user_date_idx
  on public.habit_entries(user_id, entry_date desc);

create index if not exists habit_entries_habit_date_idx
  on public.habit_entries(habit_id, entry_date desc);

alter table public.habits enable row level security;
alter table public.habit_entries enable row level security;

alter table public.habits force row level security;
alter table public.habit_entries force row level security;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'set_habits_updated_at'
      and tgrelid = 'public.habits'::regclass
  ) then
    create trigger set_habits_updated_at
    before update on public.habits
    for each row execute function public.set_updated_at();
  end if;
end $$;

-- Ensures habit_entries.user_id matches the owning habit user_id
-- and entry_date is inside the habit timeframe.
create or replace function public.validate_habit_entry()
returns trigger
language plpgsql
as $$
declare
  habit_owner uuid;
  habit_start date;
  habit_end date;
begin
  select user_id, start_date, end_date
  into habit_owner, habit_start, habit_end
  from public.habits
  where id = new.habit_id;

  if habit_owner is null then
    raise exception 'Habit not found for id %', new.habit_id;
  end if;

  if new.user_id <> habit_owner then
    raise exception 'Entry user_id must match habit owner';
  end if;

  if new.entry_date < habit_start or new.entry_date > habit_end then
    raise exception 'Entry date must be within habit timeframe';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'validate_habit_entry_trigger'
      and tgrelid = 'public.habit_entries'::regclass
  ) then
    create trigger validate_habit_entry_trigger
    before insert or update on public.habit_entries
    for each row execute function public.validate_habit_entry();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habits'
      and policyname = 'habits_select_own'
  ) then
    create policy habits_select_own
      on public.habits
      for select
      using (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habits'
      and policyname = 'habits_insert_own'
  ) then
    create policy habits_insert_own
      on public.habits
      for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habits'
      and policyname = 'habits_update_own'
  ) then
    create policy habits_update_own
      on public.habits
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habits'
      and policyname = 'habits_delete_own'
  ) then
    create policy habits_delete_own
      on public.habits
      for delete
      using (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habit_entries'
      and policyname = 'entries_select_own'
  ) then
    create policy entries_select_own
      on public.habit_entries
      for select
      using (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habit_entries'
      and policyname = 'entries_insert_own'
  ) then
    create policy entries_insert_own
      on public.habit_entries
      for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habit_entries'
      and policyname = 'entries_update_own'
  ) then
    create policy entries_update_own
      on public.habit_entries
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'habit_entries'
      and policyname = 'entries_delete_own'
  ) then
    create policy entries_delete_own
      on public.habit_entries
      for delete
      using (auth.uid() = user_id);
  end if;
end $$;

commit;
