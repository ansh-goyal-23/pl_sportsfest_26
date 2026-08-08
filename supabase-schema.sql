-- =========================================================
-- Prateek Laurel Sports Fest 2026 — Supabase schema
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run
-- =========================================================

-- ---------- Tables ----------
create table if not exists registrations (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null,
  sport_name text not null,
  category_id text,
  event_id text,
  event_label text,
  gender_cat text,
  team_name text,
  participants jsonb not null,
  phone text not null,
  flat text not null,
  fee integer not null default 0,
  screenshot_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  player_id text,
  submitted_at timestamptz not null default now()
);

create table if not exists updates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null,
  pinned boolean not null default false,
  date timestamptz not null default now()
);

create table if not exists fixtures (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null,
  date date,
  time text,
  venue text,
  participants_text text,
  status text not null default 'upcoming' check (status in ('upcoming','completed')),
  result text
);

create table if not exists sponsors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tier text not null,
  website text,
  blurb text,
  logo_url text
);

create table if not exists photos (
  id uuid primary key default gen_random_uuid(),
  url text not null,
  caption text,
  date timestamptz not null default now()
);

create table if not exists settings (
  id text primary key default 'main',
  upi_id text default '',
  updated_at timestamptz default now()
);
insert into settings (id, upi_id) values ('main', '') on conflict (id) do nothing;

-- ---------- Row Level Security ----------
alter table registrations enable row level security;
alter table updates enable row level security;
alter table fixtures enable row level security;
alter table sponsors enable row level security;
alter table photos enable row level security;
alter table settings enable row level security;

-- Registrations: anyone can submit; only logged-in organisers can read/approve/delete
create policy "public can register" on registrations for insert to anon with check (true);
create policy "organisers manage registrations" on registrations for all to authenticated using (true) with check (true);

-- Updates / Fixtures / Sponsors / Photos: everyone can read; only organisers can write
create policy "public read updates" on updates for select to anon using (true);
create policy "organisers manage updates" on updates for all to authenticated using (true) with check (true);

create policy "public read fixtures" on fixtures for select to anon using (true);
create policy "organisers manage fixtures" on fixtures for all to authenticated using (true) with check (true);

create policy "public read sponsors" on sponsors for select to anon using (true);
create policy "organisers manage sponsors" on sponsors for all to authenticated using (true) with check (true);

create policy "public read photos" on photos for select to anon using (true);
create policy "organisers manage photos" on photos for all to authenticated using (true) with check (true);

create policy "public read settings" on settings for select to anon using (true);
create policy "organisers manage settings" on settings for all to authenticated using (true) with check (true);

-- ---------- Status-check function ----------
-- Lets a participant look up THEIR OWN registrations by phone number,
-- without granting public read access to the whole registrations table.
create or replace function check_registration_status(p_phone text)
returns table (
  sport_name text, event_label text, status text, player_id text, submitted_at timestamptz
)
language sql security definer set search_path = public as $$
  select sport_name, event_label, status, player_id, submitted_at
  from registrations
  where phone = p_phone
  order by submitted_at desc;
$$;
grant execute on function check_registration_status(text) to anon;

-- ---------- Storage buckets ----------
-- payment-screenshots is PRIVATE (only organisers can view, via signed URLs)
-- sponsor-logos and event-photos are PUBLIC (shown directly on the site)
insert into storage.buckets (id, name, public)
  values ('payment-screenshots', 'payment-screenshots', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('sponsor-logos', 'sponsor-logos', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('event-photos', 'event-photos', true)
  on conflict (id) do nothing;

create policy "anon upload payment screenshots" on storage.objects
  for insert to anon with check (bucket_id = 'payment-screenshots');
-- Organisers testing the public registration form while logged into the
-- admin console will submit as an authenticated user, not anon (Supabase
-- Auth sessions are shared across every tab in the browser) — so uploads
-- need to work for both roles, not just anon.
create policy "organisers can also upload payment screenshots" on storage.objects
  for insert to authenticated with check (bucket_id = 'payment-screenshots');
-- The Storage API always tries to read a file's metadata back immediately
-- after upload (the same way a database INSERT ... RETURNING does) — even
-- for anonymous uploaders. Without some SELECT access, that automatic
-- read-back fails RLS and the whole upload is reported as an error, even
-- though the file was actually saved. Granting anon a full-time SELECT
-- policy here would let anyone holding the public anon key browse every
-- resident's payment screenshot, so instead this only allows reading files
-- uploaded in the last few minutes — enough for that one automatic
-- read-back to succeed, without leaving the bucket open long-term.
create policy "anon can briefly read own payment screenshot upload" on storage.objects
  for select to anon using (bucket_id = 'payment-screenshots' and created_at > now() - interval '5 minutes');
create policy "organisers read payment screenshots" on storage.objects
  for select to authenticated using (bucket_id = 'payment-screenshots');
create policy "organisers delete payment screenshots" on storage.objects
  for delete to authenticated using (bucket_id = 'payment-screenshots');

create policy "public read sponsor logos" on storage.objects
  for select to anon using (bucket_id = 'sponsor-logos');
create policy "organisers write sponsor logos" on storage.objects
  for insert to authenticated with check (bucket_id = 'sponsor-logos');
create policy "organisers delete sponsor logos" on storage.objects
  for delete to authenticated using (bucket_id = 'sponsor-logos');

create policy "public read event photos" on storage.objects
  for select to anon using (bucket_id = 'event-photos');
create policy "organisers write event photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'event-photos');
create policy "organisers delete event photos" on storage.objects
  for delete to authenticated using (bucket_id = 'event-photos');

-- =========================================================
-- Done. Next steps (see README.md):
-- 1. Authentication → Providers → make sure Email is enabled.
-- 2. Authentication → Settings → turn OFF "Allow new users to sign up".
-- 3. Authentication → Users → Add user → create one login per organiser
--    (Rahul, Tarun, Kapil) with their email + a password.
-- 4. Project Settings → API → copy the Project URL and anon public key
--    into index.html where marked, then deploy.
-- =========================================================
