-- t269 rollback: remove the complimentary App Review demo subscription and organisation (demo account only).
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
delete from public.business_subscriptions where owner_user_id='b64f22cb-5bf6-4e31-8901-d05815beb1b8' and provider='complimentary_review';
delete from public.business_profiles where owner_user_id='b64f22cb-5bf6-4e31-8901-d05815beb1b8' and business_name='App Review Demo Organisation' and support_note like 'COMPLIMENTARY APP REVIEW DEMO (t269)%'
  and not exists (select 1 from public.events e where e.business_profile_id = business_profiles.id);
-- If the reviewer created listings, archive/delete those first (they reference the organisation).
commit;
