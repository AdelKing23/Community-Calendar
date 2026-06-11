-- Community Calendar location scope system
-- Status: draft for review before running in Supabase.
--
-- Goal:
-- - Let users browse by a widening ladder: Maraetai -> Pōhutukawa Coast -> Franklin -> East Auckland -> Auckland -> New Zealand.
-- - Keep official/imported NZ place data in the backend without exposing council/statistical complexity to users.
-- - Make event filtering fast by precomputing every scope an event should appear in.
--
-- Import flow for all-NZ coverage:
-- 1. Run this file after review.
-- 2. Import LINZ/Stats/manual place rows into public.location_import_staging.
-- 3. Run public.promote_location_import_staging().
-- 4. Curate public.location_scope_links for the human widening ladders users actually see.

begin;

create extension if not exists pgcrypto;
create extension if not exists unaccent;
create extension if not exists pg_trgm;

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
  aliases text[] not null default '{}',
  is_public boolean not null default true,
  is_selectable boolean not null default true,
  sort_priority integer not null default 1000,
  imported_at timestamptz not null default now(),
  processed_at timestamptz,
  error text,
  constraint location_import_staging_scope_type_check
    check (scope_type in ('country', 'region', 'wider_area', 'community', 'place', 'venue'))
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

alter table public.events
  add column if not exists primary_location_scope_id uuid references public.location_scopes(id),
  add column if not exists location_display_name text,
  add column if not exists location_visibility text not null default 'public_venue';

alter table public.events
  drop constraint if exists events_location_visibility_check,
  add constraint events_location_visibility_check
  check (location_visibility in ('public_venue', 'public_address', 'hidden_until_booked', 'online_only'));

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

create index if not exists event_location_targets_scope_idx
on public.event_location_targets (location_scope_id, sort_order, event_id);

create index if not exists events_primary_location_scope_idx
on public.events (primary_location_scope_id, status, start_at);

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

drop trigger if exists resolve_event_primary_location_from_town_on_events on public.events;
create trigger resolve_event_primary_location_from_town_on_events
before insert or update of town, primary_location_scope_id on public.events
for each row
execute function public.resolve_event_primary_location_from_town();

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

drop trigger if exists refresh_event_location_targets_on_events on public.events;
create trigger refresh_event_location_targets_on_events
after insert or update of primary_location_scope_id on public.events
for each row
execute function public.refresh_event_location_targets_trigger();

create or replace function public.promote_location_import_staging()
returns table (processed_count integer, errored_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  processed_rows integer;
  bad_count integer;
begin
  update public.location_import_staging lis
  set error = null
  where processed_at is null;

  insert into public.location_scopes (
    slug,
    name,
    scope_type,
    subtitle,
    source,
    source_id,
    is_public,
    is_selectable,
    sort_priority
  )
  select
    lis.slug,
    lis.name,
    lis.scope_type,
    lis.subtitle,
    lis.source,
    lis.source_id,
    lis.is_public,
    lis.is_selectable,
    lis.sort_priority
  from public.location_import_staging lis
  where lis.processed_at is null
  on conflict (slug)
  do update set
    name = excluded.name,
    scope_type = excluded.scope_type,
    subtitle = excluded.subtitle,
    source = excluded.source,
    source_id = excluded.source_id,
    is_public = excluded.is_public,
    is_selectable = excluded.is_selectable,
    sort_priority = excluded.sort_priority,
    updated_at = now();

  insert into public.location_aliases (location_scope_id, alias, source)
  select
    ls.id,
    alias_value,
    lis.source
  from public.location_import_staging lis
  join public.location_scopes ls on ls.slug = lis.slug
  cross join lateral unnest(lis.aliases) alias_value
  where lis.processed_at is null
    and nullif(trim(alias_value), '') is not null
  on conflict (location_scope_id, normalized_alias) do nothing;

  insert into public.location_scope_links (child_scope_id, parent_scope_id, relationship_type, sort_order)
  select
    child.id,
    parent.id,
    'widens_to',
    100
  from public.location_import_staging lis
  join public.location_scopes child on child.slug = lis.slug
  join public.location_scopes parent on parent.slug = lis.parent_slug
  where lis.processed_at is null
    and lis.parent_slug is not null
  on conflict (child_scope_id, parent_scope_id, relationship_type) do nothing;

  update public.location_import_staging
  set processed_at = now()
  where processed_at is null;

  get diagnostics processed_rows = row_count;

  select count(*) into bad_count
  from public.location_import_staging
  where processed_at is null
    and error is not null;

  return query select processed_rows, bad_count;
end;
$$;

insert into public.location_scopes (slug, name, scope_type, subtitle, source, sort_priority)
values
  ('new-zealand', 'New Zealand', 'country', 'Everything currently listed', 'manual', 10000),
  ('northland', 'Northland', 'region', 'Northland listings and communities', 'manual', 9100),
  ('auckland', 'Auckland', 'region', 'Auckland listings and communities', 'manual', 9000),
  ('waikato', 'Waikato', 'region', 'Waikato listings and communities', 'manual', 9200),
  ('bay-of-plenty', 'Bay of Plenty', 'region', 'Bay of Plenty listings and communities', 'manual', 9300),
  ('gisborne', 'Gisborne', 'region', 'Gisborne listings and communities', 'manual', 9400),
  ('hawkes-bay', 'Hawke''s Bay', 'region', 'Hawke''s Bay listings and communities', 'manual', 9500),
  ('taranaki', 'Taranaki', 'region', 'Taranaki listings and communities', 'manual', 9600),
  ('manawatu-whanganui', 'Manawatu-Whanganui', 'region', 'Manawatu-Whanganui listings and communities', 'manual', 9700),
  ('wellington', 'Wellington', 'region', 'Wellington listings and communities', 'manual', 9800),
  ('tasman', 'Tasman', 'region', 'Tasman listings and communities', 'manual', 9900),
  ('nelson', 'Nelson', 'region', 'Nelson listings and communities', 'manual', 9910),
  ('marlborough', 'Marlborough', 'region', 'Marlborough listings and communities', 'manual', 9920),
  ('west-coast', 'West Coast', 'region', 'West Coast listings and communities', 'manual', 9930),
  ('canterbury', 'Canterbury', 'region', 'Canterbury listings and communities', 'manual', 9940),
  ('otago', 'Otago', 'region', 'Otago listings and communities', 'manual', 9950),
  ('southland', 'Southland', 'region', 'Southland listings and communities', 'manual', 9960),
  ('chatham-islands', 'Chatham Islands', 'region', 'Chatham Islands listings and communities', 'manual', 9970),
  ('east-auckland', 'East Auckland', 'wider_area', 'Widen toward nearby eastern communities', 'manual', 400),
  ('franklin', 'Franklin', 'wider_area', 'Widen to Franklin-side communities', 'manual', 300),
  ('pohutukawa-coast', 'Pōhutukawa Coast', 'community', 'Beachlands, Maraetai, Omana, Whitford, Clevedon and nearby coast', 'manual', 100),
  ('omana', 'Omana', 'place', 'Specific pocket between Beachlands and Maraetai', 'manual', 10),
  ('beachlands', 'Beachlands', 'place', 'Most local Beachlands listings', 'manual', 20),
  ('maraetai', 'Maraetai', 'place', 'Maraetai village, beach and nearby venues', 'manual', 30),
  ('whitford', 'Whitford', 'place', 'Whitford village and rural surrounds', 'manual', 40),
  ('clevedon', 'Clevedon', 'place', 'Clevedon village, markets and rural events', 'manual', 50),
  ('kawakawa-bay', 'Kawakawa Bay', 'place', 'Eastern coast listings near the bay', 'manual', 60),
  ('orere-point', 'Orere Point', 'place', 'Specific listings around Orere Point', 'manual', 70),
  ('hunua', 'Hunua', 'place', 'Hunua village and ranges-side events', 'manual', 80),
  ('ardmore', 'Ardmore', 'place', 'Ardmore and nearby Franklin listings', 'manual', 90)
on conflict (slug)
do update set
  name = excluded.name,
  scope_type = excluded.scope_type,
  subtitle = excluded.subtitle,
  sort_priority = excluded.sort_priority,
  updated_at = now();

insert into public.location_aliases (location_scope_id, alias, source)
select ls.id, alias_value, 'manual'
from public.location_scopes ls
join (
  values
    ('new-zealand', 'NZ'),
    ('new-zealand', 'Aotearoa'),
    ('auckland', 'Tamaki Makaurau'),
    ('pohutukawa-coast', 'Pohutukawa Coast'),
    ('pohutukawa-coast', 'Pōhutukawa Coast'),
    ('pohutukawa-coast', 'The Coast'),
    ('beachlands', 'Pine Harbour'),
    ('beachlands', 'Te Puru'),
    ('omana', 'Omana Beach'),
    ('maraetai', 'Maraetai Beach'),
    ('kawakawa-bay', 'Kawakawa'),
    ('orere-point', 'Orere')
) aliases(slug, alias_value)
  on aliases.slug = ls.slug
on conflict (location_scope_id, normalized_alias) do nothing;

insert into public.location_scope_links (child_scope_id, parent_scope_id, relationship_type, sort_order)
select child.id, parent.id, 'widens_to', link.sort_order
from (
  values
    ('omana', 'beachlands', 10),
    ('beachlands', 'pohutukawa-coast', 10),
    ('maraetai', 'pohutukawa-coast', 10),
    ('whitford', 'pohutukawa-coast', 10),
    ('clevedon', 'pohutukawa-coast', 10),
    ('kawakawa-bay', 'pohutukawa-coast', 10),
    ('orere-point', 'kawakawa-bay', 10),
    ('hunua', 'franklin', 10),
    ('ardmore', 'franklin', 10),
    ('pohutukawa-coast', 'franklin', 10),
    ('franklin', 'east-auckland', 10),
    ('east-auckland', 'auckland', 10),
    ('auckland', 'new-zealand', 10),
    ('northland', 'new-zealand', 100),
    ('waikato', 'new-zealand', 100),
    ('bay-of-plenty', 'new-zealand', 100),
    ('gisborne', 'new-zealand', 100),
    ('hawkes-bay', 'new-zealand', 100),
    ('taranaki', 'new-zealand', 100),
    ('manawatu-whanganui', 'new-zealand', 100),
    ('wellington', 'new-zealand', 100),
    ('tasman', 'new-zealand', 100),
    ('nelson', 'new-zealand', 100),
    ('marlborough', 'new-zealand', 100),
    ('west-coast', 'new-zealand', 100),
    ('canterbury', 'new-zealand', 100),
    ('otago', 'new-zealand', 100),
    ('southland', 'new-zealand', 100),
    ('chatham-islands', 'new-zealand', 100)
) link(child_slug, parent_slug, sort_order)
join public.location_scopes child on child.slug = link.child_slug
join public.location_scopes parent on parent.slug = link.parent_slug
on conflict (child_scope_id, parent_scope_id, relationship_type)
do update set sort_order = excluded.sort_order;

update public.events e
set primary_location_scope_id = ls.id,
    location_display_name = coalesce(e.location_display_name, e.town)
from public.location_scopes ls
where e.primary_location_scope_id is null
  and public.location_normalize(e.town) = ls.normalized_name;

insert into public.event_location_targets (event_id, location_scope_id, target_type, sort_order)
select e.id, ladder.id, case when ladder.depth = 0 then 'primary' else 'ancestor' end, ladder.depth
from public.events e
cross join lateral public.location_ladder(e.primary_location_scope_id) ladder
where e.primary_location_scope_id is not null
on conflict (event_id, location_scope_id)
do update set
  target_type = excluded.target_type,
  sort_order = excluded.sort_order;

alter table public.location_scopes enable row level security;
alter table public.location_aliases enable row level security;
alter table public.location_scope_links enable row level security;
alter table public.event_location_targets enable row level security;
alter table public.location_import_staging enable row level security;

drop policy if exists "Public can read active location scopes" on public.location_scopes;
create policy "Public can read active location scopes"
on public.location_scopes
for select
using (is_public);

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

drop policy if exists "Public can read event location targets" on public.event_location_targets;
create policy "Public can read event location targets"
on public.event_location_targets
for select
using (true);

drop policy if exists "Only service role manages location imports" on public.location_import_staging;
create policy "Only service role manages location imports"
on public.location_import_staging
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

commit;
