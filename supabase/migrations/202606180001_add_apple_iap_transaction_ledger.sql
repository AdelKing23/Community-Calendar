-- Apple in-app purchase transaction ledger and server-side processing
-- Draft only until reviewed and run manually.
--
-- Edge Functions own writes to this ledger by calling the service-role-only
-- processing function after Apple server verification. Swift clients must not
-- insert, update, or mark payments/promotions paid directly.

begin;

create table if not exists public.apple_iap_transactions (
  id uuid primary key default gen_random_uuid(),
  apple_transaction_id text not null,
  apple_original_transaction_id text,
  product_id text not null,
  app_account_token uuid,
  purchaser_user_id uuid not null references auth.users(id) on delete restrict,
  event_id uuid not null references public.events(id) on delete cascade,
  environment text not null,
  bundle_id text,
  purchase_date timestamptz not null,
  expiration_date timestamptz,
  revocation_date timestamptz,
  revocation_reason text,
  signed_transaction_hash text not null,
  verification_status text not null,
  processing_status text not null,
  failure_reason text,
  event_payment_record_id uuid references public.event_payment_records(id) on delete set null,
  event_promotion_id uuid references public.event_promotions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint apple_iap_transactions_transaction_not_blank_check
    check (length(trim(apple_transaction_id)) > 0),
  constraint apple_iap_transactions_product_not_blank_check
    check (length(trim(product_id)) > 0),
  constraint apple_iap_transactions_environment_check
    check (environment in ('Sandbox', 'Production', 'Xcode', 'LocalTesting')),
  constraint apple_iap_transactions_verification_status_check
    check (verification_status in ('verified', 'revoked', 'rejected')),
  constraint apple_iap_transactions_processing_status_check
    check (processing_status in ('received', 'processed', 'rejected', 'revoked')),
  constraint apple_iap_transactions_known_product_check
    check (
      product_id in (
        'communitycalendar.commercial.standard',
        'communitycalendar.boost.standard',
        'communitycalendar.boost.insights'
      )
    )
);

create unique index if not exists apple_iap_transactions_apple_transaction_id_uidx
on public.apple_iap_transactions (apple_transaction_id);

create unique index if not exists apple_iap_transactions_transaction_binding_uidx
on public.apple_iap_transactions (
  apple_transaction_id,
  purchaser_user_id,
  event_id,
  product_id
);

create index if not exists apple_iap_transactions_purchaser_time_idx
on public.apple_iap_transactions (purchaser_user_id, created_at desc);

create index if not exists apple_iap_transactions_event_time_idx
on public.apple_iap_transactions (event_id, created_at desc);

create index if not exists apple_iap_transactions_processing_status_idx
on public.apple_iap_transactions (processing_status, created_at desc);

create index if not exists apple_iap_transactions_original_transaction_idx
on public.apple_iap_transactions (apple_original_transaction_id)
where apple_original_transaction_id is not null;

create index if not exists apple_iap_transactions_product_id_idx
on public.apple_iap_transactions (product_id, created_at desc);

create unique index if not exists event_payment_records_apple_transaction_reference_uidx
on public.event_payment_records (provider, transaction_reference)
where provider = 'apple_iap' and transaction_reference is not null;

create unique index if not exists event_promotions_payment_record_id_uidx
on public.event_promotions (payment_record_id)
where payment_record_id is not null;

drop trigger if exists set_apple_iap_transactions_updated_at on public.apple_iap_transactions;
create trigger set_apple_iap_transactions_updated_at
before update on public.apple_iap_transactions
for each row execute function public.set_updated_at();

alter table public.apple_iap_transactions enable row level security;

drop policy if exists "Service role owns apple iap transaction writes" on public.apple_iap_transactions;
create policy "Service role owns apple iap transaction writes"
on public.apple_iap_transactions
for all
to service_role
using (true)
with check (true);

comment on table public.apple_iap_transactions is
  'Immutable-ish Apple IAP audit ledger. Edge Functions verify Apple transactions and write through service-role-only RPCs; clients do not write here.';

comment on column public.apple_iap_transactions.signed_transaction_hash is
  'SHA-256 hash of the Apple signed transaction representation used for audit without storing the full signed payload.';

create or replace function public.process_verified_apple_iap_transaction(
  p_apple_transaction_id text,
  p_apple_original_transaction_id text,
  p_product_id text,
  p_app_account_token uuid,
  p_purchaser_user_id uuid,
  p_event_id uuid,
  p_environment text,
  p_bundle_id text,
  p_purchase_date timestamptz,
  p_expiration_date timestamptz,
  p_revocation_date timestamptz,
  p_revocation_reason text,
  p_signed_transaction_hash text,
  p_requested_starts_at timestamptz default now(),
  p_requested_ends_at timestamptz default null
)
returns table (
  status text,
  apple_iap_transaction_id uuid,
  event_payment_record_id uuid,
  event_promotion_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_txn public.apple_iap_transactions%rowtype;
  inserted_txn_id uuid;
  resolved_payment_id uuid;
  resolved_promotion_id uuid;
  event_owner uuid;
  event_end timestamptz;
  event_status public.listing_status;
  product_amount_cents integer;
  product_tier text;
  product_placement text;
  promotion_starts_at timestamptz;
  promotion_ends_at timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'process_verified_apple_iap_transaction is server-only';
  end if;

  if length(trim(coalesce(p_apple_transaction_id, ''))) = 0 then
    status := 'rejected';
    message := 'Apple transaction id is required';
    return next;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_apple_transaction_id));

  select *
    into existing_txn
  from public.apple_iap_transactions
  where apple_transaction_id = p_apple_transaction_id;

  if found then
    if existing_txn.purchaser_user_id <> p_purchaser_user_id
       or existing_txn.event_id <> p_event_id
       or existing_txn.product_id <> p_product_id then
      status := 'rejected';
      apple_iap_transaction_id := existing_txn.id;
      message := 'Apple transaction is already bound to a different user, listing, or product';
      return next;
      return;
    end if;

    status := case
      when existing_txn.processing_status = 'processed' then 'already_processed'
      else 'rejected'
    end;
    apple_iap_transaction_id := existing_txn.id;
    event_payment_record_id := existing_txn.event_payment_record_id;
    event_promotion_id := existing_txn.event_promotion_id;

    if existing_txn.event_promotion_id is not null then
      select ep.starts_at, ep.ends_at
        into starts_at, ends_at
      from public.event_promotions ep
      where ep.id = existing_txn.event_promotion_id;
    end if;

    message := coalesce(existing_txn.failure_reason, 'Apple transaction was already received');
    return next;
    return;
  end if;

  if p_product_id = 'communitycalendar.commercial.standard' then
    product_amount_cents := 500;
    product_tier := 'commercial_standard';
    product_placement := null;
  elsif p_product_id = 'communitycalendar.boost.standard' then
    product_amount_cents := 1000;
    product_tier := 'boost';
    product_placement := 'top_ten';
  elsif p_product_id = 'communitycalendar.boost.insights' then
    product_amount_cents := 1500;
    product_tier := 'boost_insights';
    product_placement := 'priority_first';
  else
    status := 'rejected';
    message := 'Unknown Apple product id';
    return next;
    return;
  end if;

  if p_revocation_date is not null then
    insert into public.apple_iap_transactions (
      apple_transaction_id,
      apple_original_transaction_id,
      product_id,
      app_account_token,
      purchaser_user_id,
      event_id,
      environment,
      bundle_id,
      purchase_date,
      expiration_date,
      revocation_date,
      revocation_reason,
      signed_transaction_hash,
      verification_status,
      processing_status,
      failure_reason
    )
    values (
      trim(p_apple_transaction_id),
      nullif(trim(coalesce(p_apple_original_transaction_id, '')), ''),
      p_product_id,
      p_app_account_token,
      p_purchaser_user_id,
      p_event_id,
      p_environment,
      nullif(trim(coalesce(p_bundle_id, '')), ''),
      p_purchase_date,
      p_expiration_date,
      p_revocation_date,
      nullif(trim(coalesce(p_revocation_reason, '')), ''),
      p_signed_transaction_hash,
      'revoked',
      'rejected',
      'Apple transaction is revoked or refunded'
    )
    returning id into inserted_txn_id;

    status := 'rejected';
    apple_iap_transaction_id := inserted_txn_id;
    message := 'Apple transaction is revoked or refunded';
    return next;
    return;
  end if;

  if not exists (select 1 from auth.users u where u.id = p_purchaser_user_id) then
    status := 'rejected';
    message := 'Purchaser user does not exist';
    return next;
    return;
  end if;

  select e.submitted_by, e.end_at, e.status
    into event_owner, event_end, event_status
  from public.events e
  where e.id = p_event_id;

  if event_owner is null then
    status := 'rejected';
    message := 'Listing does not exist';
    return next;
    return;
  end if;

  if event_owner <> p_purchaser_user_id then
    status := 'rejected';
    message := 'Listing does not belong to purchaser';
    return next;
    return;
  end if;

  if event_end <= now() then
    status := 'rejected';
    message := 'Listing has already ended';
    return next;
    return;
  end if;

  if product_placement is not null and event_status <> 'published'::public.listing_status then
    status := 'rejected';
    message := 'Boosts can only be activated on published listings';
    return next;
    return;
  end if;

  if product_placement is not null then
    select cw.starts_at, cw.ends_at
      into promotion_starts_at, promotion_ends_at
    from public.clamp_event_promotion_window(
      p_event_id,
      product_tier,
      p_requested_starts_at,
      p_requested_ends_at
    ) cw
    limit 1;

    if promotion_starts_at is null or promotion_ends_at is null then
      status := 'rejected';
      message := 'No valid remaining promotion window exists';
      return next;
      return;
    end if;
  end if;

  insert into public.event_payment_records (
    event_id,
    purchased_by,
    provider,
    product_id,
    transaction_reference,
    amount_cents,
    currency,
    status
  )
  values (
    p_event_id,
    p_purchaser_user_id,
    'apple_iap',
    p_product_id,
    trim(p_apple_transaction_id),
    product_amount_cents,
    'NZD',
    'paid'
  )
  returning id into resolved_payment_id;

  if product_placement is not null then
    insert into public.event_promotions (
      event_id,
      purchased_by,
      payment_record_id,
      tier,
      placement,
      status,
      starts_at,
      ends_at,
      paid_at
    )
    values (
      p_event_id,
      p_purchaser_user_id,
      resolved_payment_id,
      product_tier,
      product_placement,
      'paid',
      promotion_starts_at,
      promotion_ends_at,
      p_purchase_date
    )
    returning id into resolved_promotion_id;
  end if;

  insert into public.apple_iap_transactions (
    apple_transaction_id,
    apple_original_transaction_id,
    product_id,
    app_account_token,
    purchaser_user_id,
    event_id,
    environment,
    bundle_id,
    purchase_date,
    expiration_date,
    revocation_date,
    revocation_reason,
    signed_transaction_hash,
    verification_status,
    processing_status,
    event_payment_record_id,
    event_promotion_id
  )
  values (
    trim(p_apple_transaction_id),
    nullif(trim(coalesce(p_apple_original_transaction_id, '')), ''),
    p_product_id,
    p_app_account_token,
    p_purchaser_user_id,
    p_event_id,
    p_environment,
    nullif(trim(coalesce(p_bundle_id, '')), ''),
    p_purchase_date,
    p_expiration_date,
    null,
    null,
    p_signed_transaction_hash,
    'verified',
    'processed',
    resolved_payment_id,
    resolved_promotion_id
  )
  returning id into inserted_txn_id;

  status := 'activated';
  apple_iap_transaction_id := inserted_txn_id;
  event_payment_record_id := resolved_payment_id;
  event_promotion_id := resolved_promotion_id;
  starts_at := promotion_starts_at;
  ends_at := promotion_ends_at;
  message := case
    when product_placement is null then 'Commercial listing payment recorded'
    else 'Promotion payment recorded and bounded promotion created'
  end;
  return next;
end;
$$;

revoke all on function public.process_verified_apple_iap_transaction(
  text,
  text,
  text,
  uuid,
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  timestamptz,
  timestamptz
) from public, anon, authenticated;

grant execute on function public.process_verified_apple_iap_transaction(
  text,
  text,
  text,
  uuid,
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  timestamptz,
  timestamptz
) to service_role;

comment on function public.process_verified_apple_iap_transaction(
  text,
  text,
  text,
  uuid,
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  timestamptz,
  timestamptz
) is
  'Service-role-only atomic processor for Apple IAP transactions verified by an Edge Function.';

commit;
