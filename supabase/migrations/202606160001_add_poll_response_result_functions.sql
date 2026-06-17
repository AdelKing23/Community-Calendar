-- Poll response result helpers
-- Keeps public poll cards anonymous while allowing poll owners/admins to review custom text.

begin;

create or replace function public.poll_response_counts_for_event(p_event_id uuid)
returns table(option_text text, response_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(r.selected_option, 'Other') as option_text,
    count(*)::bigint as response_count
  from public.event_poll_responses r
  join public.events e on e.id = r.event_id
  where r.event_id = p_event_id
    and e.status = 'published'::listing_status
    and e.end_at >= now()
    and (
      e.listing_kind = 'poll'
      or coalesce(e.long_description, '') like '%[POLL]%'
    )
  group by coalesce(r.selected_option, 'Other')
  order by response_count desc, option_text asc;
$$;

create or replace function public.poll_custom_responses_for_event(p_event_id uuid)
returns table(
  id uuid,
  custom_answer text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.custom_answer,
    r.created_at
  from public.event_poll_responses r
  join public.events e on e.id = r.event_id
  where r.event_id = p_event_id
    and r.custom_answer is not null
    and (
      e.submitted_by = auth.uid()
      or lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com'
    )
  order by r.created_at desc;
$$;

grant execute on function public.poll_response_counts_for_event(uuid) to anon, authenticated;
grant execute on function public.poll_custom_responses_for_event(uuid) to authenticated;

commit;
