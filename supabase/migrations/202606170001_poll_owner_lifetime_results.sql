-- Poll owner lifetime results
-- Public poll cards keep using poll_response_counts_for_event, which only shows
-- active published polls. This owner/admin helper keeps results visible after a
-- poll closes, archives, or is reviewed later.

begin;

create or replace function public.poll_owner_response_counts_for_event(p_event_id uuid)
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
    and (
      e.submitted_by = auth.uid()
      or lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com'
    )
    and (
      e.listing_kind = 'poll'
      or coalesce(e.long_description, '') like '%[POLL]%'
    )
  group by coalesce(r.selected_option, 'Other')
  order by response_count desc, option_text asc;
$$;

grant execute on function public.poll_owner_response_counts_for_event(uuid) to authenticated;

commit;
