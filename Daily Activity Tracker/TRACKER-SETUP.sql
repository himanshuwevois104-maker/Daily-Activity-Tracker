-- WeVois Daily Activity Tracker - complete database setup. Select ALL of this file and Run.
-- Target: a BRAND-NEW Supabase project (not the billing one).
-- Safe to re-run: every object is created with IF NOT EXISTS or dropped first.
-- After running, scroll to the bottom for the verification row.

-- ============================================================
-- 1. TABLES
-- ============================================================

create table if not exists dat_departments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);
create unique index if not exists dat_dept_name_uniq on dat_departments (lower(name));

create table if not exists dat_job_roles (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  dept        text not null default 'Operations',
  level       text not null default 'member'
              check (level in ('ceo','vp','manager','member')),
  pipes       jsonb not null default '[]'::jsonb,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists dat_role_name_uniq on dat_job_roles (lower(name));

create table if not exists dat_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  email       text,
  role_id     uuid references dat_job_roles(id) on delete set null,
  level       text not null default 'member'
              check (level in ('ceo','vp','manager','member')),
  mgr_id      uuid references dat_profiles(id) on delete set null,
  dept        text not null default 'Operations',
  admin       boolean not null default false,
  active      boolean not null default true,
  color       int  not null default 1,
  created_at  timestamptz not null default now()
);
create index if not exists dat_profiles_mgr_idx on dat_profiles (mgr_id);

-- Pre-authorisation. An admin adds the row BEFORE the person signs up; the
-- signup trigger below turns it into a profile. Signing up with an email that
-- is not in here creates NO profile, so the account can see nothing at all.
create table if not exists dat_invites (
  email       text primary key,
  name        text not null,
  role_id     uuid references dat_job_roles(id) on delete set null,
  level       text not null default 'member',
  mgr_id      uuid references dat_profiles(id) on delete set null,
  dept        text not null default 'Operations',
  admin       boolean not null default false,
  color       int  not null default 1,
  used        boolean not null default false,
  created_by  uuid references dat_profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists dat_pipelines (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  dept        text not null default 'Operations',
  color       int  not null default 1,
  stages      jsonb not null default '["To Do","In Progress","Done"]'::jsonb,
  created_by  uuid references dat_profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists dat_tasks (
  id          uuid primary key default gen_random_uuid(),
  pipeline_id uuid not null references dat_pipelines(id) on delete cascade,
  stage       text not null,
  title       text not null,
  description text not null default '',
  assignee    uuid references dat_profiles(id) on delete set null,
  priority    text not null default 'medium'
              check (priority in ('urgent','high','medium','low')),
  due         date,
  done        boolean not null default false,
  done_on     date,
  created_by  uuid references dat_profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists dat_tasks_pipe_idx on dat_tasks (pipeline_id);
create index if not exists dat_tasks_assignee_idx on dat_tasks (assignee);

create table if not exists dat_log_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  icon        text not null default 'N',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists dat_cat_name_uniq on dat_log_categories (lower(name));

create table if not exists dat_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references dat_profiles(id) on delete cascade,
  log_date    date not null default current_date,
  category_id uuid references dat_log_categories(id) on delete set null,
  note        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists dat_logs_user_date_idx on dat_logs (user_id, log_date desc);

create table if not exists dat_requests (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('role','account')),
  requested_by  uuid not null references dat_profiles(id) on delete cascade,
  payload       jsonb not null default '{}'::jsonb,
  note          text not null default '',
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected')),
  decided_by    uuid references dat_profiles(id) on delete set null,
  decided_on    date,
  reason        text not null default '',
  created_at    timestamptz not null default now()
);

create table if not exists dat_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references dat_profiles(id) on delete cascade,
  type        text not null default 'move',
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists dat_events_created_idx on dat_events (created_at desc);

-- ============================================================
-- 2. HELPER FUNCTIONS (security definer, so they can read profiles
--    without tripping the very policies they are used inside)
-- ============================================================

create or replace function dat_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin and p.active from dat_profiles p where p.id = auth.uid()), false);
$$;

create or replace function dat_my_level() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select p.level from dat_profiles p where p.id = auth.uid() and p.active), 'none');
$$;

create or replace function dat_has_profile() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from dat_profiles p where p.id = auth.uid() and p.active);
$$;

-- every active profile at or below the given person
create or replace function dat_subtree(root uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  with recursive t as (
    select p.id from dat_profiles p where p.id = root and p.active
    union all
    select c.id from dat_profiles c join t on c.mgr_id = t.id where c.active
  )
  select id from t;
$$;

-- Whose WORK the caller may see: ceo -> everyone, member -> self,
-- vp/manager -> their own subtree.
-- Deliberately no admin clause: an admin manages accounts, not people's work,
-- so being an Admin does not by itself expose anyone's tasks or daily log.
create or replace function dat_visible_users() returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id from dat_profiles p
    where p.active and dat_my_level() = 'ceo'
  union
  select auth.uid()
    where dat_my_level() = 'member'
  union
  select s from dat_subtree(auth.uid()) s
    where dat_my_level() in ('vp','manager');
$$;

-- pipeline ids the caller reaches through their job role, company-wide
create or replace function dat_my_role_pipes() returns setof uuid
language sql stable security definer set search_path = public as $$
  select (jsonb_array_elements_text(r.pipes))::uuid
  from dat_profiles p join dat_job_roles r on r.id = p.role_id
  where p.id = auth.uid() and p.active and r.active;
$$;

-- departments the caller's visible people sit in
create or replace function dat_visible_depts() returns setof text
language sql stable security definer set search_path = public as $$
  select distinct p.dept from dat_profiles p
  where p.id in (select dat_visible_users());
$$;

-- Callable BEFORE anyone is signed in, so the app knows whether to show
-- "sign in" or the one-time "create the first Admin" screen. It leaks only a
-- single boolean, never any row.
create or replace function dat_needs_setup() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from dat_profiles);
$$;

-- ============================================================
-- 3. SIGNUP TRIGGER
--    First account ever created becomes the Admin. Every later signup
--    only gets a profile if an admin pre-authorised that email.
-- ============================================================

create or replace function dat_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv       dat_invites%rowtype;
  n_profiles int;
  admin_role uuid;
  nm        text;
begin
  select count(*) into n_profiles from dat_profiles;
  nm := coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1));

  if n_profiles = 0 then
    -- bootstrap: the very first account is the Admin
    select id into admin_role from dat_job_roles where lower(name) = 'system administrator' limit 1;
    insert into dat_profiles (id, name, email, role_id, level, dept, admin, active, color)
    values (new.id, nm, new.email, admin_role, 'member', 'Administration', true, true, 4);
    return new;
  end if;

  select * into inv from dat_invites where lower(email) = lower(new.email) and not used;
  if found then
    insert into dat_profiles (id, name, email, role_id, level, mgr_id, dept, admin, active, color)
    values (new.id, coalesce(nullif(inv.name,''), nm), new.email, inv.role_id, inv.level,
            inv.mgr_id, inv.dept, inv.admin, true, inv.color);
    update dat_invites set used = true where email = inv.email;
  end if;
  -- no invite -> no profile. The account can sign in but RLS shows it nothing.
  return new;
end;
$$;

drop trigger if exists dat_on_auth_user_created on auth.users;
create trigger dat_on_auth_user_created
  after insert on auth.users
  for each row execute function dat_handle_new_user();

-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================

alter table dat_departments   enable row level security;
alter table dat_job_roles     enable row level security;
alter table dat_profiles      enable row level security;
alter table dat_invites       enable row level security;
alter table dat_pipelines     enable row level security;
alter table dat_tasks         enable row level security;
alter table dat_log_categories enable row level security;
alter table dat_logs          enable row level security;
alter table dat_requests      enable row level security;
alter table dat_events        enable row level security;

-- ---- departments: everyone signed in reads, only admin writes
drop policy if exists dat_dept_read   on dat_departments;
drop policy if exists dat_dept_write  on dat_departments;
create policy dat_dept_read  on dat_departments for select using (dat_has_profile());
create policy dat_dept_write on dat_departments for all
  using (dat_is_admin()) with check (dat_is_admin());

-- ---- job roles: everyone reads (they are designations), only admin writes
drop policy if exists dat_role_read  on dat_job_roles;
drop policy if exists dat_role_write on dat_job_roles;
create policy dat_role_read  on dat_job_roles for select using (dat_has_profile());
create policy dat_role_write on dat_job_roles for all
  using (dat_is_admin()) with check (dat_is_admin());

-- ---- profiles: the staff directory is readable by any signed-in colleague,
--      but only an admin may create, change or deactivate an account.
drop policy if exists dat_prof_read   on dat_profiles;
drop policy if exists dat_prof_write  on dat_profiles;
drop policy if exists dat_prof_update on dat_profiles;
drop policy if exists dat_prof_delete on dat_profiles;
create policy dat_prof_read   on dat_profiles for select using (dat_has_profile());
create policy dat_prof_write  on dat_profiles for insert with check (dat_is_admin());
create policy dat_prof_update on dat_profiles for update
  using (dat_is_admin()) with check (dat_is_admin());
create policy dat_prof_delete on dat_profiles for delete using (dat_is_admin());

-- ---- invites: admin only, both ways
drop policy if exists dat_inv_all on dat_invites;
create policy dat_inv_all on dat_invites for all
  using (dat_is_admin()) with check (dat_is_admin());

-- ---- pipelines
drop policy if exists dat_pipe_read   on dat_pipelines;
drop policy if exists dat_pipe_insert on dat_pipelines;
drop policy if exists dat_pipe_update on dat_pipelines;
drop policy if exists dat_pipe_delete on dat_pipelines;
create policy dat_pipe_read on dat_pipelines for select using (
  dat_is_admin()
  or dat_my_level() = 'ceo'
  or created_by = auth.uid()
  or dept in (select dat_visible_depts())
  or id in (select dat_my_role_pipes())
);
-- only manager and above may build a pipeline
create policy dat_pipe_insert on dat_pipelines for insert with check (
  dat_my_level() in ('ceo','vp','manager')
);
create policy dat_pipe_update on dat_pipelines for update using (
  dat_my_level() = 'ceo' or created_by = auth.uid()
  or (dat_my_level() = 'vp' and dept in (select dat_visible_depts()))
) with check (
  dat_my_level() = 'ceo' or created_by = auth.uid()
  or (dat_my_level() = 'vp' and dept in (select dat_visible_depts()))
);
create policy dat_pipe_delete on dat_pipelines for delete using (
  dat_my_level() = 'ceo' or created_by = auth.uid()
);

-- ---- tasks
drop policy if exists dat_task_read   on dat_tasks;
drop policy if exists dat_task_insert on dat_tasks;
drop policy if exists dat_task_update on dat_tasks;
drop policy if exists dat_task_delete on dat_tasks;
create policy dat_task_read on dat_tasks for select using (
  assignee in (select dat_visible_users())
  or created_by = auth.uid()
  or pipeline_id in (select dat_my_role_pipes())
);
-- you may raise a task for yourself, or for anyone in your own subtree
create policy dat_task_insert on dat_tasks for insert with check (
  dat_has_profile() and (
    assignee = auth.uid()
    or dat_my_level() = 'ceo'
    or assignee in (select dat_subtree(auth.uid()))
  )
);
create policy dat_task_update on dat_tasks for update using (
  dat_is_admin() or dat_my_level() = 'ceo'
  or assignee = auth.uid() or created_by = auth.uid()
  or assignee in (select dat_subtree(auth.uid()))
) with check (
  dat_is_admin() or dat_my_level() = 'ceo'
  or assignee = auth.uid() or created_by = auth.uid()
  or assignee in (select dat_subtree(auth.uid()))
);
create policy dat_task_delete on dat_tasks for delete using (
  dat_is_admin() or dat_my_level() = 'ceo'
  or created_by = auth.uid()
  or assignee in (select dat_subtree(auth.uid()))
);

-- ---- log categories: everyone reads, admin writes
drop policy if exists dat_cat_read  on dat_log_categories;
drop policy if exists dat_cat_write on dat_log_categories;
create policy dat_cat_read  on dat_log_categories for select using (dat_has_profile());
create policy dat_cat_write on dat_log_categories for all
  using (dat_is_admin()) with check (dat_is_admin());

-- ---- daily logs: your reporting line reads yours; ONLY YOU write yours.
--      A manager deliberately cannot edit a report's entry - otherwise the
--      log stops being a trustworthy account of what that person reported.
drop policy if exists dat_log_read   on dat_logs;
drop policy if exists dat_log_insert on dat_logs;
drop policy if exists dat_log_update on dat_logs;
drop policy if exists dat_log_delete on dat_logs;
create policy dat_log_read on dat_logs for select using (
  user_id in (select dat_visible_users())
);
create policy dat_log_insert on dat_logs for insert with check (user_id = auth.uid());
create policy dat_log_update on dat_logs for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy dat_log_delete on dat_logs for delete
  using (user_id = auth.uid() or dat_is_admin());

-- ---- requests: CEO and VP raise them, admin decides them
drop policy if exists dat_req_read   on dat_requests;
drop policy if exists dat_req_insert on dat_requests;
drop policy if exists dat_req_update on dat_requests;
create policy dat_req_read on dat_requests for select using (
  requested_by = auth.uid() or dat_is_admin()
);
create policy dat_req_insert on dat_requests for insert with check (
  requested_by = auth.uid() and dat_my_level() in ('ceo','vp')
);
create policy dat_req_update on dat_requests for update
  using (dat_is_admin()) with check (dat_is_admin());

-- ---- activity feed
drop policy if exists dat_ev_read   on dat_events;
drop policy if exists dat_ev_insert on dat_events;
create policy dat_ev_read on dat_events for select using (
  user_id in (select dat_visible_users()) or user_id = auth.uid()
);
create policy dat_ev_insert on dat_events for insert with check (user_id = auth.uid());

-- ============================================================
-- 4b. GRANTS
--     Supabase normally grants these automatically, but being explicit means
--     the migration also works if default privileges were ever changed.
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['dat_departments','dat_job_roles','dat_profiles','dat_invites',
                           'dat_pipelines','dat_tasks','dat_log_categories','dat_logs',
                           'dat_requests','dat_events']
  loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

grant usage on schema public to authenticated;
grant execute on function dat_is_admin(), dat_my_level(), dat_has_profile(),
  dat_subtree(uuid), dat_visible_users(), dat_my_role_pipes(), dat_visible_depts()
  to authenticated;

-- the first-run check must work before sign-in
grant usage on schema public to anon;
grant execute on function dat_needs_setup() to anon, authenticated;

-- ============================================================
-- 5. SEED: departments, job roles, log categories
--    No people and no pipelines - you add those in the app.
-- ============================================================

insert into dat_departments (name)
select v from (values
  ('Leadership'),('Sales'),('Marketing'),('Operations'),('Support'),('Billing'),
  ('Tender'),('Legal'),('Accounts'),('HR'),('Strategy'),('Administration')
) as t(v)
where not exists (select 1 from dat_departments d where lower(d.name) = lower(t.v));

insert into dat_job_roles (name, dept, level)
select t.n, t.d, t.l from (values
  ('Chief Executive Officer',        'Leadership',     'ceo'),
  ('VP - Sales & Marketing',         'Sales',          'vp'),
  ('VP - Operations',                'Operations',     'vp'),
  ('VP - Corporate Affairs',         'Strategy',       'vp'),
  ('Manager - Sales Operations',     'Sales',          'manager'),
  ('Manager - Marketing',            'Marketing',      'manager'),
  ('Manager - Field Operations',     'Operations',     'manager'),
  ('Manager - Support',              'Support',        'manager'),
  ('Billing Manager',                'Billing',        'manager'),
  ('Key Account Manager',            'Sales',          'manager'),
  ('Business Development Executive', 'Sales',          'member'),
  ('Tender Executive',               'Tender',         'member'),
  ('Legal Executive',                'Legal',          'member'),
  ('Business Analyst',               'Strategy',       'member'),
  ('HR Executive',                   'HR',             'member'),
  ('Social Media Executive',         'Marketing',      'member'),
  ('Accounts Executive',             'Accounts',       'member'),
  ('Field Executive',                'Operations',     'member'),
  ('Support Executive',              'Support',        'member'),
  ('Backoffice Executive',           'Support',        'member'),
  ('Content Executive',              'Marketing',      'member'),
  ('Site CRM',                       'Billing',        'member'),
  ('System Administrator',           'Administration', 'member')
) as t(n,d,l)
where not exists (select 1 from dat_job_roles r where lower(r.name) = lower(t.n));

-- icons are written as ASCII unicode escapes so this file stays pure ASCII
insert into dat_log_categories (name, icon)
select t.n, t.i from (values
  ('Site / Field visit', E'\U0001F4CD'),
  ('Meeting',            E'\U0001F91D'),
  ('Follow-up',          E'\U0001F4DE'),
  ('Documentation',      E'\U0001F4C4'),
  ('Review',             E'\U0001F50D'),
  ('Other',              E'\U0001F4CC')
) as t(n,i)
where not exists (select 1 from dat_log_categories c where lower(c.name) = lower(t.n));

-- ============================================================
-- 6. REALTIME
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['dat_departments','dat_job_roles','dat_profiles','dat_pipelines',
                           'dat_tasks','dat_log_categories','dat_logs','dat_requests','dat_events']
  loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when others then null;  -- already added, or publication absent locally
    end;
  end loop;
end $$;

-- ============================================================
-- 7. VERIFICATION - all six numbers should read:
--    12 - 23 - 6 - 0 - 0 - true
--    departments - job roles - log categories - profiles - pipelines - RLS on everywhere
-- ============================================================
select
  (select count(*) from dat_departments)                          as departments,
  (select count(*) from dat_job_roles)                            as job_roles,
  (select count(*) from dat_log_categories)                       as log_categories,
  (select count(*) from dat_profiles)                             as profiles,
  (select count(*) from dat_pipelines)                            as pipelines,
  (select bool_and(rowsecurity) from pg_tables
     where schemaname = 'public' and tablename like 'dat\_%')     as rls_on_everywhere;
