# Our Adda Brokerage / Bilty Margin projection — staging test plan

This package adds a read-only view of existing positive `bilty_margin` income. It does not add a commission, income, payable, receivable, settlement, or Cashbook posting. Run these checks only in a staging project with an operator/admin account and a separate Super Admin account. Do not use production financial records for the runtime smoke test.

## Deployment order

1. Review and apply `supabase/migrations/202610300003_our_adda_brokerage_margin_projection.sql` in staging.
2. Run `supabase/preflight/20261030_our_adda_brokerage_post_verify.sql`.
3. Run `supabase/preflight/20261030_our_adda_brokerage_summary_verify.sql`.
4. Run the UI scenarios below under authenticated staging users.

## Read-only UI scenarios

| Scenario | Setup / action | Expected |
| --- | --- | --- |
| Existing spread and separate external brokerage | Use a staging Booking with party freight 100,000, gross vehicle Kiraya 90,000, external Broker brokerage 5,000, and an existing positive `bilty_margin` of 10,000. Open Brokers for its owning Adda. | One Booking row shows 100,000 party freight, 90,000 gross vehicle Kiraya, 5,000 external brokerage, 85,000 net vehicle entitlement, and 10,000 Our Adda margin. The separate Loading Brokerage Payables panel remains the only place to view/post the external Broker payable and its actual payments. No additional 10,000 income or 5,000 payment is created by viewing. |
| Existing margin realization | Use an existing margin journal with a known Bilty receipt total. | Earned, realized and pending values match Adda Account's authoritative margin summary. They are not recomputed from generic Broker transactions. |
| Other Adda freight collection | Use a Booking whose saved source is `other_adda` and whose full-freight receivable has authorized allocations. | The row labels the existing Other Adda receivable basis and shows the current existing margin realization. No noncash adjustment, extra obligation, or Cashbook event is offered or posted. |
| Unsupported/unknown source | Use a source with null or unsupported `freight_receivable_from`. | UI shows an unresolved basis label; it does not infer a counterparty or mark margin received. |
| Reversed source | Use a recognized margin entry with its authorized reversal. | One Booking-level row remains, marked reversed; realized/pending amounts are blank. Reversal history is not counted as a second earning. |
| Booking identity | Review a Booking with its linked Loading and any historical/reversed source revision. | The projection returns at most one current row for the Booking. A corrupt state with multiple active positive sources causes the read RPC to fail closed with `OUR_ADDA_BROKERAGE_MULTIPLE_ACTIVE_BOOKING_SOURCES`. |
| Filters/pagination | Apply date bounds and search across Booking, Loading, route or Broker, then use page controls. | Date range is applied to the existing margin journal/Loading date; counts and page contents remain consistent. Invalid reversed date ranges are rejected before the RPC. |
| Tenant boundary | As an active Operator/Adda Admin, request another Adda in the RPC or switch the UI selector. As Super Admin, explicitly select each staging Adda. | Cross-Adda request is denied for the tenant user. Super Admin only sees the Adda explicitly selected in the Broker screen. Late responses from the prior Adda do not appear after switching. |
| Projection has no write side effects | Capture staging counts for `adda_account_entries`, `adda_finance_settlements`, `loading_brokerage_accruals`, `loading_brokerage_events`, `other_adda_transactions`, `other_adda_payments`, and `cashbook_entries`; load/filter/refresh this panel and the existing external payable panel without clicking a posting action. | Counts and row contents remain unchanged. The new RPC source has no DML and does not alter the existing external payable/payment flow. |
| Existing workflows | Use existing Bilty vehicle payment and Phase 1 external Broker accrual/payment scenarios separately. | Existing payment cap remains `vehicle_freight - broker_commission + overweight + lolo + detain`; external payable remains Booking-level and is not created once per Loading. No duplicate deduction is applied for Our Adda margin. |

## Limits

This is a staging test plan, not evidence of runtime execution. The migration and verifiers must be deployed and run in staging before the UI is considered runtime-verified. The view deliberately does not create an independent “commission payer” or separate Other Adda adjustment field: settlement basis comes from the existing saved freight-receivable source, and the existing `bilty_margin` journal remains the only Our Adda income source.

The projection shows the existing realization helper's aggregate freight receipt basis and margin realized/pending values. Individual receipt/payment event history remains in the authoritative Bilty or Other Adda ledger; this panel does not copy those events into another statement.
