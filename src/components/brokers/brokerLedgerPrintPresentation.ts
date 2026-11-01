import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation } from "@/components/print/LedgerStatementPrint";
import { formatAmount, getTransactionEffect, type BrokerRow, type BrokerTransactionRow } from "./Brokers";

function transactionType(language: PrintLanguage, type: string) {
  const key: Record<string, string> = {
    "Broker Payable": "payable", "Payment To Broker": "paymentTo", "Payment From Broker": "paymentFrom",
    "Advance To Broker": "advanceTo", Adjustment: "adjustment",
  };
  return key[type] ? translateLedgerPrint(language, `brokers.transactionTypes.${key[type]}`) : type;
}

function paymentMethod(language: PrintLanguage, method: string) {
  const key: Record<string, string> = { Cash: "cash", Bank: "bank", Cheque: "cheque", "Online Transfer": "onlineTransfer", Account: "account" };
  return key[method] ? translateLedgerPrint(language, `brokers.paymentMethods.${key[method]}`) : method;
}

export function brokerLedgerPrintPresentation(broker: BrokerRow, transactions: BrokerTransactionRow[], allTransactions: BrokerTransactionRow[], addaId: string, language: PrintLanguage, singleEntry = false, period?: { fromDate: string; toDate: string }): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const rows = transactions.map((item) => {
    const effect = getTransactionEffect(item.transactionType, item.amount);
    return [item.transactionDate || "—", transactionType(language, item.transactionType), item.description || "—", item.loadingNo || "—", item.vehicleNo || "—", item.driverName || "—", paymentMethod(language, item.paymentMethod), item.referenceNo || "—", effect > 0 ? formatAmount(effect) : "—", effect < 0 ? formatAmount(Math.abs(effect)) : "—", formatAmount(item.runningBalance)];
  });
  const beforePeriod = period?.fromDate
    ? allTransactions.filter((item) => item.transactionDate < period.fromDate)
    : [];
  const throughPeriodEnd = period?.toDate
    ? allTransactions.filter((item) => item.transactionDate <= period.toDate)
    : allTransactions;
  const periodOpening = period?.fromDate
    ? beforePeriod.at(-1)?.runningBalance ?? broker.openingBalance
    : broker.openingBalance;
  const periodClosing = period?.toDate
    ? throughPeriodEnd.at(-1)?.runningBalance ?? broker.openingBalance
    : broker.currentBalance;
  return {
    documentType: "broker_ledger",
    title: tr(singleEntry ? "brokerLedger.print.entryTitle" : "brokerLedger.title"),
    subtitle: singleEntry ? transactionType(language, transactions[0]?.transactionType ?? "") : tr("brokerLedger.title"),
    reference: singleEntry ? transactions[0]?.referenceNo || undefined : broker.brokerName,
    fields: [
      { label: tr("brokers.broker"), value: broker.brokerName },
      ...(broker.contactPerson ? [{ label: tr("brokerLedger.contact"), value: broker.contactPerson }] : []),
      ...(broker.phone ? [{ label: tr("brokers.phone"), value: broker.phone, direction: "ltr" as const }] : []),
      { label: tr("partyLedger.fields.adda"), value: addaId },
      ...(singleEntry && transactions[0] ? [{ label: tr("common.date"), value: transactions[0].transactionDate }] : []),
      ...(!singleEntry && period?.fromDate ? [{ label: tr("common.fromDate"), value: period.fromDate, direction: "ltr" as const }] : []),
      ...(!singleEntry && period?.toDate ? [{ label: tr("common.toDate"), value: period.toDate, direction: "ltr" as const }] : []),
    ],
    summary: singleEntry && transactions[0]
      ? [
          { label: tr("common.amount"), value: formatAmount(transactions[0].amount) },
          { label: tr("brokers.runningBalance"), value: formatAmount(transactions[0].runningBalance) },
        ]
      : [
          { label: tr("brokerLedger.opening"), value: formatAmount(periodOpening) },
          { label: tr("common.balance"), value: formatAmount(periodClosing) },
          { label: tr("brokers.currentBalance"), value: formatAmount(broker.currentBalance) },
          { label: tr("common.status"), value: tr(`brokers.statuses.${broker.balanceStatus.toLowerCase()}`) },
        ],
    tables: [{
      title: tr("brokerLedger.title"),
      columns: [tr("common.date"), tr("brokers.transactions.type"), tr("common.description"), tr("paymentReceipts.loading"), tr("common.vehicle"), tr("common.driver"), tr("brokerLedger.payment"), tr("brokerLedger.reference"), tr("brokerLedger.debit"), tr("brokerLedger.credit"), tr("brokers.runningBalance")],
      rows,
      emptyMessage: tr("brokerLedger.empty"),
    }],
  };
}
