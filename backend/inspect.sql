-- Read-only metadata inspection. Does not read school records or change permissions.
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name in ('documentations', 'profiles')
order by table_name, ordinal_position;

select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where (n.nspname = 'public' and c.relname in ('documentations', 'profiles'))
   or (n.nspname = 'storage' and c.relname = 'objects');

select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where (schemaname = 'public' and tablename in ('documentations', 'profiles'))
   or (schemaname = 'storage' and tablename = 'objects')
order by schemaname, tablename, policyname;

select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets;

select tc.table_name, tc.constraint_name, tc.constraint_type,
       pg_get_constraintdef(c.oid) as definition
from information_schema.table_constraints tc
join pg_constraint c on c.conname = tc.constraint_name
join pg_class r on r.oid = c.conrelid and r.relname = tc.table_name
join pg_namespace n on n.oid = r.relnamespace and n.nspname = tc.table_schema
where tc.table_schema = 'public' and tc.table_name = 'documentations';

select trigger_name, event_manipulation, action_statement
from information_schema.triggers
where event_object_schema = 'public' and event_object_table = 'documentations';
