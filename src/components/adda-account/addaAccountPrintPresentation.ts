import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation } from "@/components/print/LedgerStatementPrint";
import type { AddaAccountEntry, AddaFinanceSettlement, AddaFinanceSummary } from "./types";

const amount = (value: number) => `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;

export function addaAccountPrintPresentation(entry: AddaAccountEntry, settlements: AddaFinanceSettlement[], language: PrintLanguage): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const isExpense = entry.entry_kind === "expense";
  const isIssuedFinanceCommission = entry.source_type === "issued_parchi_financing_commission";
  const sourceManaged = ["bilty_margin", "bilty_loss", "employee_salary_generated", "issued_parchi_financing_commission"].includes(entry.source_type);
  const isBiltyMargin = entry.source_type === "bilty_margin";
  const statusKey = entry.is_reversal ? "reversal" : isIssuedFinanceCommission ? "earned" : entry.entry_status;
  const fields = [
    { label: tr("addaAccount.print.entryType"), value: tr(isExpense ? "addaAccount.filters.expense" : "addaAccount.filters.income") },
    { label: tr("addaAccount.print.date"), value: entry.entry_date || "—" },
    ...(entry.category_name ? [{ label: tr("addaAccount.print.category"), value: entry.category_name }] : []),
    ...(entry.reference_no ? [{ label: tr("addaAccount.print.referenceNo"), value: entry.reference_no }] : []),
    ...(entry.description ? [{ label: tr("addaAccount.print.description"), value: isIssuedFinanceCommission ? tr("addaAccount.ledger.issuedFinance") : entry.description }] : []),
    ...(entry.remarks ? [{ label: tr("addaAccount.print.remarks"), value: entry.remarks }] : []),
    ...(entry.booking_id ? [{ label: tr("common.booking"), value: entry.booking_id, direction: "ltr" as const }] : []),
    ...(entry.loading_id !== null ? [{ label: tr("common.loadingNo"), value: String(entry.loading_id), direction: "ltr" as const }] : []),
    ...(entry.vehicle_id ? [{ label: tr("common.vehicle"), value: entry.vehicle_id, direction: "ltr" as const }] : []),
    { label: tr("addaAccount.print.status"), value: tr(`addaAccount.status.${statusKey}`) },
  ];
  const summary = [
    { label: tr("addaAccount.print.totalAmount"), value: amount(entry.amount) },
    ...(isBiltyMargin
      ? [
          ...(entry.earned_amount !== null ? [{ label: tr("addaAccount.print.earnedAmount"), value: amount(entry.earned_amount) }] : []),
          ...(entry.realized_amount !== null ? [{ label: tr("addaAccount.print.realizedAmount"), value: amount(entry.realized_amount) }] : []),
          ...(entry.margin_pending_amount !== null ? [{ label: tr("addaAccount.print.marginPendingAmount"), value: amount(entry.margin_pending_amount) }] : []),
          ...(entry.received_basis_amount !== null ? [{ label: tr("addaAccount.print.receivedBasisAmount"), value: amount(entry.received_basis_amount) }] : []),
        ]
      : [
          ...(!sourceManaged ? [{ label: tr("addaAccount.print.settledAmount"), value: amount(entry.net_settled_amount) }] : []),
          ...(!sourceManaged ? [{ label: tr("addaAccount.print.pendingAmount"), value: amount(entry.pending_amount) }] : []),
        ]),
  ];
  const historyRows = settlements.map((item) => [
    item.payment_date || "—",
    tr(item.event_type === "settlement" ? "addaAccount.settlement.settlement" : "addaAccount.settlement.reversal"),
    amount(item.amount), item.payment_method || "—", item.cashbook_entry_type || "—",
    item.reference_no || item.reversal_reason || item.cashbook_reference_id || "—",
  ]);
  if (sourceManaged) historyRows.push([tr("addaAccount.print.paymentHistory"), "—", "—", "—", "—", tr(isBiltyMargin ? "addaAccount.print.marginReceiptNote" : isIssuedFinanceCommission ? "addaAccount.ledger.issuedFinanceNoCash" : "addaAccount.print.sourceManagedNote")]);
  return {
    documentType: "adda_account",
    title: tr(isExpense ? "addaAccount.print.expenseTitle" : "addaAccount.print.incomeTitle"),
    subtitle: tr("addaAccount.print.entryType"),
    reference: entry.reference_no || entry.source_id,
    fields,
    summary,
    tables: [{
      title: tr("addaAccount.print.paymentHistory"),
      columns: [tr("addaAccount.print.paymentDate"), tr("addaAccount.print.event"), tr("addaAccount.print.amount"), tr("addaAccount.print.paymentMethod"), tr("addaAccount.print.cashbookDirection"), tr("addaAccount.print.referenceNo")],
      rows: historyRows,
      emptyMessage: tr("addaAccount.print.noPayments"),
    }],
  };
}

export function addaAccountStatementPrintPresentation(
  entries: AddaAccountEntry[],
  summary: AddaFinanceSummary,
  employeeLoanReceivable: number | null,
  period: { from: string | null; to: string | null },
  language: PrintLanguage,
): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const statusKey = (entry: AddaAccountEntry) => {
    if (entry.is_reversed) return "reversed";
    if (entry.is_reversal) return "reversal";
    if (entry.source_type === "bilty_margin") return entry.realization_status === "realized" ? "realized" : entry.realization_status === "partial" ? "partial" : entry.realization_status === "pending" ? "marginPending" : "earned";
    if (entry.source_type === "bilty_loss") return "recognizedLoss";
    if (entry.source_type === "employee_salary_generated") return "employeeManaged";
    if (entry.source_type === "issued_parchi_financing_commission") return "earned";
    return entry.entry_status === "settled" ? "paid" : entry.entry_status === "partial" ? "partial" : "unpaid";
  };
  const reference = (entry: AddaAccountEntry) => entry.source_type === "bilty_margin" || entry.source_type === "bilty_loss"
    ? entry.loading_details?.booking_no || entry.loading_details?.loading_no || (entry.loading_id ? `#${entry.loading_id}` : entry.source_id)
    : entry.reference_no ?? entry.source_id.slice(0, 8);
  const tableRows = entries.map((entry) => {
    const margin = entry.source_type === "bilty_margin";
    return [
      entry.entry_date,
      tr(entry.is_reversal ? "addaAccount.status.reversal" : entry.entry_kind === "income" ? "addaAccount.filters.income" : "addaAccount.filters.expense"),
      entry.category_name ?? "—",
      reference(entry),
      entry.source_type === "issued_parchi_financing_commission" ? tr("addaAccount.ledger.issuedFinance") : entry.description || entry.source_type,
      entry.entry_kind === "income" ? amount(entry.amount) : "—",
      entry.entry_kind === "expense" ? amount(entry.amount) : "—",
      entry.source_type === "employee_salary_generated" || entry.source_type === "bilty_loss" || entry.source_type === "issued_parchi_financing_commission" ? "—" : margin ? entry.realized_amount === null ? "—" : amount(entry.realized_amount) : amount(entry.net_settled_amount),
      entry.source_type === "employee_salary_generated" || entry.source_type === "bilty_loss" || entry.source_type === "issued_parchi_financing_commission" ? "—" : margin ? entry.margin_pending_amount === null ? "—" : amount(entry.margin_pending_amount) : amount(entry.pending_amount),
      tr(`addaAccount.status.${statusKey(entry)}`),
    ];
  });
  const labels: Array<[string, number | null]> = [
    ["totalIncome", summary.total_income], ["biltyMarginIncome", summary.bilty_margin_income],
    ["vehicleCommission", summary.vehicle_commission_effective], ["biltyMarginRealized", summary.bilty_margin_realized],
    ["issuedFreightFinanceCommission", summary.issued_freight_financing_commission_income],
    ["biltyMarginPending", summary.bilty_margin_pending], ["otherIncome", summary.other_income],
    ["totalExpense", summary.total_expense], ["biltyLossExpense", summary.bilty_loss_expense],
    ["employeeExpense", summary.employee_expense], ["netProfit", summary.net_profit],
    ["pendingIncome", summary.pending_income], ["pendingExpense", summary.pending_expense],
  ];
  return {
    documentType: "adda_account",
    title: tr("addaAccount.ledger.title"),
    subtitle: `${tr("addaAccount.filters.from")}: ${period.from ?? "—"} · ${tr("addaAccount.filters.to")}: ${period.to ?? "—"}`,
    fields: [],
    summary: [
      ...labels.map(([key, value]) => ({ label: tr(`addaAccount.summary.${key}`), value: value === null ? "—" : amount(value) })),
      ...(employeeLoanReceivable === null ? [] : [{ label: tr("addaAccount.summary.employeeLoanReceivable"), value: amount(employeeLoanReceivable) }]),
      { label: tr("addaAccount.summary.settledIncome"), value: amount(summary.settled_income) },
      { label: tr("addaAccount.summary.settledExpense"), value: amount(summary.settled_expense) },
      { label: tr("addaAccount.summary.biltyMarginEarned"), value: amount(summary.bilty_margin_earned) },
    ],
    tables: [{
      title: tr("addaAccount.ledger.title"),
      columns: ["date", "type", "category", "reference", "description", "income", "expense", "settled", "pending", "status"].map((key) => tr(`addaAccount.ledger.${key}`)),
      rows: tableRows,
      emptyMessage: tr("addaAccount.ledger.empty"),
    }],
  };
}
