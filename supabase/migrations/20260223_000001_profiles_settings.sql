begin;

alter table public.profiles
  add column if not exists settings jsonb not null default '{}'::jsonb;

commit;
