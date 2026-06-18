# Apple IAP Sandbox Deployment Checklist

Use this checklist when moving the local Apple in-app purchase scaffold into the
Supabase sandbox path. Do not use `supabase db push` for this pass unless the
remote migration history has been reconciled first; earlier MVP migrations were
applied manually, so pushing the whole folder could replay old setup SQL.

## Current Project

- Supabase project ref: `fujngeynyosnplviyvbg`
- Supabase URL: `https://fujngeynyosnplviyvbg.supabase.co`
- Edge Function: `verify-apple-listing-purchase`
- Migration to run manually: `supabase/migrations/202606180001_add_apple_iap_transaction_ledger.sql`

## Apple Products

Confirm these exist in App Store Connect sandbox before enabling any purchase UI:

- `communitycalendar.commercial.standard`
- `communitycalendar.boost.standard`
- `communitycalendar.boost.insights`

Expected behavior:

- `communitycalendar.commercial.standard` records an `event_payment_records` row only.
- `communitycalendar.boost.standard` records payment and creates one bounded `top_ten` promotion.
- `communitycalendar.boost.insights` records payment and creates one bounded `priority_first` promotion.

## SQL Install

Run only this migration in Supabase SQL Editor:

```text
supabase/migrations/202606180001_add_apple_iap_transaction_ledger.sql
```

Do not run older migration files again.

After it succeeds, verify:

```sql
select to_regclass('public.apple_iap_transactions') as apple_iap_transactions;

select proname
from pg_proc
where proname = 'process_verified_apple_iap_transaction';

select policyname
from pg_policies
where schemaname = 'public'
  and tablename = 'apple_iap_transactions';
```

Expected:

- `apple_iap_transactions` is not null.
- `process_verified_apple_iap_transaction` exists.
- The table has the service-role-only policy.

## Required Secrets

Set these with real values only in Supabase, never in git:

```sh
supabase secrets set --project-ref fujngeynyosnplviyvbg \
  SUPABASE_URL="https://fujngeynyosnplviyvbg.supabase.co" \
  SUPABASE_ANON_KEY="..." \
  SUPABASE_SERVICE_ROLE_KEY="..." \
  APPLE_ISSUER_ID="..." \
  APPLE_KEY_ID="..." \
  APPLE_PRIVATE_KEY="..." \
  APPLE_BUNDLE_ID="com.atlasdigital.Pohutukawa-Coast-Calendar" \
  APPLE_ENVIRONMENT="Sandbox"
```

`APPLE_PRIVATE_KEY` should be the full `.p8` private key content. If setting it
from a local key file, use a shell method that does not print the key value into
terminal history or logs.

## Function Deploy

Deploy only after the SQL migration and secrets are ready:

```sh
supabase functions deploy verify-apple-listing-purchase \
  --project-ref fujngeynyosnplviyvbg
```

Do not enable user-facing purchase buttons until a sandbox purchase has been
verified end to end.

## Sandbox Smoke Test

1. Create or use a published listing owned by the signed-in sandbox user.
2. Start with `communitycalendar.boost.standard`.
3. Complete an Apple sandbox purchase.
4. Confirm the app does not finish the transaction until the backend returns
   `activated` or `already_processed`.
5. Verify Supabase rows:

```sql
select apple_transaction_id, product_id, processing_status, event_payment_record_id, event_promotion_id
from public.apple_iap_transactions
order by created_at desc
limit 5;

select provider, product_id, status, amount_cents, transaction_reference
from public.event_payment_records
order by created_at desc
limit 5;

select tier, placement, status, starts_at, ends_at, paid_at
from public.event_promotions
order by created_at desc
limit 5;
```

Expected for `communitycalendar.boost.standard`:

- Apple ledger row is `processed`.
- Payment row has provider `apple_iap`, status `paid`, amount `1000`.
- Promotion row has tier `boost`, placement `top_ten`, and bounded dates.

Repeat with:

- `communitycalendar.commercial.standard`: payment only, no promotion.
- `communitycalendar.boost.insights`: payment plus `boost_insights` / `priority_first`.

## Rollback

Before SQL is run:

- Revert the local commit containing the scaffold, or remove:
  - `Pohutukawa Coast Calendar/Services/AppleListingPurchaseModels.swift`
  - the StoreKit backend-processing edits
  - `supabase/functions/verify-apple-listing-purchase`
  - `supabase/migrations/202606180001_add_apple_iap_transaction_ledger.sql`

After SQL is run:

1. Do not delete audit rows blindly.
2. Disable or delete the Edge Function first.
3. Preserve any `apple_iap_transactions` rows needed for review.
4. Only then drop the additive Apple IAP function/table/indexes/policy if the
   sandbox test needs to be fully reset.
