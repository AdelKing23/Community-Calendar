# Community Calendar payment tier and analytics backend plan

Status: draft only. Do not run until reviewed.

The current Swift sandbox uses existing safe fields so the app keeps building and existing listing submission still works. A full production loop needs the backend to store listing tier, payment state, review flags, and aggregate analytics.

## Proposed columns for `public.events`

```sql
alter table public.events
  add column if not exists listing_tier text not null default 'community_free',
  add column if not exists payment_status text not null default 'not_required',
  add column if not exists payment_required boolean not null default false,
  add column if not exists review_flags text[] not null default '{}'::text[],
  add column if not exists promotion_expires_at timestamptz;

alter table public.events
  drop constraint if exists events_listing_tier_check,
  add constraint events_listing_tier_check
  check (listing_tier in ('community_free', 'commercial_standard', 'boost', 'boost_insights'));

alter table public.events
  drop constraint if exists events_payment_status_check,
  add constraint events_payment_status_check
  check (payment_status in ('not_required', 'required', 'pending', 'paid', 'failed', 'refunded', 'waived'));

create index if not exists events_listing_tier_status_idx
on public.events (listing_tier, status, created_at desc);

create index if not exists events_payment_status_idx
on public.events (payment_status, status, created_at desc);
```

## Proposed analytics table

```sql
create table if not exists public.event_analytics_daily (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  day date not null default current_date,
  impressions integer not null default 0,
  detail_views integer not null default 0,
  interested_taps integer not null default 0,
  going_taps integer not null default 0,
  save_taps integer not null default 0,
  share_taps integer not null default 0,
  directions_taps integer not null default 0,
  call_taps integer not null default 0,
  website_taps integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, day)
);

create index if not exists event_analytics_daily_event_day_idx
on public.event_analytics_daily (event_id, day desc);

alter table public.event_analytics_daily enable row level security;
```

## Intended RLS

- Public users should not see raw analytics rows.
- Signed-in listing owners can read analytics for their own listings.
- Support can read all analytics.
- Client-side anonymous writes should not be used for trusted analytics long-term.
- MVP tracking can start with app-side aggregate calls later, but stronger production tracking should use a Supabase Edge Function or server-side RPC to avoid easy counter abuse.

## Product loop

- `community_free`: no payment required, normal placement, basic analytics.
- `commercial_standard`: payment required before commercial listing is approved.
- `boost`: payment required, then Support/payment automation can set featured placement.
- `boost_insights`: payment required, featured/top placement plus deeper graph/reporting.

## StoreKit/Stripe note

- In-app listing boosts/promotions should use StoreKit where Apple requires in-app purchase.
- Stripe is still useful later for external event tickets, organiser invoices, sponsor invoices, and website checkout.
- No Stripe secret key or StoreKit shared secret should ever be stored in the iPhone app.

Prepared StoreKit product IDs:

- `communitycalendar.commercial.standard` for Commercial $5
- `communitycalendar.boost.standard` for Boost $10
- `communitycalendar.boost.insights` for Boost + Insights $15

The Swift sandbox now has a dormant StoreKit 2 service for loading products, starting a transaction listener, purchasing, and refreshing entitlements. It is intentionally not called from active listing submission yet. Before live payments, App Store Connect products, payment status storage, transaction verification, and the listing approval/payment loop need to be connected and tested.
