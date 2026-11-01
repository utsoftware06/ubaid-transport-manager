Adda Account Phase 1 runtime test plan

## Scope and safety

Phase 1 creates the prospective Adda Finance foundation only. It does not post
historical Loading margins, Salary expenses, or vehicle commissions. It does
not connect Loading, Bilty, Employee Salary, Owner/Gari, or Cashbook writers.
No production SQL should be used for fixture-based tests. Run mutation tests in
an isolated staging project or a disposable local database, using controlled
test identities and a transaction that is rolled back.

The new tables have no browser DML grants. Their append-only guards accept
inserts only under the trusted `ut.adda_finance_rpc='on'` context; Phase 1 does
not yet provide an application writer RPC. Direct UPDATE, DELETE, and TRUNCATE
are always rejected for journal, settlement, and commission-event history.

## Phase 1 checks

1. **Empty prospective ledger:** After migration, all five new tables have
   zero rows. No historical source records were copied or projected.
2. **Adda Admin own-Adda read:** With an active Adda Admin JWT, call each read
   RPC with the profile Adda. Categories return currently provisioned active
   categories (zero rows initially); summary returns one row of zero totals;
   ledger returns zero rows.
3. **Adda Admin cross-Adda read:** Call the read RPC with another Adda ID.
   The authorization helper must reject it; no data is returned.
4. **Operator read:** An active Operator can call the category, summary, and
   ledger RPCs for the profile Adda and receives tenant-scoped results.
5. **Operator cannot write directly:** Direct INSERT/UPDATE/DELETE/TRUNCATE
   against each new table fails at the privilege boundary. No row changes.
6. **Anon cannot access:** Anon has no table privileges and no execute grant
   on any Phase 1 RPC. Calls/access fail without exposing data.
7. **Super Admin explicit Adda:** A Super Admin passes one selected Adda ID to
   each read RPC and sees only that Adda. A NULL Adda selection is rejected;
   results never aggregate all Addas implicitly.
8. **Direct INSERT blocked:** For authenticated browser and anon roles, direct
   inserts fail. In a staging-only trusted connection, an insert without the
   transaction-local protected context fails the guard.
9. **Direct UPDATE blocked:** In staging, attempts to update a journal,
   settlement, or commission event fail, including from a trusted context.
10. **Direct DELETE blocked:** In staging, attempts to delete any of those
    append-only rows fail, including from a trusted context.
11. **Duplicate source identity blocked:** In a rolled-back staging fixture,
    a second original journal row for the same `(adda_id, source_type,
    source_id)` fails the partial unique index.
12. **Duplicate request identity blocked:** Reusing one request UUID in the
    same Adda fails independently for journal, settlement, and commission
    events. The same UUID in a different Adda remains a separate tenant key.
13. **Duplicate reversal blocked:** A second journal reversal, settlement
    reversal, or commission-event reversal referencing the same original
    fails. Reversal guards also reject a wrong tenant/source/amount or wrong
    event direction.
14. **Cross-Adda category link blocked:** A journal entry cannot reference a
   category owned by another Adda, even if its category UUID is known.
   Manual categories are accepted only for manual expenses; system categories
   are accepted only for their matching protected source and direction.
15. **Cross-Adda vehicle setting blocked:** A commission setting/event cannot
    pair an Adda with a Vehicle belonging to another Adda.
16. **Accounting month contract:** A first-of-month `accounting_month` is
    accepted; any other day is rejected by the check constraint. The writer
    added in a later phase must normalize user input before insert or return a
    validation error; the table does not silently rewrite it.
17. **One commission per vehicle/month:** Two original commission events for
    the same Adda, Vehicle, and month cannot coexist. A reversal does not free
    the original identity for a second commission; correction requires a
    separately approved future workflow.
18. **Empty summary:** The summary RPC returns exactly one row; all numeric
    values are zero, not NULL. Invalid date ranges are rejected.
19. **Stable ledger pagination:** Repeated calls with the same filters return
    a stable ordering by `entry_date DESC, created_at DESC, id DESC`; adjacent
    limit/offset pages do not overlap when the source set is unchanged.
20. **No historical postings:** Compare pre/post counts for existing Loadings,
    Salary, Owner/Gari transactions, and the five new tables. Existing source
    counts remain unchanged; all new Phase 1 tables remain empty.
21. **Period-aware journal reversal:** In a rolled-back staging fixture, post
    an income entry in one period and its equal opposite-kind reversal in a
    later period. The first period retains the original income, the later
    period reports the compensating expense, and a range covering both nets
    them to zero. Pending/settled totals exclude the reversed source.

## Later-phase regression checks

These are recorded now so later writer phases preserve the same foundation:

- An Adda expense recognized on credit changes Adda Expense once and creates
  no Cashbook row until an actual settlement is recorded.
- A later partial settlement changes only the paid/pending presentation and
  creates Cashbook Out for the actual amount, without a second expense.
- Other Income can be recognized before collection; only actual receipts
  create Cashbook In.
- Reversal preserves the source journal and settlement rows, appends opposite
  events, and reverses Cashbook only for actual cash previously moved.
- Loading margin, monthly commission, and generated Salary Expense each post
  once from their source identity and never create a fake Cashbook movement.
- All read/write attempts across Addas fail closed, including explicit
  Super-Admin selection of a mismatched or missing Adda.
