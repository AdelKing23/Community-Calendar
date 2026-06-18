# verify-apple-listing-purchase

Local draft Supabase Edge Function for verified StoreKit purchases.

This function is intentionally not deployed yet. It processes all paid listing
Apple products:

- `communitycalendar.commercial.standard` records the commercial listing payment
  and does not create a promotion.
- `communitycalendar.boost.standard` records payment and creates one bounded
  `top_ten` promotion.
- `communitycalendar.boost.insights` records payment and creates one bounded
  `priority_first` promotion. The paid insights entitlement is represented by
  the verified product/payment record and promotion tier; no separate entitlement
  table is introduced in this draft.

## Required Secrets

Do not commit secret values.

Supabase provides its own reserved default secrets. Do not create custom secrets
that start with `SUPABASE_`.

Default Supabase secrets used by this function:

- `SUPABASE_PUBLISHABLE_KEYS`
- `SUPABASE_SECRET_KEYS`

The function uses `SUPABASE_URL` if Supabase provides it; otherwise it falls
back to this project URL: `https://fujngeynyosnplviyvbg.supabase.co`.

Custom secrets to add:

- `APPLE_ISSUER_ID`
- `APPLE_KEY_ID`
- `APPLE_PRIVATE_KEY`
- `APPLE_BUNDLE_ID`
- `APPLE_ENVIRONMENT` (`Sandbox` or `Production`)

## Request

```json
{
  "event_id": "uuid",
  "transaction_id": "Apple transaction id",
  "product_id": "communitycalendar.boost.standard",
  "signed_transaction_jws": "optional client StoreKit signed transaction",
  "requested_starts_at": "optional ISO date",
  "requested_ends_at": "optional ISO date"
}
```

`product_id`, dates, and the signed transaction sent by the app are treated as
claims. Apple server transaction info is the source of truth.

## Response

```json
{
  "status": "activated",
  "apple_iap_transaction_id": "uuid",
  "event_payment_record_id": "uuid",
  "event_promotion_id": "uuid or null",
  "starts_at": "ISO date or null",
  "ends_at": "ISO date or null",
  "message": "Human-readable processing note"
}
```

Possible statuses are `activated`, `already_processed`, and `rejected`.

## Removal

Delete this folder and do not run/deploy `202606180001_add_apple_iap_transaction_ledger.sql`.
If the SQL has already been run in a sandbox, remove the Edge Function and drop
the additive `apple_iap_transactions` objects only after preserving any audit
data needed for review.
