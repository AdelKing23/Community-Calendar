-- Support submission RPC
-- Lets the app create support requests without exposing a personal email in UI.
-- Email delivery can be connected later by an Edge Function or webhook.

begin;

create or replace function public.submit_support_request(
  p_topic text,
  p_message text,
  p_listing_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to contact support';
  end if;

  if length(trim(coalesce(p_topic, ''))) = 0 then
    raise exception 'Support topic is required';
  end if;

  if length(trim(coalesce(p_message, ''))) < 5 then
    raise exception 'Support message is too short';
  end if;

  insert into public.support_requests (
    submitted_by,
    topic,
    listing_reference,
    message,
    status
  )
  values (
    auth.uid(),
    trim(p_topic),
    nullif(trim(coalesce(p_listing_reference, '')), ''),
    trim(p_message),
    'open'
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

grant execute on function public.submit_support_request(text, text, text) to authenticated;

commit;
