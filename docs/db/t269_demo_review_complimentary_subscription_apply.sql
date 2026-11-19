-- t269: complimentary App Review demo organisation + subscription for the reviewer demo account only.
-- Granted the way Support/service_role would: approved organisation (NOT published to the public directory)
-- and an active complimentary subscription (provider = 'complimentary_review', no Apple/Stripe ids), 90 days.
do $$
declare demo uuid := 'b64f22cb-5bf6-4e31-8901-d05815beb1b8'; org uuid; sub uuid;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  if exists (select 1 from public.business_profiles where owner_user_id = demo) then
    raise exception 'demo already has an organisation - stop';
  end if;
  insert into public.business_profiles(owner_user_id,business_name,contact_name,contact_email,about,area_scope_id,status,approved_at,organisation_type,selected_plan_id,support_note)
  values (demo,'App Review Demo Organisation','App Review',(select email from auth.users where id = demo),
          'Demo organisation for Apple App Review. Not shown in the public directory.','pohutukawa-coast','approved',now(),'community_group','growth',
          'COMPLIMENTARY APP REVIEW DEMO (t269): approved for Apple App Review only; not published; comp subscription 90 days. Remove after review.')
  returning id into org;
  insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
  values (org,demo,'growth','communitycalendar.business.growth.monthly',4,0,'active','complimentary_review',now(),now()+interval '90 days')
  returning id into sub;
  raise notice 'org=% sub=%', org, sub;
end $$;
select b.id as org_id, s.id as sub_id, s.status, s.provider, s.current_period_end from public.business_profiles b join public.business_subscriptions s on s.business_profile_id=b.id where b.owner_user_id='b64f22cb-5bf6-4e31-8901-d05815beb1b8';
