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
```

## Current migrations

- `202606110000_current_schema_baseline.sql` captures the current public schema baseline: core event/listing tables, image metadata, support requests, engagement, payments, analytics, listing topics, location table shape, policies, indexes, triggers, enum, and app functions.
- `202606110001_location_scope_system.sql` creates the location hierarchy tables, search helpers, event location targets, views, triggers, RLS policies, and initial local/NZ seed data.
- `202606110002_public_organiser_events.sql` ensures events carry `submitted_by` and adds the index used by public organiser event pages.
- `202606110003_seed_location_search_starters.sql` adds a starter set of searchable named NZ places, including Howick and Paihia, while the full official locality import is prepared.

## Audit Queries

- `audit_queries.sql` contains read-only queries for comparing the live Supabase project against the migration baseline.
- Run these with result limits disabled where possible.

## Known Externals

- Auth users and real event/listing rows are not stored in migrations.
- Storage files are not stored in migrations.
- Storage bucket metadata/policies and Postgres event triggers should be audited with `audit_queries.sql` before production launch.
- MVP owner/admin access currently uses an email-based policy check. Replace this with roles/admin membership before wider production use.

## Operating note

Supabase had early schema, location, and organiser SQL applied manually during MVP setup. These migration files preserve that backend shape in git so future environments can be recreated and reviewed properly.
