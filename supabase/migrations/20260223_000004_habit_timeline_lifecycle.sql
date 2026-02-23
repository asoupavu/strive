begin;

alter table public.habits
  add column if not exists target_count integer not null default 5 check (target_count between 1 and 30);

alter table public.habits
  add column if not exists cadence_days integer not null default 7 check (cadence_days between 1 and 90);

alter table public.habits
  add column if not exists status text not null default 'active' check (status in ('active', 'paused', 'stopped'));

alter table public.habits
  add column if not exists stopped_at timestamptz;

alter table public.habits
  add column if not exists stop_reason text;

commit;
