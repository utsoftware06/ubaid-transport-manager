"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import type { ManualDieselCorrectionHistoryView, ManualDieselLinkedPaymentView } from "./manualDieselPaymentTypes";

type Props = {
  links: ManualDieselLinkedPaymentView[];
  history: ManualDieselCorrectionHistoryView[];
  canCorrect: boolean;
  setupState: "ready" | "not_deployed" | "error" | "needs_adda";
  loadError?: string;
  onCorrect: (payment: ManualDieselLinkedPaymentView) => void;
};

function snapshotText(snapshot: Record<string, unknown>, key: string) {
  const value = snapshot[key];
  return value === null || value === undefined || value === "" ? "—" : String(value);
}

function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}

export default function ManualDieselPaymentCorrectionPanel({
  links,
  history,
  canCorrect,
  setupState,
  loadError,
  onCorrect,
}: Props) {
  const { t, dir } = useLanguage();
  return (
    <section dir={dir} className="rounded-xl border border-amber-200 bg-white p-5 shadow-sm">
      <header className="mb-4">
        <h2 className="text-xl font-black text-slate-950">{t("petrolPumpPayments.correction.sectionTitle")}</h2>
        <p className="mt-1 text-sm font-semibold text-slate-700">{t("petrolPumpPayments.correction.sectionDescription")}</p>
      </header>

      {setupState === "not_deployed" && (
        <p className="mb-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-bold text-amber-900">{t("petrolPumpPayments.correction.backendUnavailable")}</p>
      )}
      {setupState === "needs_adda" && (
        <p className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-3 text-sm font-bold text-blue-900">{t("petrolPumpPayments.correction.selectAddaPrompt")}</p>
      )}
      {setupState === "error" && (
        <p className="mb-4 rounded-lg border border-red-300 bg-red-50 p-3 text-sm font-bold text-red-800">{loadError || t("petrolPumpPayments.correction.loadFailed")}</p>
      )}

      <div className="overflow-x-auto rounded-lg border border-slate-200">
        <table className="w-full min-w-[1050px] border-collapse text-sm">
          <thead className="bg-amber-100 text-slate-900"><tr>
            {["voucher", "vehicle", "diesel", "voucherStatus", "payment", "dieselStatus", "actions"].map((key) => <th key={key} className="p-3 text-start">{t(`petrolPumpPayments.correction.columns.${key}`)}</th>)}
          </tr></thead>
          <tbody>
            {links.map((link) => (
              <tr key={link.paymentId} className="border-t border-slate-200 align-top">
                <td className="p-3 font-bold">{link.voucherNumber}</td>
                <td className="p-3">{link.vehicleNo}</td>
                <td className="p-3">#{link.dieselEntryId}<div className="text-xs text-slate-600">{formatAmount(link.dieselTotal)}</div></td>
                <td className="p-3">{t(`petrolPumpPayments.correction.voucherStatuses.${link.voucherStatus}`)}</td>
                <td className="p-3">{link.paymentDate}<div>{formatAmount(link.paidAmount)} · {link.paymentMethod}</div><div className="text-xs text-slate-600">{link.referenceNo || "—"}</div></td>
                <td className="p-3">{formatAmount(link.dieselPaid)} {t("common.paid")}<div>{formatAmount(link.dieselRemaining)} {t("common.remaining")}</div><div>{t(`common.paymentStatus.${link.dieselStatus.toLowerCase()}`)}</div></td>
                <td className="p-3">
                  {canCorrect ? (
                    <button type="button" onClick={() => onCorrect(link)} className="rounded-lg bg-amber-700 px-3 py-2 font-bold text-white hover:bg-amber-800">{t("petrolPumpPayments.correction.correct")}</button>
                  ) : <span className="text-xs font-semibold text-slate-500">{t("petrolPumpPayments.correction.adminOnly")}</span>}
                </td>
              </tr>
            ))}
            {links.length === 0 && <tr><td colSpan={7} className="p-4 text-center text-slate-600">{t("petrolPumpPayments.correction.noLinkedPayments")}</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="mt-6">
        <h3 className="mb-3 text-lg font-black text-slate-950">{t("petrolPumpPayments.correction.historyTitle")}</h3>
        <div className="overflow-x-auto rounded-lg border border-slate-200">
          <table className="w-full min-w-[900px] border-collapse text-sm">
            <thead className="bg-slate-100 text-slate-900"><tr>
              {["date", "voucher", "diesel", "action", "original", "replacement", "reason"].map((key) => <th key={key} className="p-3 text-start">{t(`petrolPumpPayments.correction.historyColumns.${key}`)}</th>)}
            </tr></thead>
            <tbody>
              {history.map((entry) => (
                <tr key={entry.id} className="border-t border-slate-200 align-top">
                  <td className="p-3">{entry.createdAt.slice(0, 16).replace("T", " ")}</td>
                  <td className="p-3 font-bold">{entry.voucherNumber}</td>
                  <td className="p-3">#{entry.dieselEntryId}</td>
                  <td className="p-3">{t(`petrolPumpPayments.correction.actions.${entry.action}`)}</td>
                  <td className="p-3">#{entry.originalPaymentId}<div>{snapshotText(entry.originalSnapshot, "date")} · {formatAmount(Number(entry.originalSnapshot.payment_now ?? 0))}</div></td>
                  <td className="p-3">{entry.replacementPaymentId ? <>#{entry.replacementPaymentId}<div>{snapshotText(entry.replacementSnapshot ?? {}, "payment_date")} · {formatAmount(Number(entry.replacementSnapshot?.payment_now ?? 0))}</div></> : "—"}</td>
                  <td className="max-w-sm whitespace-normal p-3">{entry.reason}</td>
                </tr>
              ))}
              {history.length === 0 && <tr><td colSpan={7} className="p-4 text-center text-slate-600">{t("petrolPumpPayments.correction.noHistory")}</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
