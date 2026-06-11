-- Public organiser event pages support
-- Migration: 202606110002_public_organiser_events
--
-- Lets the app fetch "what else this organiser has on" from public published
-- event data without needing a full public profile table yet.

begin;

alter table public.events
  add column if not exists submitted_by uuid references auth.users(id) on delete set null;

alter table public.events
  alter column submitted_by set default auth.uid();

create index if not exists events_public_organiser_upcoming_idx
  on public.events (submitted_by, end_at, start_at)
  where status = 'published'
    and submitted_by is not null;

commit;
