-- Current production schema baseline
-- Migration: 202606110000_current_schema_baseline
--
-- This captures the existing public schema shape before the later location seed
-- and organiser-specific migrations. It is intentionally schema-only: live event
-- rows, auth users, and storage objects are not included.

begin;

create extension if not exists pgcrypto;
create extension if not exists unaccent;
create extension if not exists pg_trgm;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'listing_status'
  ) then
    create type public.listing_status as enum (
      'pending_review',
      'published',
      'rejected',
      'archived'
    );
  end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.enforce_event_image_limit()
returns trigger
language plpgsql
as $$
begin
  if (
    select count(*)
    from public.event_images
    where event_id = new.event_id
  ) >= 5 then
    raise exception 'A listing can have a maximum of 5 images.';
  end if;

  return new;
end;
$$;

create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  cmd record;
begin
  for cmd in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
    if cmd.schema_name is not null
      and cmd.schema_name in ('public')
      and cmd.schema_name not in ('pg_catalog', 'information_schema')
      and cmd.schema_name not like 'pg_toast%'
      and cmd.schema_name not like 'pg_temp%' then
      begin
        execute format('alter table if exists %s enable row level security', cmd.object_identity);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
    else
      raise log 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
    end if;
  end loop;
end;
$$;

create or replace function public.location_normalize(value text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    lower(public.unaccent(coalesce(value, ''))),
    '[^a-z0-9]+',
    ' ',
    'g'
  )::text
$$;

create table if not exists public.location_scopes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  normalized_name text generated always as (public.location_normalize(name)) stored,
  scope_type text not null,
  subtitle text,
  source text not null default 'manual',
  source_id text,
  is_public boolean not null default true,
  is_selectable boolean not null default true,
  sort_priority integer not null default 1000,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint location_scopes_type_check
    check (scope_type in ('country', 'region', 'wider_area', 'community', 'place', 'venue'))
);

create table if not exists public.location_aliases (
  id uuid primary key default gen_random_uuid(),
  location_scope_id uuid not null references public.location_scopes(id) on delete cascade,
  alias text not null,
  normalized_alias text generated always as (public.location_normalize(alias)) stored,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  unique (location_scope_id, normalized_alias)
);

create table if not exists public.location_scope_links (
  child_scope_id uuid not null references public.location_scopes(id) on delete cascade,
  parent_scope_id uuid not null references public.location_scopes(id) on delete cascade,
  relationship_type text not null default 'widens_to',
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  primary key (child_scope_id, parent_scope_id, relationship_type),
  constraint location_scope_links_no_self_link
    check (child_scope_id <> parent_scope_id),
  constraint location_scope_links_relationship_check
    check (relationship_type in ('widens_to', 'contains', 'nearby', 'search_boost'))
);

create table if not exists public.location_import_staging (
  id bigint generated always as identity primary key,
  source text not null,
  source_id text,
  slug text not null,
  name text not null,
  scope_type text not null default 'place',
  subtitle text,
  parent_slug text,
  aliases text[] not null default '{}'::text[],
  is_public boolean not null default true,
  is_selectable boolean not null default true,
  sort_priority integer not null default 1000,
  imported_at timestamptz not null default now(),
  processed_at timestamptz,
  error text,
  constraint location_import_staging_scope_type_check
    check (scope_type in ('country', 'region', 'wider_area', 'community', 'place', 'venue'))
);

create table if not exists public.listing_topics (
  slug text primary key,
  label text not null,
  description text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null,
  town text not null,
  venue text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  price_label text not null default 'Free',
  is_free boolean not null default false,
  audience text not null default 'Everyone',
  short_description text not null,
  long_description text,
  contact_name text,
  contact_phone text,
  contact_email text,
  is_featured boolean not null default false,
  is_paid_push boolean not null default false,
  status public.listing_status not null default 'pending_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_by uuid default auth.uid() references auth.users(id) on delete set null,
  unverified_user_listing boolean not null default true,
  listing_tier text not null default 'community_free',
  payment_status text not null default 'not_required',
  payment_provider text,
  payment_reference text,
  analytics_level text not null default 'basic',
  review_flags text[] not null default '{}'::text[],
  promotion_expires_at timestamptz,
  primary_location_scope_id uuid references public.location_scopes(id),
  location_display_name text,
  location_visibility text not null default 'public_venue',
  constraint events_title_not_empty check (length(trim(title)) > 0),
  constraint events_category_not_empty check (length(trim(category)) > 0),
  constraint events_town_not_empty check (length(trim(town)) > 0),
  constraint events_venue_not_empty check (length(trim(venue)) > 0),
  constraint events_short_description_not_empty check (length(trim(short_description)) > 0),
  constraint events_start_before_end check (start_at < end_at),
  constraint events_end_after_start check (end_at >= start_at),
  constraint events_listing_tier_check
    check (listing_tier in ('community_free', 'commercial_5', 'boost_10', 'boost_insights_15')),
  constraint events_payment_status_check
    check (payment_status in ('not_required', 'required', 'pending', 'paid', 'failed', 'refunded', 'waived')),
  constraint events_analytics_level_check
    check (analytics_level in ('basic', 'boost', 'boost_insights')),
  constraint events_location_visibility_check
    check (location_visibility in ('public_venue', 'public_address', 'hidden_until_booked', 'online_only'))
);

create table if not exists public.event_images (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  storage_bucket text not null default 'listing-images',
  storage_path text not null unique,
  position integer not null,
  mime_type text not null default 'image/jpeg',
  byte_size integer,
  width integer,
  height integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_images_bucket_check check (storage_bucket = 'listing-images'),
  constraint event_images_position_check check (position >= 1 and position <= 5),
  constraint event_images_event_position_unique unique (event_id, position)
);

create table if not exists public.event_location_targets (
  event_id uuid not null references public.events(id) on delete cascade,
  location_scope_id uuid not null references public.location_scopes(id) on delete cascade,
  target_type text not null,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  primary key (event_id, location_scope_id),
  constraint event_location_targets_type_check
    check (target_type in ('primary', 'ancestor', 'manual_boost', 'nearby'))
);

create table if not exists public.event_topics (
  event_id uuid not null references public.events(id) on delete cascade,
  topic_slug text not null references public.listing_topics(slug),
  assigned_by uuid default auth.uid() references auth.users(id) on delete set null,
  source text not null default 'user',
  created_at timestamptz not null default now(),
  primary key (event_id, topic_slug),
  constraint event_topics_source_check check (source in ('user', 'system', 'support'))
);

create table if not exists public.event_change_requests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  change_type text not null,
  status text not null default 'pending',
  proposed_changes jsonb not null default '{}'::jsonb,
  requester_note text,
  support_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  review_reason text,
  constraint event_change_requests_change_type_check
    check (change_type in ('edit_request', 'removal_request')),
  constraint event_change_requests_status_check
    check (status in ('pending', 'approved', 'rejected', 'cancelled', 'applied')),
  constraint event_change_requests_proposed_changes_object_check
    check (jsonb_typeof(proposed_changes) = 'object'),
  constraint event_change_requests_review_reason_check
    check (
      review_reason is null
      or review_reason in (
        'approved_applied',
        'needs_payment',
        'inappropriate_wording',
        'inappropriate_image',
        'wrong_category',
        'wrong_date_time',
        'unclear_location',
        'duplicate_listing',
        'commercial_submitted_as_free',
        'promotion_upgrade_required',
        'not_enough_information',
        'other'
      )
    )
);

create table if not exists public.event_payment_records (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  purchased_by uuid references auth.users(id) on delete set null,
  provider text not null,
  product_id text,
  transaction_reference text,
  amount_cents integer,
  currency text not null default 'NZD',
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_payment_records_provider_check check (provider in ('apple_iap', 'stripe', 'manual')),
  constraint event_payment_records_status_check check (status in ('pending', 'paid', 'failed', 'refunded', 'waived'))
);

create table if not exists public.event_analytics_daily (
  event_id uuid not null references public.events(id) on delete cascade,
  day date not null,
  impressions integer not null default 0,
  detail_views integer not null default 0,
  interested_taps integer not null default 0,
  going_taps integer not null default 0,
  save_taps integer not null default 0,
  share_taps integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, day)
);

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid default auth.uid() references auth.users(id) on delete set null,
  topic text not null,
  listing_reference text,
  message text not null,
  status text not null default 'open',
  support_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_requests_status_check check (status in ('open', 'in_review', 'closed'))
);

create table if not exists public.user_event_engagements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  engagement_type text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, event_id, engagement_type),
  constraint user_event_engagements_engagement_type_check
    check (engagement_type in ('saved', 'interested', 'going'))
);

create or replace function public.location_ladder(start_scope_id uuid)
returns table (
  id uuid,
  slug text,
  name text,
  scope_type text,
  subtitle text,
  depth integer,
  sort_path integer[]
)
language sql
stable
as $$
  with recursive ladder as (
    select
      ls.id,
      ls.slug,
      ls.name,
      ls.scope_type,
      ls.subtitle,
      0 as depth,
      array[0]::integer[] as sort_path
    from public.location_scopes ls
    where ls.id = start_scope_id

    union all

    select
      parent.id,
      parent.slug,
      parent.name,
      parent.scope_type,
      parent.subtitle,
      ladder.depth + 1,
      ladder.sort_path || lsl.sort_order
    from ladder
    join public.location_scope_links lsl
      on lsl.child_scope_id = ladder.id
      and lsl.relationship_type = 'widens_to'
    join public.location_scopes parent
      on parent.id = lsl.parent_scope_id
    where ladder.depth < 12
  )
  select *
  from ladder
  order by sort_path, depth;
$$;

create or replace function public.search_location_scopes(search_text text, max_results integer default 20)
returns table (
  id uuid,
  slug text,
  name text,
  scope_type text,
  subtitle text,
  rank_score real
)
language sql
stable
as $$
  with query as (
    select public.location_normalize(search_text) as value
  )
  select
    lsi.id,
    lsi.slug,
    lsi.name,
    lsi.scope_type,
    lsi.subtitle,
    greatest(
      similarity(lsi.normalized_search_text, query.value),
      case when lsi.normalized_search_text like query.value || '%' then 1 else 0 end
    )::real as rank_score
  from public.location_search_index lsi, query
  where
    lsi.is_public
    and lsi.is_selectable
    and query.value <> ''
    and (
      lsi.normalized_search_text like '%' || query.value || '%'
      or similarity(lsi.normalized_search_text, query.value) > 0.25
    )
  order by rank_score desc, lsi.sort_priority asc, lsi.name asc
  limit greatest(1, least(coalesce(max_results, 20), 50));
$$;

create or replace function public.resolve_event_primary_location_from_town()
returns trigger
language plpgsql
as $$
begin
  if new.primary_location_scope_id is null and nullif(trim(coalesce(new.town, '')), '') is not null then
    select ls.id
    into new.primary_location_scope_id
    from public.location_scopes ls
    where ls.scope_type in ('place', 'community', 'wider_area', 'region')
      and ls.normalized_name = public.location_normalize(new.town)
    order by ls.sort_priority asc, ls.name asc
    limit 1;
  end if;

  if new.location_display_name is null then
    new.location_display_name = new.town;
  end if;

  return new;
end;
$$;

create or replace function public.refresh_event_location_targets(target_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  primary_scope uuid;
begin
  select primary_location_scope_id
  into primary_scope
  from public.events
  where id = target_event_id;

  delete from public.event_location_targets
  where event_id = target_event_id;

  if primary_scope is null then
    return;
  end if;

  insert into public.event_location_targets (event_id, location_scope_id, target_type, sort_order)
  select
    target_event_id,
    ladder.id,
    case when ladder.depth = 0 then 'primary' else 'ancestor' end,
    ladder.depth
  from public.location_ladder(primary_scope) ladder
  on conflict (event_id, location_scope_id)
  do update set
    target_type = excluded.target_type,
    sort_order = excluded.sort_order;
end;
$$;

create or replace function public.refresh_event_location_targets_trigger()
returns trigger
language plpgsql
as $$
begin
  perform public.refresh_event_location_targets(new.id);
  return new;
end;
$$;

create or replace view public.location_search_index as
select
  ls.id,
  ls.slug,
  ls.name,
  ls.scope_type,
  ls.subtitle,
  ls.sort_priority,
  ls.normalized_name as normalized_search_text,
  ls.is_public,
  ls.is_selectable
from public.location_scopes ls
where ls.is_public

union all

select
  ls.id,
  ls.slug,
  la.alias as name,
  ls.scope_type,
  ls.subtitle,
  ls.sort_priority + 10 as sort_priority,
  la.normalized_alias as normalized_search_text,
  ls.is_public,
  ls.is_selectable
from public.location_aliases la
join public.location_scopes ls on ls.id = la.location_scope_id
where ls.is_public;

create or replace view public.location_scope_edges as
select
  child.slug as child_slug,
  parent.slug as parent_slug,
  lsl.relationship_type,
  lsl.sort_order
from public.location_scope_links lsl
join public.location_scopes child on child.id = lsl.child_scope_id
join public.location_scopes parent on parent.id = lsl.parent_scope_id
where child.is_public
  and parent.is_public;

create or replace view public.location_alias_search_terms as
select
  ls.slug as location_slug,
  la.alias,
  la.normalized_alias,
  la.source
from public.location_aliases la
join public.location_scopes ls on ls.id = la.location_scope_id
where ls.is_public;

create or replace view public.published_event_location_targets as
select
  elt.event_id,
  ls.slug as location_slug,
  elt.target_type,
  elt.sort_order
from public.event_location_targets elt
join public.location_scopes ls on ls.id = elt.location_scope_id
join public.events e on e.id = elt.event_id
where ls.is_public
  and e.status = 'published'
  and e.end_at >= now();

create index if not exists event_change_requests_event_id_idx
on public.event_change_requests (event_id);

create index if not exists event_change_requests_requested_by_idx
on public.event_change_requests (requested_by);

create index if not exists event_change_requests_status_created_idx
on public.event_change_requests (status, created_at desc);

create index if not exists event_change_requests_type_status_idx
on public.event_change_requests (change_type, status);

create index if not exists event_images_event_position_idx
on public.event_images (event_id, position);

create index if not exists event_images_uploaded_by_idx
on public.event_images (uploaded_by);

create index if not exists event_location_targets_scope_idx
on public.event_location_targets (location_scope_id, sort_order, event_id);

create index if not exists event_topics_event_idx
on public.event_topics (event_id);

create index if not exists event_topics_topic_idx
on public.event_topics (topic_slug);

create index if not exists events_featured_feed_idx
on public.events (status, is_paid_push desc, is_featured desc, start_at);

create index if not exists events_featured_idx
on public.events (status, is_paid_push, is_featured, start_at);

create index if not exists events_listing_tier_status_idx
on public.events (listing_tier, status, start_at);

create index if not exists events_payment_status_idx
on public.events (payment_status, created_at desc);

create index if not exists events_primary_location_scope_idx
on public.events (primary_location_scope_id, status, start_at);

create index if not exists events_public_feed_idx
on public.events (status, end_at, start_at);

create index if not exists events_public_organiser_upcoming_idx
on public.events (submitted_by, end_at, start_at)
where status = 'published'
  and submitted_by is not null;

create index if not exists events_submitted_by_status_created_idx
on public.events (submitted_by, status, created_at desc);

create index if not exists location_scopes_slug_idx
on public.location_scopes (slug);

create index if not exists location_scopes_selectable_idx
on public.location_scopes (scope_type, is_public, is_selectable, sort_priority, name);

create index if not exists location_scopes_normalized_trgm_idx
on public.location_scopes using gin (normalized_name gin_trgm_ops);

create index if not exists location_aliases_normalized_trgm_idx
on public.location_aliases using gin (normalized_alias gin_trgm_ops);

create index if not exists location_scope_links_child_idx
on public.location_scope_links (child_scope_id, sort_order);

create index if not exists location_scope_links_parent_idx
on public.location_scope_links (parent_scope_id, sort_order);

drop trigger if exists set_event_analytics_daily_updated_at on public.event_analytics_daily;
create trigger set_event_analytics_daily_updated_at
before update on public.event_analytics_daily
for each row execute function public.set_updated_at();

drop trigger if exists set_event_change_requests_updated_at on public.event_change_requests;
create trigger set_event_change_requests_updated_at
before update on public.event_change_requests
for each row execute function public.set_updated_at();

drop trigger if exists enforce_event_image_limit on public.event_images;
create trigger enforce_event_image_limit
before insert on public.event_images
for each row execute function public.enforce_event_image_limit();

drop trigger if exists set_event_images_updated_at on public.event_images;
create trigger set_event_images_updated_at
before update on public.event_images
for each row execute function public.set_updated_at();

drop trigger if exists set_event_payment_records_updated_at on public.event_payment_records;
create trigger set_event_payment_records_updated_at
before update on public.event_payment_records
for each row execute function public.set_updated_at();

drop trigger if exists resolve_event_primary_location_from_town_on_events on public.events;
create trigger resolve_event_primary_location_from_town_on_events
before insert or update of town, primary_location_scope_id on public.events
for each row execute function public.resolve_event_primary_location_from_town();

drop trigger if exists refresh_event_location_targets_on_events on public.events;
create trigger refresh_event_location_targets_on_events
after insert or update of primary_location_scope_id on public.events
for each row execute function public.refresh_event_location_targets_trigger();

drop trigger if exists set_events_updated_at on public.events;
create trigger set_events_updated_at
before update on public.events
for each row execute function public.set_updated_at();

drop trigger if exists set_listing_topics_updated_at on public.listing_topics;
create trigger set_listing_topics_updated_at
before update on public.listing_topics
for each row execute function public.set_updated_at();

drop trigger if exists set_support_requests_updated_at on public.support_requests;
create trigger set_support_requests_updated_at
before update on public.support_requests
for each row execute function public.set_updated_at();

drop trigger if exists set_user_event_engagements_updated_at on public.user_event_engagements;
create trigger set_user_event_engagements_updated_at
before update on public.user_event_engagements
for each row execute function public.set_updated_at();

alter table public.event_analytics_daily enable row level security;
alter table public.event_change_requests enable row level security;
alter table public.event_images enable row level security;
alter table public.event_location_targets enable row level security;
alter table public.event_payment_records enable row level security;
alter table public.event_topics enable row level security;
alter table public.events enable row level security;
alter table public.listing_topics enable row level security;
alter table public.location_aliases enable row level security;
alter table public.location_import_staging enable row level security;
alter table public.location_scope_links enable row level security;
alter table public.location_scopes enable row level security;
alter table public.support_requests enable row level security;
alter table public.user_event_engagements enable row level security;

drop policy if exists "Owner can read all analytics" on public.event_analytics_daily;
create policy "Owner can read all analytics"
on public.event_analytics_daily
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can read analytics for own listings" on public.event_analytics_daily;
create policy "Users can read analytics for own listings"
on public.event_analytics_daily
for select
to authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_analytics_daily.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Owner can read all event change requests" on public.event_change_requests;
create policy "Owner can read all event change requests"
on public.event_change_requests
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Owner can update event change requests" on public.event_change_requests;
create policy "Owner can update event change requests"
on public.event_change_requests
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can create own event change requests" on public.event_change_requests;
create policy "Users can create own event change requests"
on public.event_change_requests
for insert
to authenticated
with check (
  requested_by = auth.uid()
  and status = 'pending'
  and reviewed_by is null
  and reviewed_at is null
  and applied_at is null
  and exists (
    select 1
    from public.events e
    where e.id = event_change_requests.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Users can read own event change requests" on public.event_change_requests;
create policy "Users can read own event change requests"
on public.event_change_requests
for select
to authenticated
using (requested_by = auth.uid());

drop policy if exists "Owner can read all event images" on public.event_images;
create policy "Owner can read all event images"
on public.event_images
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Public can read images for published events" on public.event_images;
create policy "Public can read images for published events"
on public.event_images
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_images.event_id
      and e.status = 'published'
      and e.end_at >= now()
  )
);

drop policy if exists "Users can add images to own pending listings" on public.event_images;
create policy "Users can add images to own pending listings"
on public.event_images
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and storage_bucket = 'listing-images'
  and exists (
    select 1
    from public.events e
    where e.id = event_images.event_id
      and e.submitted_by = auth.uid()
      and e.status = 'pending_review'
  )
);

drop policy if exists "Users can read images for own listings" on public.event_images;
create policy "Users can read images for own listings"
on public.event_images
for select
to authenticated
using (
  uploaded_by = auth.uid()
  or exists (
    select 1
    from public.events e
    where e.id = event_images.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Public can read event location targets" on public.event_location_targets;
create policy "Public can read event location targets"
on public.event_location_targets
for select
using (true);

drop policy if exists "Owner can read all payment records" on public.event_payment_records;
create policy "Owner can read all payment records"
on public.event_payment_records
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can read own payment records" on public.event_payment_records;
create policy "Users can read own payment records"
on public.event_payment_records
for select
to authenticated
using (
  purchased_by = auth.uid()
  or exists (
    select 1
    from public.events e
    where e.id = event_payment_records.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Owner can manage all event topics" on public.event_topics;
create policy "Owner can manage all event topics"
on public.event_topics
for all
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Public can read topics for published events" on public.event_topics;
create policy "Public can read topics for published events"
on public.event_topics
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_topics.event_id
      and e.status = 'published'
      and e.end_at >= now()
  )
);

drop policy if exists "Users can add topics to own pending listings" on public.event_topics;
create policy "Users can add topics to own pending listings"
on public.event_topics
for insert
to authenticated
with check (
  assigned_by = auth.uid()
  and exists (
    select 1
    from public.events e
    where e.id = event_topics.event_id
      and e.submitted_by = auth.uid()
      and e.status = 'pending_review'
  )
);

drop policy if exists "Users can read topics for own listings" on public.event_topics;
create policy "Users can read topics for own listings"
on public.event_topics
for select
to authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_topics.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Authenticated users can read own listings" on public.events;
create policy "Authenticated users can read own listings"
on public.events
for select
to authenticated
using (submitted_by = auth.uid());

drop policy if exists "Authenticated users can submit own pending listings" on public.events;
create policy "Authenticated users can submit own pending listings"
on public.events
for insert
to authenticated
with check (
  submitted_by = auth.uid()
  and status = 'pending_review'
  and is_featured = false
  and is_paid_push = false
  and unverified_user_listing = true
);

drop policy if exists "Owner can read all events" on public.events;
create policy "Owner can read all events"
on public.events
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Owner can update events" on public.events;
create policy "Owner can update events"
on public.events
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Public can read published current and future events" on public.events;
create policy "Public can read published current and future events"
on public.events
for select
to anon, authenticated
using (
  status = 'published'
  and end_at >= now()
);

drop policy if exists "Public can read active listing topics" on public.listing_topics;
create policy "Public can read active listing topics"
on public.listing_topics
for select
to anon, authenticated
using (active = true);

drop policy if exists "Public can read aliases for public locations" on public.location_aliases;
create policy "Public can read aliases for public locations"
on public.location_aliases
for select
using (
  exists (
    select 1
    from public.location_scopes ls
    where ls.id = location_aliases.location_scope_id
      and ls.is_public
  )
);

drop policy if exists "Only service role manages location imports" on public.location_import_staging;
create policy "Only service role manages location imports"
on public.location_import_staging
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists "Public can read public location links" on public.location_scope_links;
create policy "Public can read public location links"
on public.location_scope_links
for select
using (
  exists (
    select 1
    from public.location_scopes child
    join public.location_scopes parent on parent.id = location_scope_links.parent_scope_id
    where child.id = location_scope_links.child_scope_id
      and child.is_public
      and parent.is_public
  )
);

drop policy if exists "Public can read active location scopes" on public.location_scopes;
create policy "Public can read active location scopes"
on public.location_scopes
for select
using (is_public);

drop policy if exists "Owner can read support requests" on public.support_requests;
create policy "Owner can read support requests"
on public.support_requests
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Owner can update support requests" on public.support_requests;
create policy "Owner can update support requests"
on public.support_requests
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can create own support requests" on public.support_requests;
create policy "Users can create own support requests"
on public.support_requests
for insert
to authenticated
with check (
  submitted_by = auth.uid()
  and status = 'open'
);

drop policy if exists "Users can read own support requests" on public.support_requests;
create policy "Users can read own support requests"
on public.support_requests
for select
to authenticated
using (submitted_by = auth.uid());

drop policy if exists "Users manage own event engagements" on public.user_event_engagements;
create policy "Users manage own event engagements"
on public.user_event_engagements
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

commit;
