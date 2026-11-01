# Manual Diesel Voucher Payment Runtime Test Plan

Run `supabase/preflight/20261012_manual_diesel_pump_adda_diagnostic.sql` first and confirm the selected Manual Voucher Adda, Vehicle Adda, pump history, and resolver result agree. A cross-Adda, unresolved, or mixed-history Pump must remain blocked; do not weaken the resolver to make the test pass.

After the payment migration is deployed, create a Manual Voucher Diesel entry for LES-1234 with 632 litres at Rs. 401. Confirm the source total and linked Fuel expense are Rs. 253,432. Enter Rs. 50,000 paid, choose a payment date and method, and save. Expected: Diesel `paid_amount` Rs. 50,000, `remaining_amount` Rs. 203,432, status `Partial`; one Petrol Pump Payment and one allocation; one Cashbook OUT for actual `payment_now` Rs. 50,000; Voucher expense remains Rs. 253,432.

Repeat with paid amount 0 and with the full Rs. 253,432. Expected statuses are `Unpaid` and `Paid`, respectively. Verify negative, over-total, non-finite, and sub-cent payment values are rejected in the browser and by the protected RPC.

Retry the same saved request and confirm no second payment/allocation/Cashbook row. Edit an unpaid Draft Diesel source, then verify the linked Fuel amount updates to the full recalculated total. After any allocation exists, source and payment fields are locked; an unchanged Manual Voucher save remains a no-op for the paid Diesel source. Verify a finalized Voucher rejects new Diesel edits.

Before validating the Rs. 50,000 case, ensure no earlier Pump opening payable or older Diesel balance will be paid first by the existing allocator. If the allocator assigns any part elsewhere, the wrapper must roll back and return `MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE`; clear the earlier payable using the existing Petrol Pump Payments workflow, then retry.

Regression: create and update Bilty Diesel through its existing Loading path; verify its tenant validation, pump allocations, paid/remaining/status, and Cashbook behavior remain unchanged. Confirm no fake Loading, Bilty, or Movement Group is created, no generic Manual Voucher Cashbook entry appears, Manual finalization deducts the full Diesel expense once, and Owner/Gari/Monthly Hisab retain their existing net-settlement behavior.
