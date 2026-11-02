-- Pure parser called by the RLS-protected, SECURITY INVOKER archive-membership RPC.
-- This grants no report, file, editing or deletion access.
grant execute on function documentation_private.legacy_tag_names(text) to authenticated;
