-- Run this in Supabase SQL editor.
-- It creates per-user habit tracking tables with row-level security.

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

create index if not exists habits_user_created_idx on public.habits(user_id, created_at desc);
create index if not exists habit_entries_user_date_idx on public.habit_entries(user_id, entry_date desc);

alter table public.habits enable row level security;
alter table public.habit_entries enable row level security;

-- habits policies
drop policy if exists "habits_select_own" on public.habits;
create policy "habits_select_own"
  on public.habits for select
  using (auth.uid() = user_id);

drop policy if exists "habits_insert_own" on public.habits;
create policy "habits_insert_own"
  on public.habits for insert
  with check (auth.uid() = user_id);

drop policy if exists "habits_update_own" on public.habits;
create policy "habits_update_own"
  on public.habits for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "habits_delete_own" on public.habits;
create policy "habits_delete_own"
  on public.habits for delete
  using (auth.uid() = user_id);

-- habit entries policies
drop policy if exists "entries_select_own" on public.habit_entries;
create policy "entries_select_own"
  on public.habit_entries for select
  using (auth.uid() = user_id);

drop policy if exists "entries_insert_own" on public.habit_entries;
create policy "entries_insert_own"
  on public.habit_entries for insert
  with check (auth.uid() = user_id);

drop policy if exists "entries_update_own" on public.habit_entries;
create policy "entries_update_own"
  on public.habit_entries for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "entries_delete_own" on public.habit_entries;
create policy "entries_delete_own"
  on public.habit_entries for delete
  using (auth.uid() = user_id);

-- Keep habits.updated_at fresh
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_habits_updated_at on public.habits;
create trigger set_habits_updated_at
before update on public.habits
for each row execute function public.set_updated_at();
