do $$
declare
  a uuid := gen_random_uuid(); s uuid := gen_random_uuid(); orgA uuid; subId uuid; r text := ''; ca text; cs text;
  procedure_dummy int;
begin
  insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values (a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-t257@example.invalid',now(),'{}','{}',now(),now()),
         (s,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-s-t257@example.invalid',now(),'{}','{}',now(),now());
  insert into public.support_users(user_id,email) values (s,'probe-s-t257@example.invalid');
  ca := json_build_object('sub',a,'role','authenticated','email','probe-a-t257@example.invalid')::text;
  cs := json_build_object('sub',s,'role','authenticated','email','probe-s-t257@example.invalid')::text;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.business_profiles(owner_user_id,business_name,organisation_type,contact_email,status,approved_at)
    values (a,'Probe Org t257','community_group','probe-a-t257@example.invalid','approved',now()) returning id into orgA;

  -- helper block repeated per case via a temp function is not allowed in DO; inline the 3 create paths
  for i in 1..6 loop
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    execute 'reset role';
    delete from public.business_subscriptions where business_profile_id = orgA;
    if i = 1 then r := r || E'\n[C1 no subscription ever]';
    elsif i = 2 then r := r || E'\n[C2 active, period ended 1 minute ago]';
      insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
      values (orgA,a,'growth','communitycalendar.business.growth.monthly',4,20,'active','apple',now()-interval '31 days',now()-interval '1 minute');
    elsif i = 3 then r := r || E'\n[C3 past_due, period end in future]';
      insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
      values (orgA,a,'growth','communitycalendar.business.growth.monthly',4,20,'past_due','stripe',now()-interval '1 day',now()+interval '29 days');
    elsif i = 4 then r := r || E'\n[C4 active, no end date]';
      insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
      values (orgA,a,'growth','communitycalendar.business.growth.monthly',4,20,'active','apple',now(),null);
    elsif i = 5 then r := r || E'\n[C5 renewed: active, new period ends in 30 days]';
      insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
      values (orgA,a,'growth','communitycalendar.business.growth.monthly',4,20,'active','apple',now(),now()+interval '30 days');
    else r := r || E'\n[C6 Support creates for org with ended sub]';
      insert into public.business_subscriptions(business_profile_id,owner_user_id,plan_id,product_id,active_listing_limit,placement_rank,status,provider,current_period_start,current_period_end)
      values (orgA,a,'growth','communitycalendar.business.growth.monthly',4,20,'cancelled','stripe',now()-interval '31 days',now()-interval '1 day');
    end if;

    perform set_config('request.jwt.claims', case when i=6 then cs else ca end, true); execute 'set local role authenticated';
    begin
      perform public.owner_insert_org_calendar_listing(orgA,'Probe item',now()+interval '2 days',null::timestamptz,'public','Beachlands',null::text,null::text,'Venue'::text,'Details'::text);
      r := r || ' orgcal=ALLOWED';
    exception when others then r := r || ' orgcal=DENIED(' || sqlerrm || ')'; end;
    begin
      insert into public.events(submitted_by,business_profile_id,title,category,town,venue,start_at,end_at,short_description,status,unverified_user_listing)
      values (case when i=6 then s else a end,orgA,'Probe listing','Community','Beachlands','V',now()+interval '3 days',now()+interval '3 days 1 hour','d','pending_review',false);
      r := r || ' listing=ALLOWED';
    exception when others then r := r || ' listing=DENIED(' || sqlerrm || ')'; end;
    begin
      insert into public.member_notices(business_profile_id,owner_user_id,title,status) values (orgA,a,'Probe notice','draft');
      r := r || ' notice=ALLOWED';
    exception when others then r := r || ' notice=DENIED(' || sqlerrm || ')'; end;
    perform public.current_user_can_publish(); -- smoke
    r := r || ' can_publish=' || public.current_user_can_publish()::text;
    execute 'reset role';
  end loop;
  raise exception 'PROBE_RESULT (rolled back):%', r;
end $$;
