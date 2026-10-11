# Classroom observations in the original school portal

This change adds `visits.html`, `visit-edit.html`, `visit-analysis.html` and the read-only `visit-report.html`. It reuses the existing Supabase project, school branding and authenticated session. No alternate portal or hosting is created.

## Activation boundary

The school owner requested approval before changes to production data or permissions. The additive migration is prepared and tested, but MUST NOT be applied or published automatically. No production observation tables, roster, grants or accounts were created during preparation.

Teacher names, account links and departmental grant manifests are private school data. They are intentionally absent from this public repository. Import the school-approved roster separately after approval. Bind `observation_teachers.user_id` only to a verified account ID; never match identities by a display name supplied by a user. A roster entry does not create an Auth account or elevate `profiles.role`.

Preserve the existing server-owned `profiles.school_access`. Principal and the authorized assistant with `school_access=all` can access all departments. Other assistants, first teachers and coordinators require protected `observation_access` rows for approved departments. An empty `domain_ids` means all five official observation domains within that department; a populated array permits only its criterion rows. Domain-limited observers cannot read post-visit details or write a whole form. Ordinary teachers can read only their own finalized visits. Drafts are visible only to their observer within an authorized department. No authenticated direct INSERT/UPDATE/DELETE grants exist for these tables.

## Data integrity

Visit metadata, all 18 rating rows and post-visit details save in one transaction. The official criteria are immutable in client code and criterion IDs are constrained in Postgres. An unassessed rating is NULL. Finalization requires the two academic-achievement criteria, an explicitly selected final judgment and a written basis. The official form calls for a judgment based on those two criteria with consistency across the remaining domains; it does not specify a deterministic rule for disagreements. No numerical average is used to infer a lesson judgment.

A client request ID makes new-visit retries idempotent. A version check prevents overwriting a concurrent edit. There is no delete interface. Read-only analysis captures are performed on the server using current database permissions. Saved reports contain an immutable server-created snapshot and are reauthorized against current permissions when read.

Percentages use each criterion's valid rating count as denominator. Domain summaries pool valid ratings across their criteria. Operational counts may be zero; missing performance distributions remain null. Teacher coverage uses the approved roster for the selected academic year; no historical denominator is invented when no roster exists for that year. Comparisons show changes in the proportion exceeding expectations and their actual sample sizes, without claiming causation.

## Export

PDF embeds local Arabic fonts and the original school/ministry logo banner, preserves the RTL table, gray domain rows, all 18 criteria, counts and two-decimal percentages. The unified summary fits A4 landscape. Long narratives are paginated without clipping. The export is static and has no editable form fields. Excel uses native OOXML worksheets, numeric counts/percentages/dates, RTL sheet views, and explicit number formats; user text is always stored as text. Viewing or exporting reports never creates or updates a visit.

## Verification

Run `npm ci --ignore-scripts` then `npm run test:visits`. Tests use a local, isolated Postgres WASM engine, simulated accounts and synthetic observations. They verify roles, department/domain isolation, valid denominators, teacher coverage, comparisons, idempotent retries, atomicity, conflicting edits, saved report immutability, reopen/recovery, and PDF/Excel export. A DOM integration test connects the actual page modules to this isolated SQL backend. This is not proof of behavior on the deployed Supabase/PostgREST endpoint or on Safari/iPhone.

After school-owner approval: verify the current main branch and production schema again; apply the reviewed additive migration; import only the approved private roster; bind and assign only verified accounts; run Supabase security advisors; publish the same portal files; and repeat the role/save/reopen/report/export checks on the published URL. Do not mark official launch ready before those checks pass.
