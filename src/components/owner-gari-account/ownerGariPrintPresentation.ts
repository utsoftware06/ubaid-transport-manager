import { translateLedgerPrint, type LedgerPrintPresentation } from "@/components/print/LedgerStatementPrint";
import type { PrintLanguage } from "@/lib/print/types";
import type { OwnerGariMonthlyClosing, OwnerGariWithdrawalReceipt } from "./types";

const money = (value: number) => Number.isFinite(value)
  ? `Rs. ${value.toLocaleString("en-PK", { maximumFractionDigits: 2 })}`
  : "—";

export function ownerGariMonthlyPrintPresentation(report: OwnerGariMonthlyClosing, language: PrintLanguage): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const { account, period, summary } = report;
  const breakdown: Array<[string, number]> = [
    ["chakkarCredit", summary.chakkar_credits],
    ["chakkarDebit", summary.chakkar_debits],
    ["ownerWithdrawal", summary.owner_withdrawals],
    ["gariWithdrawal", summary.gari_withdrawals],
    ["voucherExpense", summary.voucher_adjustment_expenses],
    ["manualAdjustmentCredit", summary.manual_adjustment_credits],
    ["manualAdjustmentDebit", summary.manual_adjustment_debits],
    ["addaCommissionNet", summary.adda_commission_net_effect],
    ["ownerCommissionCharge", summary.owner_gari_net_commission_charge],
    ["commissionDifference", summary.commission_reconciliation_difference],
  ];
  return {
    documentType: "owner_gari_account",
    title: tr("ownerGariAccount.monthlyClosing.printTitle"),
    subtitle: period.period_label,
    reference: account.vehicle_no || undefined,
    fields: [
      { label: tr("ownerGariAccount.table.vehicle"), value: account.vehicle_no || "—" },
      ...(account.owner_name ? [{ label: tr("ownerGariAccount.table.owner"), value: account.owner_name }] : []),
      { label: tr("ownerGariAccount.monthlyClosing.period"), value: period.period_label },
      { label: tr("ownerGariAccount.monthlyClosing.currentBalanceAsOf"), value: summary.current_balance_as_of_date, direction: "ltr" },
      { label: tr("ownerGariAccount.monthlyClosing.commissionReconciliation"), value: tr(summary.commission_reconciliation_status === "Matched" ? "ownerGariAccount.monthlyClosing.matched" : "ownerGariAccount.monthlyClosing.difference") },
    ],
    summary: [
      { label: tr("ownerGariAccount.cards.openingBalance"), value: money(summary.opening_balance) },
      { label: tr("ownerGariAccount.monthlyClosing.totalCredits"), value: money(summary.total_credits) },
      { label: tr("ownerGariAccount.monthlyClosing.totalDebits"), value: money(summary.total_debits) },
      { label: tr("ownerGariAccount.cards.closingBalance"), value: money(summary.closing_balance) },
      { label: tr("ownerGariAccount.monthlyClosing.currentBalance"), value: money(summary.current_balance) },
      { label: tr("ownerGariAccount.monthlyClosing.transactionCount"), value: String(summary.transaction_count), direction: "ltr" },
    ],
    tables: [
      {
        title: tr("ownerGariAccount.monthlyClosing.breakdown"),
        columns: [tr("ownerGariAccount.monthlyClosing.category"), tr("common.amount")],
        rows: breakdown.map(([key, amount]) => [tr(`ownerGariAccount.monthlyClosing.${key}`), money(amount)]),
      },
      {
        title: tr("ownerGariAccount.table.title"),
        columns: [tr("ownerGariAccount.table.date"), tr("ownerGariAccount.table.transactionType"), tr("ownerGariAccount.table.reference"), tr("ownerGariAccount.table.description"), tr("ownerGariAccount.table.credit"), tr("ownerGariAccount.table.debit"), tr("ownerGariAccount.table.runningBalance")],
        rows: report.transactions.map((transaction) => [
          transaction.transaction_date || "—",
          tr(`ownerGariAccount.transactionTypes.${transaction.transaction_type}`),
          transaction.reference_no || transaction.movement_group_id || "—",
          transaction.description || "—",
          transaction.credit ? money(transaction.credit) : "—",
          transaction.debit ? money(transaction.debit) : "—",
          money(transaction.running_balance),
        ]),
        emptyMessage: tr("ownerGariAccount.table.empty"),
      },
    ],
  };
}

export function ownerGariWithdrawalPrintPresentation(receipt: OwnerGariWithdrawalReceipt, language: PrintLanguage): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  return {
    documentType: "owner_gari_account",
    title: tr("ownerGariAccount.withdrawal.receiptTitle"),
    subtitle: tr(`ownerGariAccount.transactionTypes.${receipt.transaction_type}`),
    reference: receipt.transaction_id,
    fields: [
      { label: tr("ownerGariAccount.withdrawal.receiptNo"), value: receipt.transaction_id, direction: "ltr" },
      { label: tr("ownerGariAccount.table.vehicle"), value: receipt.vehicle_no || "—" },
      ...(receipt.owner_name ? [{ label: tr("ownerGariAccount.table.owner"), value: receipt.owner_name }] : []),
      { label: tr("ownerGariAccount.withdrawal.date"), value: receipt.transaction_date, direction: "ltr" },
      { label: tr("ownerGariAccount.withdrawal.type"), value: tr(`ownerGariAccount.transactionTypes.${receipt.transaction_type}`) },
      { label: tr("ownerGariAccount.withdrawal.paymentMethod"), value: tr(`ownerGariAccount.withdrawal.paymentMethods.${receipt.payment_method}`) },
      { label: tr("ownerGariAccount.withdrawal.referenceNo"), value: receipt.reference_no || "—" },
      { label: tr("ownerGariAccount.withdrawal.cashbookReference"), value: receipt.cashbook_reference_id, direction: "ltr" },
      { label: tr("ownerGariAccount.withdrawal.remarks"), value: receipt.remarks || "—" },
      { label: tr("ownerGariAccount.withdrawal.preparedBy"), value: receipt.prepared_by || "—" },
    ],
    summary: [{ label: tr("ownerGariAccount.withdrawal.amount"), value: money(receipt.amount) }],
    tables: [],
  };
}
