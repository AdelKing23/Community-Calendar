-- t257_001 rollback: restore originals, drop new trigger + function
drop trigger if exists ab_require_active_subscription on public.events;
drop trigger if exists ab_require_active_subscription on public.member_notices;
drop function if exists public.require_active_subscription_for_create();

CREATE OR REPLACE FUNCTION public.listing_allowance_for(p_business_id uuid)
 RETURNS TABLE(period_start timestamp with time zone, period_end timestamp with time zone, allowance integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.current_period_start,
         s.current_period_end,
         coalesce(s.active_listing_limit,
                  case s.plan_id when 'local_business' then 1 when 'growth' then 4 when 'sponsor' then 8 else 0 end)
  from public.business_subscriptions s
  where s.business_profile_id = p_business_id
    and s.status in ('active', 'trialing')   -- same set as live member_profile_has_active_subscription (read 15 Nov);
                                              -- sync function also writes cancelled/expired/past_due/revoked
    and (s.current_period_end is null or s.current_period_end > now())
  order by coalesce(s.active_listing_limit, 0) desc, s.current_period_end desc nulls last
  limit 1
$function$;

CREATE OR REPLACE FUNCTION public.member_profile_has_active_subscription(p_business_profile_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.business_subscriptions bs
    where bs.business_profile_id = p_business_profile_id
      and bs.status in ('active', 'trialing')
      and (
        bs.current_period_end is null
        or bs.current_period_end > now()
      )
  );
$function$;

