-- Production-safe schema migration for STRIVE.
-- Safe to re-run. No table/data destructive operations.

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

alter table public.habits add column if not exists category text;
alter table public.habits add column if not exists tags text[] not null default '{}'::text[];
alter table public.habits add column if not exists visibility text not null default 'friends' check (visibility in ('friends', 'private'));
alter table public.habits add column if not exists is_pinned boolean not null default false;
alter table public.habits add column if not exists sort_order integer not null default 0;
alter table public.habits add column if not exists target_count integer not null default 5 check (target_count between 1 and 7);
alter table public.habits add column if not exists cadence_days integer not null default 7 check (cadence_days between 1 and 90);
alter table public.habits add column if not exists status text not null default 'active' check (status in ('active', 'paused', 'stopped'));
alter table public.habits add column if not exists stopped_at timestamptz;
alter table public.habits add column if not exists stop_reason text;
alter table public.habits alter column is_pinned set default true;

create table if not exists public.habit_entries (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  completed boolean not null default true,
  created_at timestamptz not null default now(),
  unique (habit_id, user_id, entry_date)
);

alter table public.habit_entries add column if not exists note text;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  handle text unique,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (handle is null or handle ~ '^[a-z0-9_]{3,30}$')
);

alter table public.profiles add column if not exists settings jsonb not null default '{}'::jsonb;

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id),
  unique (requester_id, addressee_id)
);

create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (blocker_id <> blocked_id),
  unique (blocker_id, blocked_id)
);

create index if not exists habits_user_created_idx on public.habits(user_id, created_at desc);
create index if not exists habits_user_sort_idx on public.habits(user_id, is_pinned desc, sort_order asc, created_at desc);
create index if not exists habits_visibility_user_idx on public.habits(user_id, visibility);

create index if not exists habit_entries_user_date_idx on public.habit_entries(user_id, entry_date desc);
create index if not exists habit_entries_habit_date_idx on public.habit_entries(habit_id, entry_date desc);

create index if not exists profiles_handle_idx on public.profiles(handle);
create index if not exists friendships_requester_status_idx on public.friendships(requester_id, status);
create index if not exists friendships_addressee_status_idx on public.friendships(addressee_id, status);
create index if not exists blocked_users_blocker_idx on public.blocked_users(blocker_id, created_at desc);
create index if not exists blocked_users_blocked_idx on public.blocked_users(blocked_id, created_at desc);

alter table public.habits enable row level security;
alter table public.habit_entries enable row level security;
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.blocked_users enable row level security;

alter table public.habits force row level security;
alter table public.habit_entries force row level security;
alter table public.profiles force row level security;
alter table public.friendships force row level security;
alter table public.blocked_users force row level security;

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
    select 1 from pg_trigger where tgname = 'set_habits_updated_at' and tgrelid = 'public.habits'::regclass
  ) then
    create trigger set_habits_updated_at
    before update on public.habits
    for each row execute function public.set_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'set_profiles_updated_at' and tgrelid = 'public.profiles'::regclass
  ) then
    create trigger set_profiles_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.validate_habit_entry()
returns trigger
language plpgsql
as $$
declare
  habit_owner uuid;
  habit_start date;
  habit_end date;
begin
  select user_id, start_date, end_date into habit_owner, habit_start, habit_end
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
    select 1 from pg_trigger where tgname = 'validate_habit_entry_trigger' and tgrelid = 'public.habit_entries'::regclass
  ) then
    create trigger validate_habit_entry_trigger
    before insert or update on public.habit_entries
    for each row execute function public.validate_habit_entry();
  end if;
end $$;

-- Habits policies

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habits' and policyname = 'habits_select_own'
  ) then
    create policy habits_select_own
      on public.habits
      for select
      using (auth.uid() = user_id);
  end if;
end $$;

alter policy habits_select_own
  on public.habits
  using (
    auth.uid() = user_id
    or (
      visibility = 'friends'
      and exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
            (f.requester_id = auth.uid() and f.addressee_id = habits.user_id)
            or (f.addressee_id = auth.uid() and f.requester_id = habits.user_id)
          )
      )
      and not exists (
        select 1
        from public.blocked_users b
        where (b.blocker_id = habits.user_id and b.blocked_id = auth.uid())
           or (b.blocker_id = auth.uid() and b.blocked_id = habits.user_id)
      )
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habits' and policyname = 'habits_insert_own'
  ) then
    create policy habits_insert_own
      on public.habits
      for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

alter policy habits_insert_own
  on public.habits
  with check (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habits' and policyname = 'habits_update_own'
  ) then
    create policy habits_update_own
      on public.habits
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

alter policy habits_update_own
  on public.habits
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habits' and policyname = 'habits_delete_own'
  ) then
    create policy habits_delete_own
      on public.habits
      for delete
      using (auth.uid() = user_id);
  end if;
end $$;

alter policy habits_delete_own
  on public.habits
  using (auth.uid() = user_id);

-- Habit entries policies

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habit_entries' and policyname = 'entries_select_own'
  ) then
    create policy entries_select_own
      on public.habit_entries
      for select
      using (auth.uid() = user_id);
  end if;
end $$;

alter policy entries_select_own
  on public.habit_entries
  using (
    auth.uid() = user_id
    or exists (
      select 1
      from public.habits h
      where h.id = habit_entries.habit_id
        and h.user_id = habit_entries.user_id
        and h.visibility = 'friends'
        and exists (
          select 1
          from public.friendships f
          where f.status = 'accepted'
            and (
              (f.requester_id = auth.uid() and f.addressee_id = habit_entries.user_id)
              or (f.addressee_id = auth.uid() and f.requester_id = habit_entries.user_id)
            )
        )
        and not exists (
          select 1
          from public.blocked_users b
          where (b.blocker_id = habit_entries.user_id and b.blocked_id = auth.uid())
             or (b.blocker_id = auth.uid() and b.blocked_id = habit_entries.user_id)
        )
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habit_entries' and policyname = 'entries_insert_own'
  ) then
    create policy entries_insert_own
      on public.habit_entries
      for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

alter policy entries_insert_own
  on public.habit_entries
  with check (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habit_entries' and policyname = 'entries_update_own'
  ) then
    create policy entries_update_own
      on public.habit_entries
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

alter policy entries_update_own
  on public.habit_entries
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habit_entries' and policyname = 'entries_delete_own'
  ) then
    create policy entries_delete_own
      on public.habit_entries
      for delete
      using (auth.uid() = user_id);
  end if;
end $$;

alter policy entries_delete_own
  on public.habit_entries
  using (auth.uid() = user_id);

create or replace function public.lookup_profile_by_handle(p_handle text)
returns table(user_id uuid, handle text)
language sql
security definer
set search_path = public
as $$
  select p.user_id, p.handle
  from public.profiles p
  where p.handle = lower(trim(p_handle))
  limit 1;
$$;

revoke all on function public.lookup_profile_by_handle(text) from public;
grant execute on function public.lookup_profile_by_handle(text) to authenticated;

-- Profiles policies

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_authenticated'
  ) then
    create policy profiles_select_authenticated
      on public.profiles
      for select
      using (auth.uid() is not null);
  end if;
end $$;

alter policy profiles_select_authenticated
  on public.profiles
  using (
    auth.uid() = user_id
    or (
      exists (
        select 1
        from public.friendships f
        where f.status in ('pending', 'accepted')
          and (
            (f.requester_id = auth.uid() and f.addressee_id = profiles.user_id)
            or (f.addressee_id = auth.uid() and f.requester_id = profiles.user_id)
          )
      )
      and not exists (
        select 1
        from public.blocked_users b
        where (b.blocker_id = profiles.user_id and b.blocked_id = auth.uid())
           or (b.blocker_id = auth.uid() and b.blocked_id = profiles.user_id)
      )
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_insert_own'
  ) then
    create policy profiles_insert_own
      on public.profiles
      for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

alter policy friendships_update_involved
  on public.friendships
  using (auth.uid() = addressee_id and status = 'pending')
  with check (
    auth.uid() = addressee_id
    and requester_id <> addressee_id
    and status in ('accepted', 'declined')
  );

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_update_own'
  ) then
    create policy profiles_update_own
      on public.profiles
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

-- Friendships policies

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_select_involved'
  ) then
    create policy friendships_select_involved
      on public.friendships
      for select
      using (auth.uid() = requester_id or auth.uid() = addressee_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_insert_requester'
  ) then
    create policy friendships_insert_requester
      on public.friendships
      for insert
      with check (auth.uid() = requester_id and status = 'pending');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_update_involved'
  ) then
    create policy friendships_update_involved
      on public.friendships
      for update
      using (auth.uid() = requester_id or auth.uid() = addressee_id)
      with check (auth.uid() = requester_id or auth.uid() = addressee_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_delete_involved'
  ) then
    create policy friendships_delete_involved
      on public.friendships
      for delete
      using (auth.uid() = requester_id or auth.uid() = addressee_id);
  end if;
end $$;

-- Blocked users policies

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'blocked_users' and policyname = 'blocked_users_select_involved'
  ) then
    create policy blocked_users_select_involved
      on public.blocked_users
      for select
      using (auth.uid() = blocker_id or auth.uid() = blocked_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'blocked_users' and policyname = 'blocked_users_insert_blocker'
  ) then
    create policy blocked_users_insert_blocker
      on public.blocked_users
      for insert
      with check (auth.uid() = blocker_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'blocked_users' and policyname = 'blocked_users_delete_blocker'
  ) then
    create policy blocked_users_delete_blocker
      on public.blocked_users
      for delete
      using (auth.uid() = blocker_id);
  end if;
end $$;

commit;
