-- Poll response policy hardening
-- Allows responses for legacy/fallback polls stored in long_description [POLL] blocks.

begin;

create or replace function public.event_poll_option_values(
  p_poll_options jsonb,
  p_long_description text
)
returns table(option_text text)
language sql
immutable
set search_path = public
as $$
  select trim(option_value) as option_text
  from jsonb_array_elements_text(coalesce(p_poll_options, '[]'::jsonb)) as option_values(option_value)
  where jsonb_typeof(coalesce(p_poll_options, '[]'::jsonb)) = 'array'
    and jsonb_array_length(coalesce(p_poll_options, '[]'::jsonb)) > 0
    and length(trim(option_value)) > 0

  union

  select trim(matches[1]) as option_text
  from regexp_matches(
    coalesce(p_long_description, ''),
    '^\s*\d+\.\s*(.+?)\s*$',
    'gm'
  ) as matches
  where jsonb_array_length(coalesce(p_poll_options, '[]'::jsonb)) = 0
    and length(trim(matches[1])) > 0;
$$;

create or replace function public.event_allows_custom_poll_answer(
  p_poll_allows_custom_answer boolean,
  p_long_description text
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_poll_allows_custom_answer, false)
    or coalesce(p_long_description, '') ~* 'Custom answer:\s*Allowed';
$$;

drop policy if exists "Poll owners can read responses for own polls" on public.event_poll_responses;
create policy "Poll owners can read responses for own polls"
on public.event_poll_responses
for select
to authenticated
using (
  exists (
    select 1
    from public.events e
    where e.id = event_poll_responses.event_id
      and e.submitted_by = auth.uid()
      and (
        e.listing_kind = 'poll'
        or coalesce(e.long_description, '') like '%[POLL]%'
      )
  )
);

drop policy if exists "Authenticated users can answer published polls" on public.event_poll_responses;
create policy "Authenticated users can answer published polls"
on public.event_poll_responses
for insert
to authenticated
with check (
  respondent_id = auth.uid()
  and exists (
    select 1
    from public.events e
    where e.id = event_poll_responses.event_id
      and e.status = 'published'
      and e.end_at >= now()
      and (
        e.listing_kind = 'poll'
        or coalesce(e.long_description, '') like '%[POLL]%'
      )
      and (
        event_poll_responses.selected_option is null
        or event_poll_responses.selected_option in (
          select option_text
          from public.event_poll_option_values(e.poll_options, e.long_description)
        )
      )
      and (
        event_poll_responses.custom_answer is null
        or public.event_allows_custom_poll_answer(e.poll_allows_custom_answer, e.long_description)
      )
  )
);

drop policy if exists "Users can update own poll response" on public.event_poll_responses;
create policy "Users can update own poll response"
on public.event_poll_responses
for update
to authenticated
using (respondent_id = auth.uid())
with check (
  respondent_id = auth.uid()
  and exists (
    select 1
    from public.events e
    where e.id = event_poll_responses.event_id
      and e.status = 'published'
      and e.end_at >= now()
      and (
        e.listing_kind = 'poll'
        or coalesce(e.long_description, '') like '%[POLL]%'
      )
      and (
        event_poll_responses.selected_option is null
        or event_poll_responses.selected_option in (
          select option_text
          from public.event_poll_option_values(e.poll_options, e.long_description)
        )
      )
      and (
        event_poll_responses.custom_answer is null
        or public.event_allows_custom_poll_answer(e.poll_allows_custom_answer, e.long_description)
      )
  )
);

grant execute on function public.event_poll_option_values(jsonb, text) to anon, authenticated;
grant execute on function public.event_allows_custom_poll_answer(boolean, text) to anon, authenticated;

commit;
