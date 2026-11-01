import { Eye, Printer, RotateCcw, Truck } from "lucide-react";

import type { OwnerGariTransaction } from "./types";

type Props = {
  rows: OwnerGariTransaction[];
  loading: boolean;
  onView: (row: OwnerGariTransaction) => void;
  onPrintReceipt: (row: OwnerGariTransaction) => void;
  onReverseWithdrawal: (row: OwnerGariTransaction) => void;
  reversingTransactionId: string | null;
  t: (key: string) => string;
};

function money(value: number) {
  return value
    ? `Rs. ${Number(value).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`
    : "—";
}

export default function OwnerGariAccountTable({
  rows,
  loading,
  onView,
  onPrintReceipt,
  onReverseWithdrawal,
  reversingTransactionId,
  t,
}: Props) {
  const headings = [
    "date",
    "vehicle",
    "owner",
    "transactionType",
    "reference",
    "credit",
    "debit",
    "runningBalance",
    "description",
    "actions",
  ];

  return (
    <section className="overflow-hidden rounded-2xl bg-white shadow-md">
      <div className="border-b border-slate-200 p-5">
        <h2 className="text-xl font-black text-slate-950">
          {t("ownerGariAccount.table.title")}
        </h2>
        <p className="mt-1 font-medium text-slate-600">
          {t("ownerGariAccount.table.subtitle")}
        </p>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[1400px] text-sm">
          <thead className="bg-blue-700 text-white">
            <tr>
              {headings.map((heading) => (
                <th key={heading} className="px-4 py-3 text-start font-black">
                  {t(`ownerGariAccount.table.${heading}`)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {rows.map((row) => (
              <tr key={row.transaction_id} className="hover:bg-blue-50/60">
                <td className="px-4 py-3 font-semibold">{row.transaction_date}</td>
                <td className="px-4 py-3 font-bold">{row.vehicle_no || "—"}</td>
                <td className="px-4 py-3">{row.owner_name || "—"}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-3 py-1 text-xs font-black ${
                    row.signed_amount < 0
                      ? "bg-red-100 text-red-800"
                      : "bg-emerald-100 text-emerald-800"
                  }`}>
                    {t(`ownerGariAccount.transactionTypes.${row.transaction_type}`)}
                  </span>
                </td>
                <td className="max-w-56 px-4 py-3 font-mono text-xs">
                  {row.reference_no || row.movement_group_id || "—"}
                </td>
                <td className="px-4 py-3 text-end font-bold text-emerald-700 [direction:ltr]">
                  {money(row.signed_amount > 0 ? row.signed_amount : 0)}
                </td>
                <td className="px-4 py-3 text-end font-bold text-red-700 [direction:ltr]">
                  {money(row.signed_amount < 0 ? -row.signed_amount : 0)}
                </td>
                <td className={`px-4 py-3 text-end font-black [direction:ltr] ${
                  row.running_balance < 0 ? "text-red-700" : "text-slate-950"
                }`}>
                  {money(row.running_balance)}
                </td>
                <td className="max-w-72 px-4 py-3 text-slate-700">
                  {row.description || "—"}
                </td>
                <td className="px-4 py-3">
                  <div className="flex min-w-max flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => onView(row)}
                      className="inline-flex items-center gap-2 rounded-lg bg-blue-100 px-3 py-2 font-bold text-blue-800 hover:bg-blue-200"
                    >
                      <Eye size={16} /> {t("ownerGariAccount.actions.viewDetail")}
                    </button>
                    {(row.transaction_type === "owner_withdrawal" ||
                      row.transaction_type === "gari_withdrawal") && (
                      <>
                        <button
                          type="button"
                          onClick={() => onPrintReceipt(row)}
                          className="inline-flex items-center gap-2 rounded-lg bg-slate-100 px-3 py-2 font-bold text-slate-800 hover:bg-slate-200"
                        >
                          <Printer size={16} /> {t("ownerGariAccount.actions.printReceipt")}
                        </button>
                        <button
                          type="button"
                          onClick={() => onReverseWithdrawal(row)}
                          disabled={reversingTransactionId === row.transaction_id}
                          className="inline-flex items-center gap-2 rounded-lg bg-red-100 px-3 py-2 font-bold text-red-800 hover:bg-red-200 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          <RotateCcw size={16} />
                          {reversingTransactionId === row.transaction_id
                            ? t("ownerGariAccount.actions.reversingWithdrawal")
                            : t("ownerGariAccount.actions.reverseWithdrawal")}
                        </button>
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={10} className="px-4 py-12 text-center font-bold text-slate-500">
                  <Truck className="mx-auto mb-3" />
                  {t("ownerGariAccount.table.empty")}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
