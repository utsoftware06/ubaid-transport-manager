"use client";

import { useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export type VoucherDriverEarningOption = {
  id: string;
  driverId: string;
  driverName: string;
  salaryDate: string;
  salaryMonth: string;
  vehicleId: string;
  vehicleNo: string;
  earningType: string;
  basicSalary: number;
  tripPay: number;
  bonusAllowance: number;
  deductionFine: number;
  grossExpense: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: string;
  attachedVoucherId: number | null;
  attachedVoucherNo: string | null;
  attachedVoucherDate: string | null;
};

type Props = {
  entries: VoucherDriverEarningOption[];
  selectedIds: string[];
  onChange: (ids: string[]) => void;
};

function monthLabel(value: string) {
  const match = /^(\d{4})-(\d{2})/.exec(value);
  if (!match) return value || "-";
  return new Intl.DateTimeFormat("en-PK", { month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, 1)));
}

export default function VoucherDriverEarningSelector({ entries, selectedIds, onChange }: Props) {
  const { t, dir } = useLanguage();
  const [search, setSearch] = useState("");
  const rows = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return entries;
    return entries.filter((entry) => [
      entry.driverName, entry.salaryDate, entry.salaryMonth, entry.vehicleNo,
      entry.earningType, entry.paymentStatus,
    ].join(" ").toLowerCase().includes(keyword));
  }, [entries, search]);
  const total = entries
    .filter((entry) => selectedIds.includes(entry.id))
    .reduce((sum, entry) => sum + entry.grossExpense, 0);

  return (

    <section dir={dir} className="mt-4 rounded-xl border border-blue-300 bg-blue-50 p-4">
      <h3 className="text-lg font-black text-gray-900">{t("expenses.driverLink.title")}</h3>
      <p className="mt-1 text-sm font-semibold text-gray-700">{t("expenses.driverLink.description")}</p>
      <VoiceTypingField fieldLabel={t("expenses.driverLink.searchPlaceholder")} mode="text"><input
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder={t("expenses.driverLink.searchPlaceholder")}
        className="mt-4 w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold text-gray-900"
      /></VoiceTypingField>
      <div className="mt-3 max-h-72 overflow-y-auto rounded-lg border bg-white">
        {rows.length === 0 ? (
          <p className="p-5 text-center font-semibold">{t("expenses.driverLink.empty")}</p>
        ) : rows.map((entry) => {
          const checked = selectedIds.includes(entry.id);
          return (
            <label key={entry.id} className="flex cursor-pointer gap-3 border-b p-3 last:border-0 hover:bg-blue-50">
              <input
                type="checkbox"
                checked={checked}
                onChange={() => onChange(checked ? selectedIds.filter((id) => id !== entry.id) : [...selectedIds, entry.id])}
                className="mt-1 h-5 w-5 accent-blue-600"
              />
              <span className="min-w-0 flex-1 text-sm">
                <strong>{entry.driverName} · {monthLabel(entry.salaryMonth)} · {entry.vehicleNo}</strong>
                <span className="block font-semibold">{t(`drivers.account.earningTypes.${entry.earningType}`)} · {entry.salaryDate}</span>
                <span className="block text-gray-700">
                  {t("expenses.driverLink.settled")}: Rs. {entry.paidAmount.toLocaleString("en-PK")} · {t("common.remaining")}: Rs. {entry.remainingAmount.toLocaleString("en-PK")}
                </span>
                <span className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-xs font-black ${entry.attachedVoucherId ? "border-blue-300 bg-blue-100 text-blue-900" : "border-gray-300"}`}>
                  {t(entry.attachedVoucherId ? "expenses.driverLink.attached" : "expenses.driverLink.notAttached")}
                </span>
                {entry.attachedVoucherId && (
                  <span className="ms-2 text-xs font-bold text-blue-900">
                    {entry.attachedVoucherNo || entry.attachedVoucherId}{entry.attachedVoucherDate ? ` · ${entry.attachedVoucherDate}` : ""}
                  </span>
                )}
              </span>
              <strong className="whitespace-nowrap text-blue-800">Rs. {entry.grossExpense.toLocaleString("en-PK")}</strong>
            </label>
          );
        })}
      </div>
      <div className="mt-3 flex justify-between rounded-lg border border-blue-200 bg-white p-3 font-black">
        <span>{t("expenses.driverLink.selectedCount")}: {selectedIds.length}</span>
        <span>{t("expenses.driverLink.selectedTotal")}: Rs. {total.toLocaleString("en-PK")}</span>
      </div>
    </section>

  );
}
