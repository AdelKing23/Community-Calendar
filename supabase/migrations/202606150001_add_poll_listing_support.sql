-- Add poll listing support
-- Migration: 202606150001_add_poll_listing_support
--
-- Polls are stored as a listing kind on events so they can keep using the
-- existing review, image, location, and public feed systems. Responses live in
-- their own table so voting/feedback can be added without changing event rows.

begin;

create or replace function public.poll_options_are_valid(options jsonb)
returns boolean
language sql
immutable
as $$
  select
    jsonb_typeof(coalesce(options, '[]'::jsonb)) = 'array'
    and jsonb_array_length(coalesce(options, '[]'::jsonb)) between 2 and 10
    and not coalesce(
      (
        select bool_or(length(trim(option_value)) = 0)
        from jsonb_array_elements_text(coalesce(options, '[]'::jsonb)) as option_values(option_value)
      ),
      true
    )
$$;

alter table public.events
  add column if not exists listing_kind text not null default 'event',
  add column if not exists poll_question text,
  add column if not exists poll_options jsonb not null default '[]'::jsonb,
  add column if not exists poll_allows_custom_answer boolean not null default false;

alter table public.events
  drop constraint if exists events_listing_kind_check,
  add constraint events_listing_kind_check
    check (listing_kind in ('event', 'poll'));

alter table public.events
  drop constraint if exists events_poll_shape_check,
  add constraint events_poll_shape_check
    check (
      (
        listing_kind = 'event'
        and poll_question is null
        and poll_options = '[]'::jsonb
        and poll_allows_custom_answer = false
      )
      or
      (
        listing_kind = 'poll'
        and poll_question is not null
        and length(trim(poll_question)) > 0
        and public.poll_options_are_valid(poll_options)
      )
    );

create table if not exists public.event_poll_responses (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  respondent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  selected_option text,
  custom_answer text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_poll_responses_answer_check
    check (
      (
        selected_option is not null
        and length(trim(selected_option)) > 0
        and custom_answer is null
      )
      or
      (
        selected_option is null
        and custom_answer is not null
        and length(trim(custom_answer)) > 0
        and length(custom_answer) <= 250
      )
    ),
  constraint event_poll_responses_custom_answer_length_check
    check (custom_answer is null or length(custom_answer) <= 250),
  constraint event_poll_responses_one_response_per_user unique (event_id, respondent_id)
);

create index if not exists events_listing_kind_status_idx
on public.events (listing_kind, status, end_at);

create index if not exists event_poll_responses_event_id_idx
on public.event_poll_responses (event_id);

create index if not exists event_poll_responses_respondent_id_idx
on public.event_poll_responses (respondent_id);

drop trigger if exists set_event_poll_responses_updated_at on public.event_poll_responses;
create trigger set_event_poll_responses_updated_at
before update on public.event_poll_responses
for each row execute function public.set_updated_at();

alter table public.event_poll_responses enable row level security;

drop policy if exists "Owner can read all poll responses" on public.event_poll_responses;
create policy "Owner can read all poll responses"
on public.event_poll_responses
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = 'isaacwellis@hotmail.com');

drop policy if exists "Users can read own poll responses" on public.event_poll_responses;
create policy "Users can read own poll responses"
on public.event_poll_responses
for select
to authenticated
using (respondent_id = auth.uid());

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
      and e.listing_kind = 'poll'
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
      and e.listing_kind = 'poll'
      and (
        event_poll_responses.selected_option is null
        or event_poll_responses.selected_option in (
          select jsonb_array_elements_text(e.poll_options)
        )
      )
      and (
        event_poll_responses.custom_answer is null
        or e.poll_allows_custom_answer = true
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
      and e.listing_kind = 'poll'
      and (
        event_poll_responses.selected_option is null
        or event_poll_responses.selected_option in (
          select jsonb_array_elements_text(e.poll_options)
        )
      )
      and (
        event_poll_responses.custom_answer is null
        or e.poll_allows_custom_answer = true
      )
  )
);

commit;
