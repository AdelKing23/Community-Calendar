-- t257_001: Isaac (18 Nov): no grace period. From the subscription end date (current_period_end) nothing
-- can be created; once paid (active/trialing with a new period end in the future) creating resumes.
-- A subscription with no end date no longer counts as active.

create or replace function public.member_profile_has_active_subscription(p_business_profile_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select exists (
    select 1
    from public.business_subscriptions bs
    where bs.business_profile_id = p_business_profile_id
      and bs.status in ('active', 'trialing')
      and bs.current_period_end is not null
      and bs.current_period_end > now()
  );
$function$;

create or replace function public.listing_allowance_for(p_business_id uuid)
 returns table(period_start timestamp with time zone, period_end timestamp with time zone, allowance integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select s.current_period_start,
         s.current_period_end,
         coalesce(s.active_listing_limit,
                  case s.plan_id when 'local_business' then 1 when 'growth' then 4 when 'sponsor' then 8 else 0 end)
  from public.business_subscriptions s
  where s.business_profile_id = p_business_id
    and s.status in ('active', 'trialing')
    and s.current_period_end is not null
    and s.current_period_end > now()   -- t257: no grace period
  order by coalesce(s.active_listing_limit, 0) desc, s.current_period_end desc
  limit 1
$function$;

-- One gate for every organisation create (listings, org calendar items, polls, notices).
create or replace function public.require_active_subscription_for_create()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_profile uuid;
  v_had_any boolean;
begin
  if auth.uid() is null or coalesce(auth.role(), '') = 'service_role' or public.current_user_is_support() then
    return new;
  end if;

  v_profile := new.business_profile_id;
  if v_profile is null then
    select bp.id into v_profile from public.business_profiles bp
     where bp.owner_user_id = auth.uid() and bp.status = 'approved'
     order by bp.approved_at desc nulls last limit 1;
  end if;
  if v_profile is null then
    return new; -- not an organisation create; existing policies decide
  end if;

  if public.member_profile_has_active_subscription(v_profile) then
    return new;
  end if;

  select exists (select 1 from public.business_subscriptions s where s.business_profile_id = v_profile
                 and s.status not in ('pending')) into v_had_any;
  if v_had_any then
    raise exception using errcode = 'P0001', message = 'subscription_ended',
      hint = 'Your subscription has ended. Renew to keep creating.';
  else
    raise exception using errcode = 'P0001', message = 'subscription_required',
      hint = 'An active subscription is needed to create. Choose a plan to start creating.';
  end if;
end;
$function$;

revoke all on function public.require_active_subscription_for_create() from public, anon, authenticated;

drop trigger if exists ab_require_active_subscription on public.events;
create trigger ab_require_active_subscription before insert on public.events
  for each row execute function public.require_active_subscription_for_create();

drop trigger if exists ab_require_active_subscription on public.member_notices;
create trigger ab_require_active_subscription before insert on public.member_notices
  for each row execute function public.require_active_subscription_for_create();
