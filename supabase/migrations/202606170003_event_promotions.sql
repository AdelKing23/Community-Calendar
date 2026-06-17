-- Event promotion windows
-- Supports bounded paid boost placement instead of making a listing float near
-- the top until a far-future event date.

begin;

create table if not exists public.event_promotions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  purchased_by uuid default auth.uid() references auth.users(id) on delete set null,
  payment_record_id uuid references public.event_payment_records(id) on delete set null,
  tier text not null,
  placement text not null,
  status text not null default 'pending',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_promotions_tier_check
    check (tier in ('boost', 'boost_insights')),
  constraint event_promotions_placement_check
    check (placement in ('top_ten', 'priority_first')),
  constraint event_promotions_status_check
    check (status in ('pending', 'paid', 'active', 'expired', 'cancelled', 'refunded')),
  constraint event_promotions_window_check
    check (ends_at > starts_at),
  constraint event_promotions_duration_check
    check (
      (tier = 'boost' and ends_at <= starts_at + interval '3 days')
      or
      (tier = 'boost_insights' and ends_at <= starts_at + interval '7 days')
    )
);

create index if not exists event_promotions_event_id_idx
on public.event_promotions (event_id);

create index if not exists event_promotions_active_lookup_idx
on public.event_promotions (status, starts_at, ends_at, placement, paid_at);

create index if not exists event_promotions_purchased_by_idx
on public.event_promotions (purchased_by, created_at desc)
where purchased_by is not null;

drop trigger if exists set_event_promotions_updated_at on public.event_promotions;
create trigger set_event_promotions_updated_at
before update on public.event_promotions
for each row execute function public.set_updated_at();

alter table public.event_promotions enable row level security;

drop policy if exists "Owner can read all event promotions" on public.event_promotions;
create policy "Owner can read all event promotions"
on public.event_promotions
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can read own event promotions" on public.event_promotions;
create policy "Users can read own event promotions"
on public.event_promotions
for select
to authenticated
using (
  purchased_by = auth.uid()
  or exists (
    select 1
    from public.events e
    where e.id = event_promotions.event_id
      and e.submitted_by = auth.uid()
  )
);

drop policy if exists "Users can create pending promotions for own listings" on public.event_promotions;
create policy "Users can create pending promotions for own listings"
on public.event_promotions
for insert
to authenticated
with check (
  purchased_by = auth.uid()
  and status = 'pending'
  and exists (
    select 1
    from public.events e
    where e.id = event_promotions.event_id
      and e.submitted_by = auth.uid()
      and e.end_at > now()
  )
);

drop policy if exists "Owner can update event promotions" on public.event_promotions;
create policy "Owner can update event promotions"
on public.event_promotions
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

create or replace view public.active_event_promotions as
select
  ep.event_id,
  ep.tier,
  ep.placement,
  ep.starts_at,
  ep.ends_at,
  ep.paid_at,
  case ep.placement
    when 'priority_first' then 2
    when 'top_ten' then 1
    else 0
  end as placement_rank
from public.event_promotions ep
join public.events e on e.id = ep.event_id
where ep.status in ('paid', 'active')
  and ep.starts_at <= now()
  and ep.ends_at > now()
  and e.status = 'published'::listing_status
  and e.end_at > now();

create or replace function public.clamp_event_promotion_window(
  p_event_id uuid,
  p_tier text,
  p_requested_starts_at timestamptz default now(),
  p_requested_ends_at timestamptz default null
)
returns table(starts_at timestamptz, ends_at timestamptz, placement text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  event_end timestamptz;
  resolved_start timestamptz;
  max_duration interval;
begin
  select e.end_at into event_end
  from public.events e
  where e.id = p_event_id
    and e.end_at > now();

  if event_end is null then
    return;
  end if;

  if p_tier = 'boost' then
    max_duration := interval '3 days';
    placement := 'top_ten';
  elsif p_tier = 'boost_insights' then
    max_duration := interval '7 days';
    placement := 'priority_first';
  else
    return;
  end if;

  resolved_start := greatest(coalesce(p_requested_starts_at, now()), now());
  starts_at := resolved_start;
  ends_at := least(
    coalesce(p_requested_ends_at, resolved_start + max_duration),
    resolved_start + max_duration,
    event_end
  );

  if ends_at <= starts_at then
    return;
  end if;

  return next;
end;
$$;

grant select on public.active_event_promotions to anon, authenticated;
grant execute on function public.clamp_event_promotion_window(uuid, text, timestamptz, timestamptz) to authenticated;

commit;
