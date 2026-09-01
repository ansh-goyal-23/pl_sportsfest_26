-- =========================================================
-- Prateek Laurel Sports Fest 2026 — Supabase schema
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run
--
-- This is a full, consolidated schema reflecting everything the current
-- index.html actually uses — registrations, updates, fixtures boards
-- (per sport/category/event/gender), sponsors, photos, site settings,
-- registration open/close control, live match scoring, and site
-- analytics. If you're running this fresh, every "create table if not
-- exists" / "add column if not exists" is safe to run even if some of
-- it already exists in your project.
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
  submitted_at timestamptz not null default now(),
  -- Basketball Open player-auction fields (position, playing style, etc.)
  auction_info jsonb,
  -- Player's own photo for the auction, uploaded to the private
  -- player-photos bucket.
  player_photo_path text,
  -- Anonymous per-browser ID (see Site Analytics), tags which visitor
  -- completed this registration — never used for anything else.
  visitor_id text
);

create table if not exists updates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null,
  pinned boolean not null default false,
  date timestamptz not null default now(),
  -- Set when an update is linked to a posted photo, so the photo shows
  -- inline on the Updates page instead of just being announced in text.
  image_url text
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

-- One drawn fixtures/bracket image per sport + category + event (+
-- gender, where that sport splits by gender). event_id is '' when a
-- category only has one event (or the board covers every event in that
-- category at once) — organisers upload a photo of the fixtures board
-- rather than entering matches one by one.
create table if not exists fixture_boards (
  sport_id text not null,
  category_id text not null,
  event_id text not null default '',
  gender text not null default '',
  image_path text not null,
  updated_at timestamptz not null default now(),
  primary key (sport_id, category_id, event_id, gender)
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
  updated_at timestamptz default now(),
  -- Path to an admin-uploaded QR image (e.g. a bank-issued static QR),
  -- shown instead of a generated one when set — some banks' UPI apps
  -- handle a real bank QR more reliably than a generated collect-request
  -- QR code.
  payment_qr_path text,
  -- Link to a Google Sheet published to the web as CSV (Admin -> Results).
  -- The public Results page fetches this Sheet live and searches it —
  -- nothing about awardees is stored in this database. The `awardees`
  -- table further down is legacy from an earlier Excel-upload version of
  -- this feature and is no longer read by the site; safe to ignore/drop.
  results_sheet_url text
);
insert into settings (id, upi_id) values ('main', '') on conflict (id) do nothing;
alter table settings add column if not exists results_sheet_url text;

-- Lets organisers close (or schedule an automatic close for) registration
-- on a specific category, from Admin → Registration Status — no code
-- change or redeploy needed to open/close something.
create table if not exists category_status (
  sport_id text not null,
  category_id text not null,
  closed boolean not null default false,
  closes_at timestamptz,
  closed_message text,
  updated_at timestamptz not null default now(),
  primary key (sport_id, category_id)
);

-- Live match scoring (currently used for Basketball). One row per match;
-- score is derived live from score_events, not stored as a mutable
-- number on this row.
create table if not exists matches (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null default 'basketball',
  category_id text not null,
  team_a_name text not null,
  team_b_name text not null,
  team_a_players jsonb not null default '[]', -- [{name}]
  team_b_players jsonb not null default '[]',
  duration_seconds int not null default 1200,
  remaining_seconds int not null default 1200,
  running_since timestamptz, -- null when paused/not started; set when the clock is actively running
  clock_state text not null default 'not_started', -- not_started | running | paused | ended
  scorer_token text not null default encode(gen_random_bytes(12), 'hex'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Every scoring tap is its own permanent, timestamped record — never a
-- mutation of an existing number. A mistaken tap gets excluded (toggled
-- off), never deleted, so there's always a full audit trail. A match's
-- displayed score is always "sum of every non-excluded event for that
-- team," computed live.
create table if not exists score_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references matches(id) on delete cascade,
  team text not null, -- 'A' or 'B'
  player_name text not null,
  points int not null,
  excluded boolean not null default false,
  created_at timestamptz not null default now()
);

-- Finalised Basketball Open auction teams, entered once in Admin so
-- they're available to pick from when setting up a match.
create table if not exists open_category_teams (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null default 'basketball',
  team_name text not null,
  players jsonb not null default '[]',
  created_at timestamptz not null default now()
);

-- Anonymous, browser-ID-based site analytics (Admin → Site Analytics).
-- No names, phone numbers, or IP addresses recorded.
create table if not exists analytics_events (
  id uuid primary key default gen_random_uuid(),
  visitor_id text not null,
  event_type text not null check (event_type in ('hit','pageview')),
  page text,
  created_at timestamptz not null default now()
);

-- ---------- Row Level Security ----------
alter table registrations enable row level security;
alter table updates enable row level security;
alter table fixtures enable row level security;
alter table fixture_boards enable row level security;
alter table sponsors enable row level security;
alter table photos enable row level security;
alter table settings enable row level security;
alter table category_status enable row level security;
alter table matches enable row level security;
alter table score_events enable row level security;
alter table open_category_teams enable row level security;
alter table analytics_events enable row level security;

-- Registrations: anyone can submit; only logged-in organisers can read/approve/delete
create policy "public can register" on registrations for insert to anon with check (true);
create policy "organisers manage registrations" on registrations for all to authenticated using (true) with check (true);

-- Updates / Fixtures / Sponsors / Photos: everyone can read; only organisers can write
create policy "public read updates" on updates for select to anon using (true);
create policy "organisers manage updates" on updates for all to authenticated using (true) with check (true);

create policy "public read fixtures" on fixtures for select to anon using (true);
create policy "organisers manage fixtures" on fixtures for all to authenticated using (true) with check (true);

create policy "public read fixture boards" on fixture_boards for select to anon using (true);
create policy "organisers manage fixture boards" on fixture_boards for all to authenticated using (true) with check (true);

create policy "public read sponsors" on sponsors for select to anon using (true);
create policy "organisers manage sponsors" on sponsors for all to authenticated using (true) with check (true);

create policy "public read photos" on photos for select to anon using (true);
create policy "organisers manage photos" on photos for all to authenticated using (true) with check (true);

create policy "public read settings" on settings for select to anon using (true);
create policy "organisers manage settings" on settings for all to authenticated using (true) with check (true);

create policy "public read category status" on category_status for select to anon using (true);
create policy "organisers manage category status" on category_status for all to authenticated using (true) with check (true);

-- Matches / score_events: readable and updatable by anon (the public live
-- scoreboard and the no-login scorer link both need this), full control
-- for organisers. There's deliberately no anon DELETE policy on
-- score_events — a scoring mistake can only ever be excluded, never
-- removed, so there's always a full audit trail.
create policy "public read matches" on matches for select to anon using (true);
create policy "public update matches" on matches for update to anon using (true) with check (true);
create policy "organisers manage matches" on matches for all to authenticated using (true) with check (true);

create policy "public read score events" on score_events for select to anon using (true);
create policy "public insert score events" on score_events for insert to anon with check (true);
create policy "public update score events" on score_events for update to anon using (true) with check (true);
create policy "organisers manage score events" on score_events for all to authenticated using (true) with check (true);

create policy "public read open teams" on open_category_teams for select to anon using (true);
create policy "organisers manage open teams" on open_category_teams for all to authenticated using (true) with check (true);

-- Analytics: anon can only log events (never read them back); organisers
-- can read/manage everything for the Site Analytics dashboard.
create policy "anon can log analytics" on analytics_events for insert to anon with check (true);
create policy "organisers manage analytics" on analytics_events for all to authenticated using (true) with check (true);

-- ---------- Status-check function ----------
-- Lets a participant look up THEIR OWN registrations by phone number,
-- without granting public read access to the whole registrations table.
-- Returns category/team/participant details too, so someone checking
-- their status can see exactly what they submitted.
create or replace function check_registration_status(p_phone text)
returns table (
  sport_name text, event_label text, status text, player_id text,
  category_id text, team_name text, participants jsonb
)
language sql security definer set search_path = public as $$
  select sport_name, event_label, status, player_id, category_id, team_name, participants
  from registrations
  where phone = p_phone
  order by submitted_at desc;
$$;
grant execute on function check_registration_status(text) to anon;

-- ---------- Storage buckets ----------
-- payment-screenshots and player-photos are PRIVATE (only organisers can
-- view, via signed URLs). sponsor-logos, event-photos, fixture-boards
-- and payment-qr are PUBLIC (shown directly on the site).
insert into storage.buckets (id, name, public)
  values ('payment-screenshots', 'payment-screenshots', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('sponsor-logos', 'sponsor-logos', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('event-photos', 'event-photos', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('fixture-boards', 'fixture-boards', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('player-photos', 'player-photos', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('payment-qr', 'payment-qr', true)
  on conflict (id) do update set public = true;

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

create policy "public read fixture boards" on storage.objects
  for select to anon using (bucket_id = 'fixture-boards');
create policy "organisers write fixture boards" on storage.objects
  for insert to authenticated with check (bucket_id = 'fixture-boards');
create policy "organisers update fixture boards" on storage.objects
  for update to authenticated using (bucket_id = 'fixture-boards') with check (bucket_id = 'fixture-boards');
create policy "organisers delete fixture boards" on storage.objects
  for delete to authenticated using (bucket_id = 'fixture-boards');

-- Player photos (Basketball Open auction) — anon uploads their own
-- during registration, only organisers can view/manage.
create policy "anon upload player photos" on storage.objects
  for insert to anon with check (bucket_id = 'player-photos');
create policy "organisers can also upload player photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'player-photos');
create policy "anon can briefly read own player photo upload" on storage.objects
  for select to anon using (bucket_id = 'player-photos' and created_at > now() - interval '5 minutes');
create policy "organisers read player photos" on storage.objects
  for select to authenticated using (bucket_id = 'player-photos');
create policy "organisers delete player photos" on storage.objects
  for delete to authenticated using (bucket_id = 'player-photos');

-- Payment QR image — public (shown on every registration form), only
-- organisers can upload/replace it from Admin → Settings.
create policy "public read payment qr" on storage.objects
  for select to anon using (bucket_id = 'payment-qr');
create policy "organisers write payment qr" on storage.objects
  for insert to authenticated with check (bucket_id = 'payment-qr');
create policy "organisers update payment qr" on storage.objects
  for update to authenticated using (bucket_id = 'payment-qr') with check (bucket_id = 'payment-qr');
create policy "organisers delete payment qr" on storage.objects
  for delete to authenticated using (bucket_id = 'payment-qr');

-- =========================================================
-- Done. Next steps (see README.md):
-- 1. Authentication → Providers → make sure Email is enabled.
-- 2. Authentication → Settings → turn OFF "Allow new users to sign up".
-- 3. Authentication → Users → Add user → create one login per organiser
--    (Rahul, Tarun, Kapil) with their email + a password.
-- 4. Project Settings → API → copy the Project URL and anon public key
--    into index.html where marked, then deploy.
-- =========================================================

-- =========================================================
-- Results / Awardees + Gallery (added later)
-- =========================================================

-- One row per uploaded "official results" PDF (Admin -> Results). Multiple
-- PDFs can be listed at once (e.g. one per sport, or updated versions over
-- time) - nothing here is ever auto-deleted, organisers manage the list.
create table if not exists results_files (
  id uuid primary key default gen_random_uuid(),
  label text,
  file_name text not null,
  file_path text not null,
  uploaded_at timestamptz not null default now()
);

-- Parsed rows from an admin-uploaded Excel sheet of awardees, so visitors
-- can search their own name and see what they won without having to open
-- a PDF. Admin can upload a fresh Excel any time - each upload appends
-- more rows (old rows are never touched unless an organiser clears them).
create table if not exists awardees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sport text,
  event text,
  category text,
  award text,
  uploaded_at timestamptz not null default now()
);

-- Event photo gallery, shown on its own Gallery page and cycled through
-- as a slideshow on the Home page. Deliberately separate from the
-- existing `photos` table, which feeds the Updates page's
-- photo-highlight posts - gallery uploads do NOT create Updates entries.
create table if not exists gallery_photos (
  id uuid primary key default gen_random_uuid(),
  url text not null,
  caption text,
  created_at timestamptz not null default now()
);

alter table results_files enable row level security;
alter table awardees enable row level security;
alter table gallery_photos enable row level security;

drop policy if exists "public read results files" on results_files;
create policy "public read results files" on results_files for select to anon using (true);
drop policy if exists "organisers manage results files" on results_files;
create policy "organisers manage results files" on results_files for all to authenticated using (true) with check (true);

drop policy if exists "public read awardees" on awardees;
create policy "public read awardees" on awardees for select to anon using (true);
drop policy if exists "organisers manage awardees" on awardees;
create policy "organisers manage awardees" on awardees for all to authenticated using (true) with check (true);

drop policy if exists "public read gallery photos" on gallery_photos;
create policy "public read gallery photos" on gallery_photos for select to anon using (true);
drop policy if exists "organisers manage gallery photos" on gallery_photos;
create policy "organisers manage gallery photos" on gallery_photos for all to authenticated using (true) with check (true);

-- Storage buckets: both public, since the whole point is visitors
-- downloading the results PDF and viewing gallery photos directly.
insert into storage.buckets (id, name, public)
  values ('results-pdf', 'results-pdf', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
  values ('gallery-photos', 'gallery-photos', true)
  on conflict (id) do nothing;

drop policy if exists "public read results pdf" on storage.objects;
create policy "public read results pdf" on storage.objects
  for select to anon using (bucket_id = 'results-pdf');
drop policy if exists "organisers write results pdf" on storage.objects;
create policy "organisers write results pdf" on storage.objects
  for insert to authenticated with check (bucket_id = 'results-pdf');
drop policy if exists "organisers delete results pdf" on storage.objects;
create policy "organisers delete results pdf" on storage.objects
  for delete to authenticated using (bucket_id = 'results-pdf');

drop policy if exists "public read gallery photos storage" on storage.objects;
create policy "public read gallery photos storage" on storage.objects
  for select to anon using (bucket_id = 'gallery-photos');
drop policy if exists "organisers write gallery photos" on storage.objects;
create policy "organisers write gallery photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'gallery-photos');
drop policy if exists "organisers delete gallery photos" on storage.objects;
create policy "organisers delete gallery photos" on storage.objects
  for delete to authenticated using (bucket_id = 'gallery-photos');
