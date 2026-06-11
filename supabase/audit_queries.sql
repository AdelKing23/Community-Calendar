-- Supabase backend audit queries
--
-- Use these when checking whether the live Supabase project still matches the
-- migration baseline. These queries are read-only and should be run with result
-- limits disabled when possible.

-- Public table columns.
select
  table_schema,
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default,
  ordinal_position
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- Public constraints.
select
  conrelid::regclass::text as table_name,
  conname as constraint_name,
  contype as constraint_type,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where connamespace = 'public'::regnamespace
order by conrelid::regclass::text, conname;

-- Public indexes.
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- Public RLS policies.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- Public RLS enabled/forced status.
select
  schemaname,
  tablename,
  rowsecurity as rls_enabled,
  forcerowsecurity as rls_forced
from pg_tables
where schemaname = 'public'
order by tablename;

-- Public app functions. Extension functions from pg_trgm/unaccent can appear
-- here if extensions are installed into public; migrations should create the
-- extension rather than hand-copying those C functions.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;

-- Public table triggers.
select
  event_object_table as table_name,
  trigger_name,
  action_timing,
  event_manipulation,
  action_statement
from information_schema.triggers
where trigger_schema = 'public'
order by table_name, trigger_name;

-- Postgres event triggers, such as automatic RLS enabling helpers.
select
  evtname as trigger_name,
  evtevent as event_name,
  evtowner::regrole::text as owner,
  evtfoid::regprocedure::text as function_name,
  evtenabled as enabled_state,
  evttags as tags
from pg_event_trigger
order by evtname;

-- Public enums.
select
  t.typname as enum_name,
  e.enumlabel as enum_value,
  e.enumsortorder
from pg_type t
join pg_enum e on t.oid = e.enumtypid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
order by t.typname, e.enumsortorder;

-- Public views.
select
  schemaname,
  viewname,
  definition
from pg_views
where schemaname = 'public'
order by viewname;

-- Installed extensions.
select
  extname,
  extversion,
  n.nspname as schema_name
from pg_extension e
join pg_namespace n on n.oid = e.extnamespace
order by extname;

-- Supabase Storage buckets. This captures metadata only, not stored image files.
select
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types,
  created_at,
  updated_at
from storage.buckets
order by id;

-- Supabase Storage RLS policies.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'storage'
order by tablename, policyname;
