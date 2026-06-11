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
```

## Current migrations

- `202606110000_current_schema_baseline.sql` captures the current public schema baseline: core event/listing tables, image metadata, support requests, engagement, payments, analytics, listing topics, location table shape, policies, indexes, triggers, enum, and app functions.
- `202606110001_location_scope_system.sql` creates the location hierarchy tables, search helpers, event location targets, views, triggers, RLS policies, and initial local/NZ seed data.
- `202606110002_public_organiser_events.sql` ensures events carry `submitted_by` and adds the index used by public organiser event pages.

## Operating note

Supabase had early schema, location, and organiser SQL applied manually during MVP setup. These migration files preserve that backend shape in git so future environments can be recreated and reviewed properly.
