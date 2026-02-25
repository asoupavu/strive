# send-daily-reminders

Sends 7:00 AM local-time daily habit reminder emails for users who enabled the setting.

## Required secrets

Set these in Supabase Functions secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `REMINDER_FROM_EMAIL` (verified sender in Resend, e.g. `Strive <noreply@yourdomain.com>`)
- `SITE_URL` (your app URL, e.g. `https://strive.vercel.app`)

## Deploy

```bash
supabase functions deploy send-daily-reminders --no-verify-jwt
```

## Schedule

Create a scheduled invocation every hour (cron):

```cron
0 * * * *
```

The function itself filters recipients to only send between 07:00-07:59 in each user's saved timezone, and logs each local date to prevent duplicates.
