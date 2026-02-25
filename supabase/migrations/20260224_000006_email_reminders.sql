begin;

create table if not exists public.reminder_email_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  sent_at timestamptz not null default now(),
  unique (user_id, local_date)
);

create index if not exists reminder_email_logs_user_date_idx
  on public.reminder_email_logs(user_id, local_date desc);

create or replace function public.get_due_reminder_recipients(p_now timestamptz default now())
returns table (
  user_id uuid,
  email text,
  handle text,
  local_date date
)
language sql
security definer
set search_path = public, auth
as $$
  with prof as (
    select
      p.user_id,
      p.handle,
      coalesce(tzn.name, 'UTC') as tz_name
    from public.profiles p
    left join pg_timezone_names tzn
      on tzn.name = coalesce(nullif(p.settings->>'reminderTimezone', ''), 'UTC')
    where coalesce((p.settings->>'emailRemindersEnabled')::boolean, false) = true
  )
  select
    prof.user_id,
    u.email,
    prof.handle,
    (p_now at time zone prof.tz_name)::date as local_date
  from prof
  join auth.users u on u.id = prof.user_id
  where u.email is not null
    and u.email_confirmed_at is not null
    and (p_now at time zone prof.tz_name)::time >= time '07:00'
    and (p_now at time zone prof.tz_name)::time < time '08:00'
    and not exists (
      select 1
      from public.reminder_email_logs l
      where l.user_id = prof.user_id
        and l.local_date = (p_now at time zone prof.tz_name)::date
    );
$$;

revoke all on function public.get_due_reminder_recipients(timestamptz) from public;
grant execute on function public.get_due_reminder_recipients(timestamptz) to service_role;

commit;
