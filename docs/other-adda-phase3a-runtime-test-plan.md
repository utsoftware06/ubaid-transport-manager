# Other Adda Phase 3A runtime authorization test plan

## Scope and execution gate

This is TEST DESIGN ONLY. No test in this document has been executed. The user reports that the foundation migration is deployed and the 17-row structural verifier has been accepted with zero BLOCKED rows. That report is not runtime authorization evidence.

Phase 3A is NON-CASH. Phase 3B remains NO-GO. Do not modify schema, functions, grants, profiles, users, auth logic or frontend. Do not write to any existing financial/operational module. Do not disable guards, impersonate users in SQL Editor, create payments or delete history.

### Mode A — safe pre-runtime

The companion file `supabase/preflight/20260918_other_adda_phase3a_runtime_discovery.sql` is one read-only SELECT with labelled sections 01–12. It inspects candidate identities, state, contracts and baselines. It does not run business RPCs or change context. It has been drafted only; running it is a separate human action. Save its complete result securely. Candidate profile UUIDs are identifiers, not authentication credentials.

### Mode B — controlled runtime, separate explicit approval required

Prefer isolated staging/local Supabase with the same accepted Phase 3A contract and legitimate existing test identities. Do not automatically provision users or copy production secrets/data. If that environment does not exist, report it.

Before production runtime execution, obtain explicit approval covering the environment, selected tenant/profile IDs, dedicated fixture names, maximum intended events, allowed negative tests, concurrency tests and permanent-history consequences. Running Mode A does not approve Mode B. Every request is a separate committed API transaction; a SQL Editor rollback does not clean up authenticated HTTP requests.

Test masters and obligations are persistent auditable data. They can only be fully reversed and archived, not deleted. Even a supposedly denied request could create a row if a defect exists: use exclusively dedicated approved fixtures, never real business masters/transactions. Do not promise rollback-only production mutation tests.

## Contract audit and runtime assumptions

The complete repository migration and post-verifier were reread for this design, rather than relying on summaries. Live drift is checked by discovery definitions and function-body fingerprints; repository contents alone cannot prove current deployment equality.

| Object | Audited contract / assumption to test |
|---|---|
| `other_addas` | UUID identity, required Adda FK, composite `(adda_id,id)` unique key, regular/one_time, active/archived, profile actor FKs and archive-state CHECK. Historical master deletion and identity rewrites blocked by guard. |
| `other_adda_transactions` | Positive finite numeric(18,2), two sides, manual origin, obligation/reversal event type, tenant/request uniqueness, composite master and reversal FKs, one reversal per original. No settlement or integration IDs. |
| `ut_other_adda_authorize(uuid,boolean)` | Requires auth.uid and active profile; allowed roles super_admin/adda_admin/operator. Admin flag excludes operator. Normal users derive tenant from helper and cannot override it. Super Admin uses explicit target or own assigned tenant fallback; target must be a live Adda. |
| `save_other_adda` | Admin only. Optional explicit target. Create uses `p_id=NULL`; edit requires same-tenant existing ID. FULL replacement of editable fields, including nullable fields; unspecified fields become NULL/default. No create request-id idempotency. Do not blindly retry an uncertain master create. |
| `set_other_adda_status(uuid,text)` | Admin only. Resolves target from existing master; row lock serializes lifecycle against posting. Archive tests unreversed originals and invalid reversal state, not net. Reactivation preserves UUID. Repeated archive preserves original archive actor/time; reactivation clears archive metadata. |
| `ut_other_adda_event` | Private shared implementation; repeats authorization, locks tenant/request then master, compares complete normalized payload and actor on retries. Existing matching requests return before active-master/double-reversal rejection. |
| `post_other_adda_obligation` | Active own-tenant master; operator/admin permitted. Amount >0, finite, <=2 decimals and <10^16. Required date, nonblank description, request UUID. Captures actor. |
| `reverse_other_adda_obligation` | Admin only. Resolves original/master/tenant. Full original amount and same side; original must be an obligation; date cannot precede original; reason required. New event, no rewrite. |
| `ut_other_adda_guard()` | BEFORE row guards enforce append-only transactions and reversal compatibility; master guard rejects delete/identity rewrites/invalid archive. BEFORE TRUNCATE guards exist on both tables. No browser helper EXECUTE. |
| `find_other_adda_duplicates` | Target-authorized search across active AND archived; trimmed/case-normalized name OR digits-only mobile. City is a match flag, not an independent search or mandatory filter. No country-code normalization, fuzzy identity, merge or unique-name enforcement. |
| `get_other_adda_balances` | One authorized tenant per call, including explicitly targeted Super Admin. Obligation amounts minus full reversal amounts per side; net=receivable-payable. Counts originals/reversals/effective originals. No paid/partial fields. |
| Table/RPC privileges | Authenticated SELECT only on both tables; entry EXECUTE only to authenticated. PUBLIC/anon/service role have no intended table or RPC access. Active Super Admin table RLS reads are deliberately global. All nine new functions are postgres-owned DEFINER with empty search_path. |

Read-only discovery returns exact definitions for all nine routines, plus existing authority helpers, and flags changed bodies/grants. STOP on unexplained mismatch before constructing expected runtime outcomes.

## Identity and fixture selection

Do not invent UUIDs. Select live IDs only from reviewed Mode A output.

| Placeholder | Requirement |
|---|---|
| `A` / `ADMIN_A` | Live Tenant A, active adda_admin, legitimate authenticated session available. |
| `OP_A` | Active operator in the SAME A, legitimate session available. |
| `B` / `USER_B` | Different live tenant B; active non-super operator/admin with a legitimate session. |
| `ADMIN_B` or `SA` | Needed to create dedicated B fixtures, unless already approved test-only fixtures exist. A B operator alone cannot create a master. |
| `SA` (optional) | Active super_admin with legitimate session. Record whether profile has adda_id; this changes omitted-target behavior. Absence means SKIPPED, not PASS. |

Discovery lists all candidates and eligible A/B pairs; it does not auto-select anyone. Missing same-tenant A admin/operator, distinct B user, accessible sessions or B fixture creator blocks the affected tests. Do not substitute a Super Admin for ordinary cross-tenant RLS tests. Do not change profile roles/active flags just to satisfy the matrix. Anonymous and inactive-profile testing is optional only if safe existing contexts are available; never manufacture JWTs.

Before Mode B, define `RUN_SUFFIX` as a new run UUID string and names `UT_PHASE3A_TEST_<RUN_SUFFIX>_<purpose>`. Obtain approval for synthetic mobile/name values that are demonstrably non-business test metadata; no real person's phone/name. Use the same digits with formatting changes for duplicate tests. Do not send messages or notifications.

Dedicated fixtures:

- `M_EMPTY`: A one_time master for lifecycle and duplicates.
- `M_NET`: A master for RECEIVABLE 100 / PAYABLE 100 net-zero archive denial.
- `M_BAL`: A master for RECEIVABLE 100 / RECEIVABLE 40 / PAYABLE 70 and retry/reversal tests.
- `M_B`: B test-only master with one test-only obligation `T_B`, created only by ADMIN_B or explicitly targeted SA.
- Concurrency/Super Admin fixture masters: separate approved fixtures, staging preferred; never reuse business data.

Use an approved finite date `D`; reversals use D or later. Use a new request UUID for EVERY new event/negative case, except deliberate retries of the SAME logical request. Log request UUIDs before sending. No fabricated production IDs appear in this plan.

## Authenticated context and evidence protocol

All RLS reads, entry-RPC allow/deny checks, direct row-scoped DML denials and concurrency tests require real independently authenticated user sessions through the Supabase API/application context. No frontend implementation is required; a human-controlled API client may use legitimate sessions after Mode B approval. Never print/export JWTs, refresh tokens, passwords or service keys. Do not use service_role or postgres as a substitute.

SQL Editor postgres bypasses the user context. It can inspect grants, policies, definitions, indexes and trigger presence and collect baselines; it cannot prove browser authorization. Do not SET ROLE, SET JWT claims, set_config, alter auth.uid, or weaken grants to make tests pass. Trigger defense against privileged direct DML is NOT proven by authenticated permission denial; verify its definition/catalog now and reserve any privileged runtime trigger probe for separately approved disposable staging.

For each case record: run/case ID, environment, profile/role/tenant ID (no tokens), exact sanitized named-parameter payload, request UUID, timestamp, HTTP status, database error code/message, returned UUID/rows, expected vs actual, and scoped post-read counts/actors. Distinguish PASS, FAIL, BLOCKED and SKIPPED. Never label a case PASS solely because an API returned success; inspect the resulting dedicated fixture rows/balances. Denials must have no fixture changes.

Ordinary unauthorized table SELECT under RLS typically succeeds with ZERO ROWS; that is the expected denial of visibility, not necessarily an HTTP error. RPC errors generally use the function's exception message (often SQLSTATE P0001); transport/status can differ. Permission denial is normally 42501; record actual results without assuming a particular HTTP code. The plan does not probe arbitrary business row UUIDs.

## Exact entry call contracts (named parameters, not executable scripts)

| RPC | Named parameters |
|---|---|
| `save_other_adda` | `p_id`, `p_adda_name`, optional `p_contact_person`, `p_mobile`, `p_whatsapp`, `p_city`, `p_address`, `p_ntn_cnic`, `p_business_type`, `p_notes`, `p_target_adda_id`. For edits supply the entire desired editable snapshot, not only changed fields. |
| `set_other_adda_status` | `p_other_adda_id`, `p_status` = active or archived. |
| `find_other_adda_duplicates` | `p_adda_name`, optional `p_mobile`, `p_city`, `p_target_adda_id`. |
| `post_other_adda_obligation` | `p_other_adda_id`, `p_transaction_date`, `p_side`, `p_amount`, `p_description`, `p_request_id`, optional `p_reference_no`. No tenant parameter. |
| `reverse_other_adda_obligation` | `p_transaction_id`, `p_transaction_date`, `p_reason`, `p_request_id`. No tenant/side/amount parameter. |
| `get_other_adda_balances` | Optional `p_target_adda_id`. Normal omission resolves own tenant, not all tenants. |

Do not invoke the private ut_ helpers. An unknown `adda_id` parameter is not a supported contract: normal target override tests use the supported `p_target_adda_id`; direct forged relationship tests use catalog proof or dedicated row-scoped authenticated denial probes.

## Role matrix

| Operation | OP_A | ADMIN_A | Active SA |
|---|---|---|---|
| Own tenant table reads / duplicate search / balances | Allow | Allow | Allow; table reads may be global |
| Create/edit master | Deny role_not_authorized | Allow own tenant | Explicit target or own assigned tenant fallback |
| Archive/reactivate master | Deny role_not_authorized | Allow own tenant subject to gross archive guard | Existing source safely resolves target |
| Post obligation to active owned master | Allow | Allow | Existing master resolves target |
| Reverse obligation | Deny role_not_authorized | Allow own tenant | Existing original resolves target |
| Other ordinary tenant table read | Zero rows | Zero rows | Global table visibility intended |
| Other tenant RPC reads/writes | Deny tenant_mismatch / same-tenant lookup failure | Deny tenant_mismatch / same-tenant lookup failure | Target-authorized, not categorically denied |
| Direct financial INSERT/UPDATE/DELETE/TRUNCATE | Deny by authenticated grants | Deny | Deny: SA is still authenticated at table privilege boundary |
| Internal helper execution | Deny | Deny | Deny |

## Ordered controlled runtime matrix

### Master lifecycle and duplicate warning

| ID | Actor / action | Expected evidence |
|---|---|---|
| M01 | ADMIN_A creates M_EMPTY, p_id=NULL, one_time, test-only full snapshot | New UUID; adda_id=A; active; created_by/updated_by=ADMIN_A; archive fields NULL. Record UUID immediately. No blind retry on uncertain response. |
| M02 | ADMIN_A edits contact/city/notes with full snapshot | Same UUID/tenant/created metadata; intended changes; updated actor/time. No accidental erasure of other fields. |
| M03 | OP_A and ADMIN_A read master/history and balances | Own master visible; zero balances and counts. |
| M04 | Both search identical name with case/outer whitespace changes | M_EMPTY included, name_match=true. |
| M05 | Both search synthetic mobile with punctuation/space changes | M_EMPTY included, mobile_match=true. Do not expect +92/0 country-code equivalence. |
| M06 | Search only same city with unmatched name/phone | City alone does not cause match. City mismatch does not suppress an actual name/phone match. |
| M07 | OP_A attempts create, edit, archive and reactivate | Each denied role_not_authorized, including create against a unique test-only name. No new master or metadata changes. |
| M08 | ADMIN_A archives empty M_EMPTY | Same UUID, archived metadata with admin actor/time, balances zero. |
| M09 | Duplicate search while archived | SAME archived UUID included; no active-only filter. |
| M10 | ADMIN_A reactivates M_EMPTY | SAME UUID/history/created metadata, active, archive fields cleared. |
| M11 | Invalid business_type/status/blank name, valid authorized fixture | invalid_master_payload / invalid_status. No row change. |

### Obligations, retries and archive gross-side protection

| ID | Actor / action | Expected evidence |
|---|---|---|
| O01 | ADMIN_A creates M_NET and M_BAL with approved distinct test names | Both active in A. |
| O02 | OP_A posts receivable 100 to M_NET with new request UUID | One obligation row; side/amount/date/master/tenant/origin=manual and created_by=OP_A. Capture original ID. |
| O03 | ADMIN_A attempts archive M_NET | gross_obligations_outstanding; remains active. |
| O04 | ADMIN_A posts payable 100 to M_NET with new request UUID | Gross receivable=100, payable=100, net=0; two effective originals. |
| O05 | ADMIN_A again attempts archive | STILL gross_obligations_outstanding; no archive metadata. |
| O06 | OP_A posts receivable 100 to M_BAL: request X, payload A | New row T100; exactly one row for tenant/request X. |
| O07 | SAME OP_A repeats X with identical named payload | SAME T100 UUID; no extra row/count/balance. |
| O08 | SAME actor repeats X with one changed field at a time: amount, side, description, date, reference_no or another approved same-tenant master | idempotency_payload_mismatch; one X row remains. All changed payloads must otherwise be valid. |
| O09 | ADMIN_A repeats X with otherwise same payload | idempotency_payload_mismatch because created_by participates. Idempotency is actor-bound. |
| O10 | ADMIN_A posts receivable 40 (T40) and payable 70 (T70) to M_BAL; distinct requests | Gross receivable=140, payable=70, net=70; counts original=3, reversal=0, effective=3. Correct actor captured on each. |
| O11 | Archive M_EMPTY while empty, then OP_A posts NEW request to archived master | active_other_adda_required; no new row. Reactivate via admin afterward. |
| O12 | Authorized caller supplies zero/negative/>2-decimal/out-of-range numeric, unsupported side; NULL request/date or blank description | invalid_side_or_amount or required_event_payload as appropriate; no new rows. Non-finite numeric API handling may reject before RPC; do not claim server validation was executed unless transport accepts value. Definition/catalog is evidence otherwise. |

Descriptions/references explicitly include TEST and run/case ID. Every successful O02/O04/O06/O10 row must be read back to verify id, request_id, actor, tenant, master, finite exact amount, side, transaction_date, event_type=obligation and origin=manual. There are no payment records or Cashbook operations in these calls.

### Reversal and balance sequence

| ID | Actor / action | Expected evidence |
|---|---|---|
| R01 | OP_A attempts reversal of T40 with valid date/reason/new request | role_not_authorized; no new row. |
| R02 | ADMIN_A reverses T40 with date earlier than original, fresh request | invalid_original; original unchanged and no reversal. |
| R03 | ADMIN_A reverses T40 at D or later, reason TEST/run/case, request Y | NEW row R40, event_type=reversal, reverses_transaction_id=T40, same amount/side/master/tenant; reason in description; admin actor/time. Original T40 persists unchanged. |
| R04 | Read M_BAL balances | Receivable=100, payable=70, net=30; originals=3, reversals=1, effective=2. |
| R05 | SAME admin retries Y, identical reversal parameters | SAME R40 returned; no second reversal. |
| R06 | SAME admin retries Y with changed valid reason/date | idempotency_payload_mismatch; original and reversal unchanged. |
| R07 | Admin uses NEW request to reverse T40 again | already_reversed. This is distinct from successful same-request retry. |
| R08 | Admin attempts reversal of R40 with new request/date/reason | invalid_original; no chain reversal. |
| R09 | ADMIN_A reverses T70 with new request | New same-side payable reversal; gross receivable=100, payable=0, net=100; counts 3/2/1. |
| R10 | Admin tries blank reason or missing request | required_event_payload; no event. |
| R11 | Admin reverses remaining originals on M_NET/M_BAL for completion, then archives | All gross balances zero, effective count zero, original/reversal history retained. Capture all completion event IDs. |
| R12 | SAME original poster retries X identical after its original was reversed and M_BAL archived | SAME T100 returns; does not recreate outstanding balance. Request evidence survives reversal/archive. A fresh request still fails active_other_adda_required. |

Reversal does not preserve the original reference_no on the new event; linkage identifies the original. Original reference remains intact. No partial reversal is supported. Correction is a new separately idempotent obligation after full reversal, not an atomic correction RPC; do not assume both calls succeed together.

### Tenant isolation (live dedicated B fixture required)

Create M_B/T_B only under approved B admin/SA authority; never use an existing business row as a write target. Run symmetric A→B and B→A cases where roles permit. Verify no mutation even if the expected denial message differs by lookup order.

| ID | Actor / action | Expected evidence |
|---|---|---|
| T01 | OP_A and ADMIN_A direct SELECT filtered by M_B/T_B IDs | Successful empty result under RLS; no B fields/amounts visible. Unfiltered reads contain only A rows. |
| T02 | USER_B reads A test masters/transactions | Empty results; own B fixtures visible. |
| T03 | ADMIN_A edits M_B with omitted target | other_adda_not_in_tenant; B master unchanged. |
| T04 | ADMIN_A edits/creates with p_target_adda_id=B | tenant_mismatch; no B row/update. Use a unique TEST name for denied create. |
| T05 | ADMIN_A archives/reactivates M_B | tenant_mismatch; B metadata unchanged. |
| T06 | OP_A and ADMIN_A post to M_B | tenant_mismatch; no transaction. |
| T07 | ADMIN_A reverses T_B | tenant_mismatch; no reversal. OP_A may instead fail role_not_authorized first; both must deny. |
| T08 | OP_A and ADMIN_A call balances/duplicates with supported explicit target B | tenant_mismatch, no B output. Omitted target returns A only. |
| T09 | USER_B performs A-targeted RPCs | Denied by tenant/role checks; no A output/change. Operator B cannot exercise successful admin operations. |
| T10 | Attempt browser tenant spoof using supported target parameter or forged direct INSERT payload on dedicated fixture | Override denied; direct INSERT denied by grants. There is no tenant parameter in posting/reversal. No corrupted tenant/master combination created. |

### Super Admin — optional, contract-derived

| ID | Action | Expected evidence |
|---|---|---|
| S01 | Legitimate active SA direct table read of approved A/B fixture IDs | Both may be visible by intended global SELECT policy. Not an isolation failure. |
| S02 | SA balances/duplicates with explicit A, then B | Each call returns only its selected tenant; no tenant mixing. |
| S03 | SA omits target for reads/master create | If SA profile has NO adda_id: valid_target_adda_required, no insert. If assigned: own assigned tenant fallback is the ACTUAL contract, not an unconditional denial. Any successful create must have an approved dedicated TEST name/assigned-tenant scope. |
| S04 | SA explicitly creates/edits dedicated master for A | Target A honored; correct tenant and SA actor. p_target_adda_id must be included for global SA without assigned tenant. |
| S05 | SA edits B fixture ID while explicitly targeting A | other_adda_not_in_tenant; no cross-tenant corruption. |
| S06 | SA posts/reverses/status-changes approved fixture by ID | Target safely resolves from live source, even without separate target parameter; admin guards apply. Reversal dates/amounts/side and archive gross tests still apply. |
| S07 | SA supplies valid-form UUID confirmed absent from addas in reviewed metadata for target | valid_target_adda_required; no row. Do not fabricate an existing tenant UUID or guess business IDs. |
| S08 | SA direct financial row DML / helper calls | Denied by authenticated grants, despite global read policy. |

If no SA is safely accessible, mark S cases SKIPPED and retain the exact-body evidence; do not claim SA runtime PASS.

### Append-only and privilege boundary

| ID | Probe | Evidence / safe boundary |
|---|---|---|
| P01 | As each authenticated role, direct INSERT of a complete test-only transaction payload | Permission denial; no row. This is a controlled Mode B negative mutation request, not Mode A. |
| P02 | Direct UPDATE of exact dedicated test transaction ID only | Permission denial; row unchanged. Never unfiltered UPDATE. |
| P03 | Direct DELETE of exact dedicated test transaction ID only | Permission denial; row persists. Never unfiltered DELETE. |
| P04 | TRUNCATE | CATALOG ONLY: no effective privilege; enabled BEFORE TRUNCATE guards with exact helper body. Do not execute table-wide destructive SQL in production or via this plan. |
| P05 | Internal-helper execute boundary | Catalog false for authenticated/anon/service. Any optional API check only after approval, with fixture-scoped arguments; unknown-RPC HTTP response alone is not proof of grants. Do not intentionally invoke guard as a business RPC. |
| P06 | Trigger defense beyond grant denial | Catalog exact body/bindings plus unique reversal/tenant constraints. Privileged staging runtime probes require separate approval and a disposable environment. Do not grant browser DML, disable RLS or change deployed objects. |

### Concurrency and uncertain responses (staging preferred)

| ID | Parallel requests | Expected |
|---|---|---|
| C01 | Same actor, same master, same request and payload | Both return SAME transaction UUID; exactly one event/balance effect. |
| C02 | Same tenant/request, different otherwise-valid payloads | Exactly one winner; other receives idempotency_payload_mismatch; one event. |
| C03 | Two admin reversals of one original using DIFFERENT request UUIDs | One new reversal; other already_reversed; unique reversal constraint remains satisfied. |
| C04 | Posting to empty active fixture vs archive | Serialized master-lock outcomes: archive wins → posting active_other_adda_required; posting wins → archive gross_obligations_outstanding. No archived master with a new unreversed obligation. |
| C05 | Lost/uncertain posting response | Retry exact same request/payload/actor; returns existing UUID or creates once if first never committed. Do not generate a new key to resolve uncertainty. Master create is different: inspect dedicated name/identity before retry, as it has no request key. |

Use separate authenticated client sessions for parallel cases, never SQL Editor claim injection. Record timeout/deadlock/transport failures as observations requiring safe same-key retry, not evidence of duplicate success. Do not run concurrency probes on production without explicit scope approval.

## Zero integration and existing-module non-interference

Before any approved Mode B request, save Mode A sections 07–11 as baseline. After completion, a human may rerun the same read-only discovery after approval; no automatic execution is included.

- Compare Cashbook count and both fingerprints. `reference_type='other_adda_payment'` count must remain zero; payment/allocation tables must remain absent.
- Compare bookings, loadings, payment_receipts, expenses and expense_items fingerprints/counts. Do not lock these tables or expect exact equality while unrelated production activity continues.
- Fingerprints are compact diagnostic checksums, not collision-free or causal proof. A change requires review, not an automatic Other Adda failure or attribution. Equality is corroboration, not exhaustive proof of all transient side effects.
- The primary non-interference evidence is complete exact Phase 3A routine bodies, actual trigger bindings/definitions, FK targets and catalog/textual dependency review. Resolve unexpected routines/triggers before testing. pg_depend alone cannot capture all PL/pgSQL/dynamic calls.
- In an isolated quiet staging environment, unchanged baselines are a stronger corroboration. In production, unexplained changes must be investigated read-only; do not inspect/mutate unrelated rows casually. No Phase 3A operation may write these tables even if global activity makes count comparison inconclusive.

## Completion policy and report

Do not delete fixtures or transaction history. Under the approved runtime scope, an authorized admin may fully reverse every successful test obligation with NEW logged request UUIDs, verify both gross sides are zero and archive each master. This is persistent financial correction history, not removal. M_B completion requires B admin/SA. Unexpectedly successful denied requests must be recorded, testing stopped and remediation separately approved; do not improvise destructive cleanup.

Produce a final test report listing per-case PASS/FAIL/BLOCKED/SKIPPED, identities/environment, sanitized evidence, request/event/master IDs, balances, before/after fingerprints, all persistent fixtures and uncompleted reversals. Do not export auth credentials. Stop immediately on cross-tenant visibility/mutation, unexpected DML success, duplicate accounting or integration side effects.

Runtime acceptance requires actual evidence for normal operator/admin allowed and denied paths, tenant isolation in BOTH directions, idempotency and mismatch behavior, gross archive protection, linked immutable reversals and correct balance sequence. Missing sessions/fixtures or unrun required cases are BLOCKED/NOT TESTED, never PASS. Super Admin and advanced staging trigger/concurrency coverage must be explicitly reported if skipped. Completion does not authorize frontend, schema repair or Phase 3B.
