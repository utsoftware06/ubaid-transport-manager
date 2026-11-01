# Adda Account Employee Integration Runtime Test Plan

Run only after deploying, in order:

1. `supabase/preflight/20261005_adda_account_employee_integration_preflight.sql`
2. `supabase/migrations/202610050004_adda_account_employee_integration.sql`
3. `supabase/preflight/20261005_adda_account_employee_integration_post_verify.sql`
4. `supabase/preflight/20261005_adda_account_employee_integration_summary_verify.sql`

Use a designated test Adda and employee. Record the pre-test Adda Account, Employee Salary, Employee Loan, Employee Ledger, and Cashbook totals. Do not use historical salary or loan rows as test fixtures.

## Salary expense projection

1. Create a new salary with basic salary Rs. 30,000, bonus Rs. 0, deduction Rs. 0, and paid amount Rs. 0.
   - `employee_salary_records` and its `employee_salary_generated` transaction each show Rs. 30,000.
   - Adda Account receives exactly one `employee_salary_generated` expense of Rs. 30,000, linked by `salary_record_id` and the same Adda/employee.
   - No Adda Finance settlement or Cashbook row is created by this projection.
   - Adda Account `employee_expense`, total expense, and net profit reflect the one salary expense.
   - Salary is not counted as pending or settled through Adda Finance settlement totals; those totals remain scoped to Adda Finance settlements.

2. Edit only payment fields and pay Rs. 10,000, then pay the remaining Rs. 20,000 in a later edit.
   - The existing Employee Salary/Cashbook flow remains authoritative for each actual payment.
   - Cashbook has the existing `employee_salary` Cash Out evidence only.
   - Adda Account still has one active Rs. 30,000 salary expense and no Adda Finance settlement.

3. Change the generated salary from Rs. 30,000 to Rs. 35,000.
   - The previous Adda journal source stays present and receives one opposite-kind reversal.
   - A new active Rs. 35,000 Adda expense is appended and linked to the same salary record.
   - Active Adda P&L expense for that salary is Rs. 35,000, not Rs. 65,000.
   - Employee generated/paid/recovery rows and the existing Cashbook row match the updated Employee source.

4. Repeat the same Save/Edit payload without changing salary month, employee, or generated amount.
   - No additional Adda journal entry is created.

5. Change `salary_month` or the employee (where the existing Employee RPC permits it) on an already projected salary.
   - The prior Adda projection is reversed and one new projection is appended with the corrected date/employee link.
   - Cross-Adda employee reassignment is rejected by the existing Employee RPC and the transaction leaves no partial Adda journal changes.

6. Delete/cancel a projected salary using `delete_employee_salary` where existing recovery/delete validation permits it.
   - The Adda journal source remains and has one opposite-kind reversal.
   - Employee child transactions, the salary row, and existing salary Cashbook row follow the existing delete RPC behavior.
   - No Adda journal row is deleted, and no second Cashbook entry is created.

7. Attempt to add an Adda Finance settlement to the salary journal entry.
   - The existing `settle_adda_account_entry` rejects `employee_salary_generated` sources.
   - Salary status in the Adda Account ledger shows “Employee module”; settled/pending columns show no Adda settlement values.

## Loan receivable visibility

8. Create an Employee Loan of Rs. 20,000 through the existing Employee Loan RPC.
   - Existing Cashbook posts its single `employee_loan` Cash Out.
   - Adda Account Employee Loan Receivable rises by Rs. 20,000.
   - Adda income, expense, and net profit do not change.

9. Recover Rs. 5,000 through the existing salary loan-recovery flow.
   - Employee loan `recovered_amount` and `remaining_amount` are updated by the Employee Salary RPC.
   - Adda Account Employee Loan Receivable shows Rs. 15,000.
   - Adda P&L and Cashbook receive no additional loan recovery posting from this integration.

10. Try viewing the same loan receipt using a different Adda context.
    - `get_adda_employee_loan_receivable` resolves the authenticated tenant server-side and does not return another Adda’s loan balance.

## Cutover, permissions, and reconciliation

11. Confirm salary rows at or below `adda_employee_salary_projection_cutover.max_existing_salary_id` have no generated Adda journal projection from migration deployment. Editing one of those pre-cutover salaries does not silently backfill it.

12. Confirm a newly created salary with a positive generated amount is projected even if it was initially zero and later changed to a positive amount, provided its ID is above the captured cutover value.

13. Verify Adda Admin and Super Admin behavior through the existing Salary RPC and selected Adda context. Verify Operator salary writes remain governed by the existing Employee role contract; the projection has no browser-side write path.

14. Compare Adda summary and ledger totals:
    - `employee_expense` equals active non-reversed `employee_salary_generated` journal rows for the selected period.
    - total expense includes salary once; net profit is income minus expense.
    - employee loan principal is visible only in the separate receivable card and is excluded from P&L.

15. Inspect Cashbook before and after every step. This migration must not create `employee_salary` or `employee_loan` Cashbook entries; only the existing Employee RPCs write those rows.

## Expected source conventions

- Adda journal salary source type: `employee_salary_generated` (the existing Phase 1 guard/category contract).
- Initial source ID: `employee_salary_records.id::text`.
- Revised projection source ID: salary ID plus a unique revision UUID; `salary_record_id` remains the authoritative link to the salary row.
- Existing Employee generated transaction reference: `employee_salary_generated` / salary ID text.
- Existing salary cash reference: `employee_salary` / salary ID text.
- Existing loan cash reference: `employee_loan` / loan ID text.
- Loan receivable: tenant-scoped sum of authoritative `employee_loans.remaining_amount`.
