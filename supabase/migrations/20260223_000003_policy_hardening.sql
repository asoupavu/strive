begin;

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

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_authenticated'
  ) then
    execute $stmt$
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
        )
    $stmt$;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_update_involved'
  ) then
    execute $stmt$
      alter policy friendships_update_involved
        on public.friendships
        using (auth.uid() = addressee_id and status = 'pending')
        with check (
          auth.uid() = addressee_id
          and requester_id <> addressee_id
          and status in ('accepted', 'declined')
        )
    $stmt$;
  end if;
end $$;

commit;
