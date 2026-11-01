Created the legacy provenance deployment package:
- [Read-only preflight](C:/Users/HOME/Downloads/ubaid-transport-manager/supabase/preflight/20261012_diesel_legacy_tenant_provenance_preflight.sql)
- [Forward-only migration](C:/Users/HOME/Downloads/ubaid-transport-manager/supabase/migrations/202610120003_diesel_legacy_tenant_provenance.sql)
- [Post-verifier](C:/Users/HOME/Downloads/ubaid-transport-manager/supabase/preflight/20261012_diesel_legacy_tenant_provenance_post_verify.sql)
- [Summary verifier](C:/Users/HOME/Downloads/ubaid-transport-manager/supabase/preflight/20261012_diesel_legacy_tenant_provenance_summary_verify.sql)
The migration adds nullable diesel_entries.legacy_adda_id and assigns it only to Diesel row 4. Before doing so, it asserts row 4 still references Loading 8 and Voucher 12, has no Manual Voucher context, matches LES-1234 and the expected Adda, and has the matching Voucher link and exactly one qualifying Cashbook row. It snapshots the Diesel row and verifies all existing fields other than the new provenance and updated_at remain unchanged. It does not assign a Booking or write to Cashbook.
The shared resolver now checks, in order: Manual Voucher Adda, normal Loading-to-Booking Adda, then explicitly evidenced legacy provenance. Unresolved or mixed-Adda pump history still resolves to NULL; different vehicles within one Adda remain valid. The expected shell result is 44b73002-7582-4c75-aca8-24d853311674.
SQL run order: preflight → migration → post-verifier → summary verifier.
Static structure and git diff --check passed. No local PostgreSQL parser was available, and no production SQL was executed.

  Edited 4 files+1,008-0View changesUndoView changes

supabase/preflight/20261012_diesel_legacy_tenant_provenance_preflight.sqlsupabase/preflight/20261012_diesel_legacy_tenant_provenance_preflight.sql+134-0
supabase/migrations/202610120003_diesel_legacy_tenant_provenance.sqlsupabase/migrations/202610120003_diesel_legacy_tenant_provenance.sql+360-0
supabase/preflight/20261012_diesel_legacy_tenant_provenance_post_verify.sqlsupabase/preflight/20261012_diesel_legacy_tenant_provenance_post_verify.sql+269-0
Show 1 more file