begin;

create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (blocker_id <> blocked_id),
  unique (blocker_id, blocked_id)
);

create index if not exists blocked_users_blocker_idx on public.blocked_users(blocker_id, created_at desc);
create index if not exists blocked_users_blocked_idx on public.blocked_users(blocked_id, created_at desc);

alter table public.blocked_users enable row level security;
alter table public.blocked_users force row level security;

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

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habits' and policyname = 'habits_select_own'
  ) then
    execute $stmt$
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
        )
    $stmt$;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'habit_entries' and policyname = 'entries_select_own'
  ) then
    execute $stmt$
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
        )
    $stmt$;
  end if;
end $$;

commit;
