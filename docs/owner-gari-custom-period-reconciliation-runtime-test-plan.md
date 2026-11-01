# Owner/Gari Custom Period Closing and Commission Reconciliation

## Deployment order

1. Run `supabase/preflight/20261009_owner_gari_custom_period_reconciliation_preflight.sql` and its single-grid summary.
2. Review and deploy `supabase/migrations/202610090001_owner_gari_custom_period_reconciliation.sql`.
3. Run `supabase/preflight/20261009_owner_gari_custom_period_reconciliation_post_verify.sql` and `supabase/preflight/20261009_owner_gari_custom_period_reconciliation_summary_verify.sql`.
4. Run the runtime cases below in the application.

No production SQL was executed while preparing this change. The migration adds a read-only RPC; it does not write or backfill financial rows.

## Runtime cases

Use vehicle AKK 2178 and compare the RPC output with the full Owner/Gari ledger.

| Case | Input/action | Expected |
| --- | --- | --- |
| Custom September range | Date From 2026-09-08, Date To 2026-09-10 | Custom mode and inclusive range; owner commission rows 0, paired Adda effect 0, difference 0. Opening is the signed balance before Sep 8. |
| October month | Clear both custom dates; select October 2026 | Month mode for Oct 1–31; owner commission charge Rs.10,000, event-paired Adda effect Rs.10,000, difference Rs.0, Matched. |
| Narrow October range | Set both custom dates within October | Only Owner/Gari transactions and paired journal events whose accounting dates fall in that range contribute. |
| Partial custom range | Set only Date From or only Date To and apply | Closing cards show validation; no mixed month/range result is requested. |
| Reset | Reset filters after a custom range | Both custom dates clear, the selected closing month remains, and closing returns to month mode. |
| Search/type filter | Filter the visible Owner/Gari statement rows | Closing totals and reconciliation remain the complete active-period values. |
| Print | Print while in custom mode, then month mode | Printed summary and transaction rows use the same V2 period and include all rows for that period, regardless of table filters. |
| Later reversal | Compare October original with a reversal posted in November | October retains its October posting; November reports the reversal in November. No current-lineage rewrite of October. |

For all cases, confirm sign-based Credit/Debit and running balances, and verify the returned current balance is explicitly labeled as of `current_balance_as_of_date`. No Cashbook rows or financial postings should be created by loading, filtering, or printing the closing report.
