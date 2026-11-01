import Link from "next/link";
import { ExternalLink, X } from "lucide-react";

import type { OwnerGariTransaction } from "./types";

type Props = {
  transaction: OwnerGariTransaction;
  onClose: () => void;
  t: (key: string) => string;
};

function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

export default function OwnerGariAccountDetailModal({ transaction, onClose, t }: Props) {
  const fields = [
    [t("ownerGariAccount.table.date"), transaction.transaction_date],
    [t("ownerGariAccount.table.vehicle"), transaction.vehicle_no || "—"],
    [t("ownerGariAccount.table.owner"), transaction.owner_name || "—"],
    [t("ownerGariAccount.table.transactionType"), t(`ownerGariAccount.transactionTypes.${transaction.transaction_type}`)],
    [t("ownerGariAccount.table.reference"), transaction.reference_no || "—"],
    [t("ownerGariAccount.detail.signedAmount"), money(transaction.signed_amount)],
    [t("ownerGariAccount.table.runningBalance"), money(transaction.running_balance)],
    [t("ownerGariAccount.detail.settlement"), transaction.source_settlement_id || transaction.source_manual_settlement_id || "—"],
    ["Manual Adjustment", transaction.source_manual_adjustment_id || "—"],
    ...(transaction.adjustment_no ? [["Adjustment No.", transaction.adjustment_no]] : []),
    ...(transaction.adjustment_reason ? [["Adjustment Reason", transaction.adjustment_reason]] : []),
    [t("ownerGariAccount.detail.movementGroup"), transaction.movement_group_id || "—"],
    [t("ownerGariAccount.detail.voucherId"), transaction.voucher_id?.toString() || "—"],
    ...(transaction.source_commission_event_id ? [
      [t("ownerGariAccount.detail.commissionMonth"), transaction.commission_month?.slice(0, 7) || "—"],
      [t("ownerGariAccount.detail.commissionEvent"), transaction.source_commission_event_id],
      [t("ownerGariAccount.detail.commissionEventType"), transaction.commission_event_type || "—"],
      [t("ownerGariAccount.detail.commissionRoot"), transaction.commission_root_event_id || "—"],
      [t("ownerGariAccount.detail.commissionEffective"), transaction.commission_effective_root_amount == null ? "—" : money(transaction.commission_effective_root_amount)],
      [t("ownerGariAccount.detail.commissionReason"), transaction.commission_correction_reason || transaction.commission_reversal_reason || "—"],
    ] : []),
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4" role="dialog" aria-modal="true">
      <div className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-2xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-slate-200 p-5">
          <div>
            <h2 className="text-2xl font-black text-slate-950">{t("ownerGariAccount.detail.title")}</h2>
            <p className="mt-1 font-medium text-slate-600">{transaction.description}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t("common.actions.close")} className="rounded-lg p-2 text-slate-600 hover:bg-slate-100">
            <X size={22} />
          </button>
        </div>

        <div className="grid gap-3 p-5 sm:grid-cols-2">
          {fields.map(([label, value]) => (
            <div key={label} className="rounded-xl border border-slate-200 bg-slate-50 p-4">
              <p className="text-xs font-black uppercase tracking-wide text-slate-500">{label}</p>
              <p className="mt-2 break-words font-bold text-slate-950">{value}</p>
            </div>
          ))}
        </div>

        {(transaction.transaction_type === "chakkar_net_credit" || transaction.transaction_type === "manual_chakkar_net" || transaction.transaction_type === "manual_chakkar_adjustment") && (
          <div className="flex flex-wrap gap-3 border-t border-slate-200 p-5">
            {transaction.transaction_type === "chakkar_net_credit" && transaction.movement_group_id && (
              <Link href={`/bilty?movementGroupId=${encodeURIComponent(transaction.movement_group_id)}`} className="inline-flex items-center gap-2 rounded-xl bg-blue-700 px-4 py-3 font-black text-white hover:bg-blue-800">
                <ExternalLink size={17} /> {t("ownerGariAccount.actions.viewChakkar")}
              </Link>
            )}
            {transaction.voucher_id !== null && (
              <Link href={`/expenses?voucherId=${transaction.voucher_id}`} className="inline-flex items-center gap-2 rounded-xl bg-violet-100 px-4 py-3 font-black text-violet-800 hover:bg-violet-200">
                <ExternalLink size={17} /> {t("ownerGariAccount.actions.viewVoucher")}
              </Link>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
