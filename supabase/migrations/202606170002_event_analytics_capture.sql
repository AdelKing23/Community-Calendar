-- Real event analytics capture
-- Stores raw analytics events and rolls them into event_analytics_daily.

begin;

alter table public.event_analytics_daily
  add column if not exists poll_answers integer not null default 0,
  add column if not exists promotion_impressions integer not null default 0;

create table if not exists public.event_analytics_events (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  actor_id uuid default auth.uid() references auth.users(id) on delete set null,
  session_id text,
  event_type text not null,
  source text,
  location_scope_slug text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint event_analytics_events_type_check
    check (
      event_type in (
        'impression',
        'detail_view',
        'interested',
        'going',
        'save',
        'share',
        'poll_answer',
        'promotion_impression'
      )
    ),
  constraint event_analytics_events_metadata_shape_check
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists event_analytics_events_event_time_idx
on public.event_analytics_events (event_id, occurred_at desc);

create index if not exists event_analytics_events_type_time_idx
on public.event_analytics_events (event_type, occurred_at desc);

create index if not exists event_analytics_events_actor_time_idx
on public.event_analytics_events (actor_id, occurred_at desc)
where actor_id is not null;

alter table public.event_analytics_events enable row level security;

drop policy if exists "Owner can read all analytics events" on public.event_analytics_events;
create policy "Owner can read all analytics events"
on public.event_analytics_events
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can read raw analytics for own listings" on public.event_analytics_events;
create policy "Users can read raw analytics for own listings"
on public.event_analytics_events
for select
to authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_analytics_events.event_id
      and e.submitted_by = auth.uid()
  )
);

create or replace function public.record_event_analytics(
  p_event_id uuid,
  p_event_type text,
  p_source text default null,
  p_location_scope_slug text default null,
  p_session_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  analytics_day date := current_date;
begin
  if p_event_type not in (
    'impression',
    'detail_view',
    'interested',
    'going',
    'save',
    'share',
    'poll_answer',
    'promotion_impression'
  ) then
    raise exception 'Unsupported analytics event type: %', p_event_type;
  end if;

  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Analytics metadata must be a JSON object';
  end if;

  if not exists (select 1 from public.events e where e.id = p_event_id) then
    raise exception 'Unknown event id: %', p_event_id;
  end if;

  insert into public.event_analytics_events (
    event_id,
    actor_id,
    session_id,
    event_type,
    source,
    location_scope_slug,
    metadata
  )
  values (
    p_event_id,
    auth.uid(),
    nullif(trim(coalesce(p_session_id, '')), ''),
    p_event_type,
    nullif(trim(coalesce(p_source, '')), ''),
    nullif(trim(coalesce(p_location_scope_slug, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  );

  insert into public.event_analytics_daily (
    event_id,
    day,
    impressions,
    detail_views,
    interested_taps,
    going_taps,
    save_taps,
    share_taps,
    poll_answers,
    promotion_impressions
  )
  values (
    p_event_id,
    analytics_day,
    case when p_event_type = 'impression' then 1 else 0 end,
    case when p_event_type = 'detail_view' then 1 else 0 end,
    case when p_event_type = 'interested' then 1 else 0 end,
    case when p_event_type = 'going' then 1 else 0 end,
    case when p_event_type = 'save' then 1 else 0 end,
    case when p_event_type = 'share' then 1 else 0 end,
    case when p_event_type = 'poll_answer' then 1 else 0 end,
    case when p_event_type = 'promotion_impression' then 1 else 0 end
  )
  on conflict (event_id, day)
  do update set
    impressions = public.event_analytics_daily.impressions + excluded.impressions,
    detail_views = public.event_analytics_daily.detail_views + excluded.detail_views,
    interested_taps = public.event_analytics_daily.interested_taps + excluded.interested_taps,
    going_taps = public.event_analytics_daily.going_taps + excluded.going_taps,
    save_taps = public.event_analytics_daily.save_taps + excluded.save_taps,
    share_taps = public.event_analytics_daily.share_taps + excluded.share_taps,
    poll_answers = public.event_analytics_daily.poll_answers + excluded.poll_answers,
    promotion_impressions = public.event_analytics_daily.promotion_impressions + excluded.promotion_impressions,
    updated_at = now();
end;
$$;

grant execute on function public.record_event_analytics(uuid, text, text, text, text, jsonb) to anon, authenticated;

commit;
