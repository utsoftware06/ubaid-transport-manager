# Manual Diesel Selected Payment Runtime Test Plan

Run this after applying the selected-payment migration and both verifiers pass.
Use a Draft Manual Voucher on a pump with older unpaid Diesel rows.

1. Create a Manual Diesel entry for Rs. 216,825 and enter Paid Amount Rs. 100,000.
   Confirm the selected Diesel gets paid Rs. 100,000, remaining Rs. 116,825,
   and status Partial.
2. Record the older Diesel row IDs and their paid/remaining values before the
   test. After saving, confirm every older row is unchanged. Confirm the new
   payment has exactly one allocation, and that allocation names only the
   selected Manual Diesel entry.
3. Confirm the Petrol Pump payment is Rs. 100,000 with advance_used = 0 and
   payment_now = 100,000. Confirm exactly one Cashbook Cash Out exists for
   that payment reference with amount Rs. 100,000. The Manual Voucher expense
   remains the full Rs. 216,825.
4. Retry the exact same request. It must return the same Diesel entry and
   payment without creating another payment, allocation, or Cashbook row.
   Retry with a changed amount or payment detail; it must be rejected.
5. In the generic Petrol Pump Payments screen, create an unmarked payment.
   Confirm the established opening-first, Diesel FIFO allocation remains in
   force. Repeat with a normal Bilty Diesel payment and confirm its behavior
   is unchanged.
6. Run a later normal pump accounting rebuild by saving a generic pump
   payment. Confirm marked Manual payments still allocate only to their mapped
   Manual Diesel row, while unmarked payments remain FIFO, and that pump
   payable equals opening liability plus all Diesel remaining amounts.
7. Try editing or deleting a selected Manual Diesel initial payment through
   the generic Petrol Pump payment workflow. It must reject the operation.
   The Manual Diesel wrapper permits only an identical idempotent retry after
   the initial payment; changing payment details or amount is locked.
8. Try a payment greater than the selected Diesel total, a negative payment,
   a cross-Adda pump, a different vehicle/source, and a Finalized Voucher.
   Each must fail without leaving a payment, allocation, or Cashbook row.
9. Try a payment date earlier than the pump's latest existing payment date.
   It must fail with MANUAL_DIESEL_SELECTED_PAYMENT_BACKDATE_NOT_ALLOWED;
   this prevents stale chronological pump-payment summaries without replaying
   prior allocations during the initial selected-payment operation.
   After a selected payment exists, also try creating or editing a generic
   pump payment dated earlier than it; it must fail with
   PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT. This protects
   the selected allocation during later accounting rebuilds.
10. Test unpaid (0) and fully paid (amount = total) Manual Diesel entries.
    Zero creates no pump payment or Cashbook row; full payment records a
    selected allocation equal to the full Diesel expense.

Expected selected-payment example:

| Measure | Expected |
| --- | ---: |
| Manual Diesel total expense | Rs. 216,825 |
| Selected Diesel paid | Rs. 100,000 |
| Selected Diesel remaining | Rs. 116,825 |
| Selected Diesel status | Partial |
| Cashbook OUT | Rs. 100,000 |
| Older Diesel rows | Unchanged |

The package does not execute these tests or production SQL.
