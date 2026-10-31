# Department reports and student council access

A separate SELECT-only `documentation_private.report_read_scopes` table controls department/council delegation. It is never used by UPDATE/DELETE policies or by `report_edit_context`. Existing leadership, owner, support-center and technology editing permissions remain intact.

Department scopes are seeded from actual `observation_access` assignments for first teachers/coordinators, not their employment title or home department alone. The verified council coordinator is assigned the existing council tag; the archive and its `documentation_tag_memberships` RPC continue to use the original report IDs.

Only published, undeleted reports are newly shared. Explicit confidential/private flags, recognition/reward records, student meeting minutes and structured student rosters are excluded. Existing owner/admin access is retained. Unclassified sensitive free text cannot be reliably detected automatically and still requires administrative classification.

`department-reports.html` lists staff (including zero counts), groups reports by `created_by` UUID and expands them below each name. Its filters and counts share one ID-deduplicated source. The existing report/meeting viewers provide attachments and print/PDF output. Approved administrators can add/remove read-only department assignments from this page; changes are audited.

Storage policies already follow parent report RLS for images/PDFs, and meeting files follow the meeting read guard. No public buckets or extra upload/edit/delete permissions were introduced.

## Validation

- 13 local tests: PostgreSQL RLS, original report/attachment access, unrelated department denial, private/draft/student minutes denial, no peer UPDATE/DELETE, no self-delegation, admin assignment/revocation guard, UUID counts, zero-count staff, in-place expansion, existing council archive filter and print/PDF route actions.
- Production read-only RLS transaction for the council coordinator: 14 published council reports, including 3 other-author reports; all 32 referenced images visible via Storage RLS; zero peer edit grants; no DELETE privilege.
- No production report content, ownership, profile roles or passwords changed. Existing `meeting_private.read` definition is backed up in a private deployment backup table.
- A secure browser sign-in as the council coordinator is still required to verify actual UI/download behavior on that account. SQL impersonation and local UI tests are not a real sign-in.
