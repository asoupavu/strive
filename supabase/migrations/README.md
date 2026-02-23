# Supabase Migrations

This folder contains versioned SQL migrations for STRIVE.

## Order
Apply files in lexical order:
1. `20260223_000001_profiles_settings.sql`
2. `20260223_000002_blocked_users.sql`

## Notes
- Migrations are idempotent and safe to re-run.
- Keep `supabase_schema.sql` as a full snapshot, and add incremental changes here.
