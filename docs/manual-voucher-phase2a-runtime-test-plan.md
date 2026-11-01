# Manual Voucher Phase 2A runtime test plan

Run only after the read-only preflight passes and the migration, post-verifier, and summary verifier have been run in the requested order. Use a test Adda/vehicle and do not use production financial examples without authorization.

## Draft and expense handling

1. Confirm the default Create Voucher mode remains Bilty Based and its existing create/edit/finalize flow still works.
2. Switch to Manual / Without Bilty; confirm no Bilty, Movement Group, or Loading is requested or created.
3. Save a Phase 1 Manual draft with Outbound only and no expenses; reopen it and verify the saved fields remain intact.
4. Save Local-only, Return-only, multiple Local rows, and Outbound + multiple Local + Return freight combinations; verify displayed totals.
5. Add plain regular expenses (for example Toll Tax and Food), save, reload, and verify the persisted items and total.
6. Confirm Fuel/Diesel, Workshop, Oil, Tyre, and Driver Salary source-linked choices are not available in Manual mode.
7. Save with an incomplete expense row, unsupported type, zero/negative amount, excess decimal precision, invalid Chakkar Days, or no positive freight; verify the UI/RPC rejects it without partial saves.
8. Edit a Manual draft, change freight and expense rows, add/remove Local rows, and save; verify one Voucher and replacement rows only.
9. Delete a draft with only eligible plain expense rows; verify the draft rows are removed atomically and no Cashbook/settlement/Owner/Gari rows appear.
10. Attempt cross-Adda vehicle/driver use with an authenticated test user; verify RPC rejection.

## Finalization and accounting

11. Finalize a positive-net sample and compare the Manual settlement totals with freight and saved expense rows.
12. Retry finalization; verify it returns the same settlement and does not add a second settlement or Owner/Gari projection.
13. Verify Owner/Gari receives exactly one signed `manual_chakkar_net` row linked to that settlement, for the exact net and Voucher date.
14. Verify no `vehicle_chakkar_settlements` row, Bilty, Movement Group, Loading, or Cashbook row was created for Manual freight or expense entry/finalization.
15. Finalize a negative-net sample; verify the Owner/Gari amount is negative and the settlement net is negative by the same amount.
16. Finalize a zero-net sample; verify the consistent zero-valued source projection and that totals do not present it as profit.
17. Try to edit/delete a finalized Manual Voucher and its freight/expense rows through the UI and authorized RPCs; verify read-only rejection.
18. Confirm draft and finalized status display correctly; print both and verify Voucher number/type/date, Vehicle/Driver, Chakkar Days, freight lines, expense details, totals, net, and remarks.

## Reporting and regression

19. Select the Vehicle Monthly Hisab period containing the Manual settlement; verify it appears with source Manual, Voucher number/date, Chakkar Days, freight, expense, and net snapshot.
20. Verify Monthly Hisab summary freight, expenses, and profit combine Bilty and Manual rows without changing the original Bilty settlement snapshot.
21. Print Monthly Hisab and an individual Manual Chakkar; verify no fabricated Movement Group or Return Bilty is displayed.
22. Open Owner / Gari Account; verify transaction type, signed credit/debit, running/closing balance, settlement source, and View Voucher drill-down.
23. Check Manual row display in Owner / Gari filters/search and the signed credit/debit summary for positive/negative/zero results.
24. Confirm a Bilty Voucher with its existing finalizer still creates the normal `vehicle_chakkar_settlements` and `chakkar_net_credit` exactly once.
25. Compare before/after counts for Cashbook, Bilty settlements, and unrelated Owner/Gari sources; no Manual test should affect those sources.
