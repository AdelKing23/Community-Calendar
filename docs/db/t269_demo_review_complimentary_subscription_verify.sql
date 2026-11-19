-- t269 verify (everything rolled back by the final raise): demo account can create; an unpaid approved org is still blocked.
do $$
declare demo uuid := 'b64f22cb-5bf6-4e31-8901-d05815beb1b8'; org uuid := 'e17e7b74-8cf7-454e-8372-25a93ec9cb9d';
        p uuid := gen_random_uuid(); porg uuid; r text := '';
begin
  -- 1) demo account
  perform set_config('request.jwt.claims', json_build_object('sub',demo,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  r := r || ' demo_can_publish=' || public.current_user_can_publish()::text;
  begin
    insert into public.events(submitted_by,business_profile_id,title,category,town,venue,start_at,end_at,short_description,status,unverified_user_listing)
    values (demo,org,'Verify listing','Community','Beachlands','V',now()+interval '3 days',now()+interval '3 days 1 hour','d','pending_review',false);
    r := r || ' demo_listing=ALLOWED';
  exception when others then r := r || ' demo_listing=DENIED(' || sqlerrm || ')'; end;
  execute 'reset role';
  -- 2) ordinary unpaid approved organisation
  insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values (p,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-t269@example.invalid',now(),'{}','{}',now(),now());
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.business_profiles(owner_user_id,business_name,organisation_type,contact_email,status,approved_at)
  values (p,'Probe Org t269','community_group','probe-t269@example.invalid','approved',now()) returning id into porg;
  perform set_config('request.jwt.claims', json_build_object('sub',p,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.events(submitted_by,business_profile_id,title,category,town,venue,start_at,end_at,short_description,status,unverified_user_listing)
    values (p,porg,'Probe listing','Community','Beachlands','V',now()+interval '3 days',now()+interval '3 days 1 hour','d','pending_review',false);
    r := r || ' unpaid_listing=ALLOWED';
  exception when others then r := r || ' unpaid_listing=DENIED(' || sqlerrm || ')'; end;
  execute 'reset role';
  raise exception 'VERIFY_RESULT (rolled back):%', r;
end $$;
