# WeVois — Daily Activity Tracker

Internal team tracker: custom pipelines, daily activity log, and a
CEO → VP → Manager → Team Member hierarchy with admin-managed job roles.

## Before this site will work

1. **Run the database schema.** `TRACKER-SETUP.sql` (kept outside this folder,
   in `1-SQL-RUN-IN-SUPABASE`) must be run once in the Supabase SQL Editor.
2. **Fill in `supabase-config.js`.** Paste your Supabase Project URL and the
   **anon public** key. Never the `service_role` key.
3. In Supabase → Authentication → Providers → Email: **Confirm email OFF**,
   and leave **sign-ups ON** (safe — a signup with no invite gets no profile
   and can read nothing).

Until step 2 is done the site loads but shows "Not configured yet".

## Files here

| File | What it is |
|---|---|
| `index.html` | the whole app — one file |
| `supabase-config.js` | your project URL + anon key |
| `manifest.json` | lets staff install it like an app on their phone |
| `sw.js` | offline shell; network-first so redeploys land immediately |

All four must sit together in the same folder. `index.html` must be at the
**root** of what the host serves, or the site will 404.

## First run

The first account created becomes the **Admin** — the person who creates job
roles and everyone else's accounts. That should be your office/HR admin, not
the CEO. After that, accounts are created inside the app.
