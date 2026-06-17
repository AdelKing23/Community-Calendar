# Supabase Backend Migrations

This folder is the source of truth for database changes used by the Pohutukawa Coast Calendar app.

## Rule

Every backend change should be added here as a dated migration before it is run in Supabase.

Use filenames like:

```text
YYYYMMDDHHMM_short_description.sql
```

Example:

```text
202606110000_current_schema_baseline.sql
202606110001_location_scope_system.sql
202606110002_public_organiser_events.sql
202606110003_seed_location_search_starters.sql
202606110004_seed_expanded_nz_places.sql
202606110005_import_statsnz_urban_rural_2026_places.sql
```

## Current migrations

- `202606110000_current_schema_baseline.sql` captures the current public schema baseline: core event/listing tables, image metadata, support requests, engagement, payments, analytics, listing topics, location table shape, policies, indexes, triggers, enum, and app functions.
- `202606110001_location_scope_system.sql` creates the location hierarchy tables, search helpers, event location targets, views, triggers, RLS policies, and initial local/NZ seed data.
- `202606110002_public_organiser_events.sql` ensures events carry `submitted_by` and adds the index used by public organiser event pages.
- `202606110003_seed_location_search_starters.sql` adds a starter set of searchable named NZ places, including Howick and Paihia, while the full official locality import is prepared.
- `202606110004_seed_expanded_nz_places.sql` adds a broader backend-only set of real NZ towns, suburbs, settlements, and visitor places, linked to the existing region ladder so location search can show more of New Zealand immediately.
- `202606110005_import_statsnz_urban_rural_2026_places.sql` imports 597 official user-facing urban areas and rural settlements from the Stats NZ Urban Rural 2026 DBF export. It excludes water and rural-other statistical buckets, preserves curated local ladders, and only adds a New Zealand fallback parent where no better widening link exists.
- `202606110006_link_statsnz_places_to_regions.sql` links imported Stats NZ places into their parent region ladders so places like Paihia, Hamilton, Rotorua, and Queenstown widen correctly.
- `202606150001_add_poll_listing_support.sql` adds structured poll fields to events and creates the poll response table for authenticated voting/custom feedback.
- `202606160001_add_poll_response_result_functions.sql` adds poll response RPC helpers for anonymous public option counts and owner/admin-only custom answer review.
- `202606160002_fix_poll_response_policy_for_fallback_polls.sql` updates poll response policies so already-created fallback polls stored in `[POLL]` long-description blocks can accept votes, while future structured poll rows continue to work normally.

## Audit Queries

- `audit_queries.sql` contains read-only queries for comparing the live Supabase project against the migration baseline.
- Run these with result limits disabled where possible.

## Known Externals

- Auth users and real event/listing rows are not stored in migrations.
- Storage files are not stored in migrations.
- Storage bucket metadata/policies and Postgres event triggers should be audited with `audit_queries.sql` before production launch.
- MVP owner/admin access currently uses an email-based policy check. Replace this with roles/admin membership before wider production use.
- The expanded NZ place seed is not a polygon/statistical geography import. It deliberately stores user-facing place names only.
- The Stats NZ Urban Rural 2026 import stores official names and source codes from the supplied DBF attributes only. Geometry files are intentionally not stored in Supabase because the app does not need polygons for location search.

## Operating note

Supabase had early schema, location, and organiser SQL applied manually during MVP setup. These migration files preserve that backend shape in git so future environments can be recreated and reviewed properly.
