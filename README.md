# STRIVE

Production-ready static frontend for STRIVE, built with Vite and deployed on Vercel.

## Local setup

1. Install dependencies:
   ```bash
   npm install
   ```
2. Create a local env file:
   ```bash
   cp .env.example .env
   ```
3. Set values in `.env`:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
4. Run local dev server:
   ```bash
   npm run dev
   ```

## Build

```bash
npm run build
```

Build output is generated in `dist/`.

## Vercel deployment

`vercel.json` is configured to:
- build with `npm run build`
- publish `dist/`
- use clean URLs
- set baseline security headers (CSP, HSTS, X-Frame-Options, etc.)

Set these Vercel environment variables:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

## Supabase backend

Apply migrations in `supabase/migrations/` in lexical order, as described in:
- `supabase/migrations/README.md`
