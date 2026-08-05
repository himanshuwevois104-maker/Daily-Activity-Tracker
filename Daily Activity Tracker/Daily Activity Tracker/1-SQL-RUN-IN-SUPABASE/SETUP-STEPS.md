# Going live — WeVois Daily Activity Tracker

Four steps, about 20 minutes. Do them in order.

---

## 1. Create the Supabase project

Go to supabase.com, **New project**. Give it a name like `wevois-tracker`,
pick the region closest to you (Mumbai / `ap-south-1`), and set a database
password. This is a **separate project from your billing system** — nothing
here can touch `fhlvjeenvswwfhpxkgkm`.

Wait for it to finish provisioning (a minute or two).

## 2. Run the schema

Open **SQL Editor → New query**. Open `TRACKER-SETUP.sql`, **select the whole
file** (Ctrl+A), paste it in, and press Run.

> Select the *whole* file. The Supabase SQL editor runs only the highlighted
> text when there is a selection — a partial selection is what caused the
> `syntax error at or near "====="` you hit on the billing project.

When it finishes you should see one row at the bottom:

| departments | job_roles | log_categories | profiles | pipelines | rls_on_everywhere |
|---|---|---|---|---|---|
| 12 | 23 | 6 | 0 | 0 | true |

If any number differs, stop and send me what you see. `rls_on_everywhere`
must be **true** — that is the switch that keeps your data private.

## 3. Two auth settings

**Authentication → Providers → Email:**

- **Confirm email → OFF.** Otherwise a new colleague cannot sign in until
  they click a link in an email, and account creation from inside the app
  will half-fail.
- **Allow new users to sign up → leave ON.** This is different from the
  advice for the billing system, and it is deliberate. Read the next
  paragraph before changing it.

**Why leaving sign-up on is safe here.** Signing up only creates a *login*.
It does not create a *profile*, and without a profile the account sees
literally nothing — no people, no tasks, no logs, not even the list of job
roles. A profile is only created when your Admin has already entered that
person's email in the app. I verified this against a real PostgreSQL 16
database: an uninvited account returns 0 rows from every single table.

If you would rather turn sign-ups off anyway, you can — but then the app
cannot create logins for you. You would add each person in **Authentication
→ Users → Add user** in the Supabase dashboard yourself, and the tracker
would still slot them into the right job role automatically.

## 4. Point the app at the project and deploy

Open **Project Settings → API** and copy two values into
`supabase-config.js`:

```js
window.TRACKER_CONFIG = {
  url:     "https://xxxxxxxxxxxx.supabase.co",   // Project URL
  anonKey: "eyJhbGci..."                          // anon public
};
```

Only ever the **anon public** key. Never `service_role` — that one bypasses
all the security in step 2.

Then deploy the four files (`index.html`, `supabase-config.js`,
`manifest.json`, `sw.js`) as their own Vercel project:

- **Vercel → Add New → Project → Deploy** (or drag the folder onto
  vercel.com/new). No build command, no framework — it is a static site.
- If you upload it into a GitHub repo first, set **Root Directory** to
  whichever folder holds `index.html`.

---

## First run

Open the deployed URL. Because the database has no accounts yet, you get a
one-time **"Create the first account"** screen.

**The account you create here becomes the Admin.** Per your decision, that
should be your separate admin person — the office/HR admin — not you. Either
have them do this step, or create it with their email and hand them the
password.

After that, the Admin signs in and:

1. **Admin → Accounts → New account** for each person. Pick their job role
   (the level and department fill in automatically), choose who they report
   to, and the app shows you a temporary password to pass on. They can change
   it themselves from the account menu at the bottom-left.
2. Build the org from the top down — create the CEO first, then VPs, then
   managers, then everyone else, so "Reports to" always has someone to point at.
3. **Admin → Job roles** if you need a role that isn't in the 23 seeded ones.

Then managers and above create their pipelines under **Pipelines → New
pipeline**, and everyone starts logging their day.

## What each person sees

| | CEO | VP | Manager | Team member | Admin |
|---|---|---|---|---|---|
| Own tasks & daily log | yes | yes | yes | yes | yes |
| Their team's work | everyone | own branch | own team | no | no |
| Create pipelines | yes | yes | yes | no | no |
| Create job roles / accounts | **no** | **no** | no | no | **yes** |
| Request a job role / account | yes | yes | no | no | n/a |
| Decide requests | no | no | no | no | yes |

Two deliberate choices worth remembering:

- **The Admin is not a supervisor.** Being Admin lets you manage accounts and
  job roles; it does not show you anyone's tasks or daily log. Enforced in the
  database, not just the screen.
- **Nobody can edit someone else's daily log entry — not even the CEO.** A
  manager can move a report's task, but the log is that person's own account
  of their day. Also enforced in the database.

## Things to know

- **A role can grant company-wide pipeline access.** In **Admin → Job roles**,
  ticking a pipeline on (say) Accounts Executive lets everyone in that role see
  that pipeline across every team, not just their own. That is how Accounts,
  Legal, Tender and Billing people work across the org.
- **Deactivate, don't delete.** Deactivating a leaver keeps every task and log
  entry they ever wrote. You cannot deactivate someone who still has people
  reporting to them — move their team first.
- **Changes appear live.** If two people have the app open, one moving a card
  shows up for the other within a second.
- **Password resets.** Right now the Admin sets a new one by... actually, they
  can't — Supabase does not let one user change another's password from the
  browser. Use **Authentication → Users → ⋯ → Send password recovery** in the
  Supabase dashboard, or tell me and I'll add a "forgot password" link to the
  sign-in screen.

## If something goes wrong

- **"Not configured yet" screen** — `supabase-config.js` still has the
  placeholder values, or wasn't deployed alongside `index.html`.
- **"Could not load your data"** — the schema didn't run fully. Re-run
  `TRACKER-SETUP.sql`; it is safe to run twice.
- **A new colleague sees "Your account is not set up yet"** — they signed up
  themselves with an email the Admin hadn't entered. Have the Admin create the
  account with that exact email address.
- **Account creation says "half-created"** — email confirmation is still ON
  (step 3). Turn it off; the person can then sign up themselves with their
  email and will land in the right job role.
