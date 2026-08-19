# Prateek Laurel Sports Fest 2026 — Deployment Guide

This site is a single `index.html` file backed by a real Supabase database.
Everyone who visits it sees the same live data — registrations, updates,
fixtures, sponsors, photos — because it's stored in your Supabase project,
not in the browser.

Total setup time: about 10–15 minutes. Three stages:
**A) Supabase** (database + accounts) → **B) index.html** (paste in your keys)
→ **C) Render** (put the site online).

---

## A. Set up Supabase (~5 min)

You said you've already connected a Supabase account — if you haven't
created a **project** yet, do that first at supabase.com → New Project
(pick any name/region, e.g. "prateek-laurel-sports-fest").

1. **Run the schema.**
   In your Supabase project, open **SQL Editor → New query**, paste in
   the entire contents of `supabase-schema.sql` (included alongside this
   file), and click **Run**. This creates all twelve tables, the security
   rules, the phone-lookup function, and the six storage buckets. It's
   safe to re-run at any point — every statement is written to skip
   anything that already exists rather than error out.

2. **Turn off public sign-up.**
   Go to **Authentication → Sign In / Providers** (or **Authentication →
   Settings**, depending on your Supabase version) and turn **off**
   "Allow new users to sign up". This matters — without it, anyone could
   create their own login and get into the admin console.

3. **Create your organiser logins.**
   Go to **Authentication → Users → Add user**. Create one user for each
   organiser who needs admin access (Rahul, Tarun, Kapil, or however you
   want to split it) — an email address and a password each. These are
   the credentials they'll use to log into the "Organiser Login" link in
   the site footer. No self-signup, no shared passcode.

4. **Copy your API keys.**
   Go to **Project Settings → API**. You'll need two values from this
   page in the next step:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon / public key** (a long string starting with `eyJ...`)

   Don't use the `service_role` key anywhere in this file — that one
   must never appear in client-side code.

---

## B. Add your keys to index.html (~1 min)

Open `index.html` in any text editor and find this block near the top of
the first `<script>` section:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_PROJECT_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace the two placeholder strings with the values you copied in step
A.4, save the file. That's the only edit required.

Optional: once the site is live, log into **Organiser Login** →
**Settings** and enter your UPI ID there instead of hardcoding it — this
is what generates the live payment QR code on the registration form, and
you can change it any time without touching the code. You can also
upload an actual bank-issued QR image there instead of using the
generated one, if that proves more reliable for your bank/UPI app.

---

## C. Put it on Render (~5 min)

Render deploys static sites from a **Git repository** — there's no drag-and-drop
upload, so the file needs to live on GitHub (or GitLab/Bitbucket) first.

### Step 1 — Push the files to GitHub
1. Go to github.com → **New repository** (e.g. `prateek-laurel-sports-fest`).
   Keep it public or private, either works.
2. Upload `index.html` to that repo — easiest way: on the repo's GitHub
   page, click **Add file → Upload files**, drag `index.html` in, and
   commit. (You don't need to upload `supabase-schema.sql` or this
   README — they're just for your reference.)

### Step 2 — Connect Render
1. Go to render.com and sign in.
2. **New → Static Site**.
3. Connect your GitHub account if prompted, then select the repo you
   just created.
4. Leave **Build Command** blank and set **Publish Directory** to `.`
   (a single dot — it just means "the root of the repo").
5. Click **Create Static Site**. Render will give you a URL like
   `https://prateek-laurel-sports-fest.onrender.com` within a minute or two.

### Step 3 (optional) — Custom domain
If your society has a domain, Render's **Settings → Custom Domain** on
that same static site lets you point something like
`sportsfest.prateeklaurel.in` at it — follow the DNS instructions Render
shows you there.

---

## How the pieces fit together

| Feature | Where it lives |
|---|---|
| Site pages (Home, Sports, Register, etc.) | `index.html`, served by Render |
| Registrations, updates, fixtures, sponsors, photos | Supabase database tables |
| Fixtures boards, per sport/category/event/gender | `fixture_boards` table + Supabase Storage (public) |
| Payment screenshots | Supabase Storage (`payment-screenshots` bucket, private) |
| Player photos (Basketball Open auction) | Supabase Storage (`player-photos` bucket, private) |
| Sponsor logos & event photos | Supabase Storage (public buckets) |
| Organiser login | Supabase Auth (email + password, no public sign-up) |
| Payment QR code | Generated live from the UPI ID in Admin → Settings, or an uploaded bank QR image if you prefer |
| Registration open/close control | `category_status` table — close or schedule an auto-close per category from Admin → Registration Status, no redeploy needed |
| Live match scoring (Basketball) | `matches` + `score_events` tables — Admin → Live Scoring sets up a match and generates a no-login scorer link; anyone can watch a live scoreboard at `#livescore` |
| Site analytics | `analytics_events` table — anonymous, browser-ID based, Admin → Site Analytics |

## Updating the site later
Any time you want to change the sport rules, timeline copy, or styling,
edit `index.html` and re-upload it to the same GitHub repo (or `git push`
if you're using Git locally) — Render redeploys automatically within a
minute of any push to the connected branch.

If a change also needs a database update (a new table or column), that's
a separate step: run the relevant SQL directly in Supabase's SQL Editor.
Keep `supabase-schema.sql` in this repo up to date as you go, so it stays
a true reflection of what's actually in your database — it's meant to be
the one file you can hand to a future collaborator (or yourself, months
later) to fully reconstruct the database from scratch.

## A note on security
The admin passcode from the earlier version is gone — admin access is now
real Supabase authentication, and the database rules (Row Level Security)
enforce that only logged-in organisers can approve registrations or edit
content, even if someone tries to call the API directly. Participant
phone numbers aren't publicly queryable; the "check my status" feature
uses a locked-down lookup function instead of open table access.

Two features are a deliberate exception to this, worth knowing about:
live match scores and the no-login scorer link both work by letting
anyone with the right link write to the `matches` and `score_events`
tables without being logged in — this keeps event-day scoring simple
(no accounts for volunteers to juggle), at the cost of real access
control on those two tables specifically. Treat this as a low-stakes,
convenience-over-security tradeoff appropriate for a friendly community
event, not a pattern to copy for anything sensitive.

## A note on testing while logged in as an organiser
Supabase Auth sessions are stored in the browser and shared across every
tab of that browser profile. If you log into **Organiser Login** and then
test the public Register form in another tab of the *same* browser, your
submission goes through as that logged-in organiser, not as an anonymous
visitor — which uses a different set of database permissions. The schema
grants both roles what they need, so this should work either way, but if
you ever see a permissions-flavoured error while testing, try the same
action in an Incognito/Private window (or a different browser) first to
rule out a leftover login session before assuming something's broken.
