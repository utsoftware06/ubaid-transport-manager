UT SOFTWARE — SECURITY PHASE 4
SUMMARY VERIFIER MISSING WRITER JOIN FIX

Phase 4 migration is already deployed.
Phase 4 post-verifier is 100% PASS.

The summary verifier fails with:

ERROR: 42P01:
missing FROM-clause entry for table "writer"

Around line 262:
(writer.prosecdef AND EXISTS(...))

This is summary-verifier-only.

Fix ONLY:
supabase/preflight/20261022_security_hardening_phase4_petrol_pumps_summary_verify.sql

Required:

1. Find the SELECT/CTE that references:
   writer.prosecdef

2. Identify the intended source CTE/table alias for that writer routine.

3. Add the correct explicit JOIN / FROM source,
   OR replace the direct alias reference with a scalar/aggregate value already produced by the appropriate writer CTE.

4. Do not add a dummy CROSS JOIN or weaken the condition.
   The summary verifier must still prove:
   - protected accounting RPC security mode
   - authenticated entry-point contracts
   - internal helper restrictions
   - anon/PUBLIC denied

5. Search the whole summary verifier for any other alias references that are not present in their SELECT's FROM/JOIN list:
   - writer.*
   - helper.*
   - legacy.*
   - policy.*
   - grant.*

6. Keep the summary verifier read-only.

Do NOT modify:
- migration
- post-verifier
- policies
- grants
- helper functions
- accounting RPCs
- data
- frontend

Return:
A. exact missing alias/join bug
B. exact fix
C. file changed
D. confirm migration does not need rerun
E. confirm I should rerun only the summary verifier

Do not execute SQL.