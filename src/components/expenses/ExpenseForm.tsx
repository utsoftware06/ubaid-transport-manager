import { useMemo, useState } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicles?: {
    vehicle_no: string | null;
  } | null;
  drivers?: {
    name: string | null;
  } | null;
  bookings?: {
    booking_no?: string | null;
    trip_type?: string | null;
  } | {
    booking_no?: string | null;
    trip_type?: string | null;
  }[] | null;
};

export type VoucherMovementSummary = {
  id: string;
  label: string;
  outboundBiltyNo: string;
  biltyCount: number;
  tripTypes: string[];
  loadingNumbers: string[];
};

export type VoucherMovementOption = VoucherMovementSummary & {
  id: string;
  loadingIds: string[];
  voucherStatus: "available" | "voucher_created";
  linkedVoucherId: number | null;
  linkedVoucherNo: string | null;
  linkedVoucherDate: string | null;
  selectable: boolean;
};

type ExpenseFormProps = {
  contextKey: string;
  expenseNo: string;
  setExpenseNo: (value: string) => void;
  startDate: string;
  setStartDate: (value: string) => void;
  endDate: string;
  setEndDate: (value: string) => void;
  onSelectMovementGroup: (groupId: string) => void;
  description: string;
  setDescription: (value: string) => void;
  selectedLoadings: LoadingRecord[];
  movementSummary: VoucherMovementSummary | null;
  movementGroups: VoucherMovementOption[];
  totalDays: number | null;
};

export default function ExpenseForm({
  contextKey,
  expenseNo,
  setExpenseNo,
  startDate,
  setStartDate,
  endDate,
  setEndDate,
  onSelectMovementGroup,
  description,
  setDescription,
  selectedLoadings,
  movementSummary,
  movementGroups,
  totalDays,
}: ExpenseFormProps) {
  const { t, dir } = useLanguage();
  const [movementSearch, setMovementSearch] = useState("");
  const normalizedSearch = movementSearch.trim().toLocaleLowerCase();
  const filteredMovementGroups = useMemo(
    () =>
      movementGroups.filter((group) => {
        if (!normalizedSearch) return true;
        return [
          group.label,
          group.outboundBiltyNo,
          ...group.loadingNumbers,
          ...group.tripTypes,
        ]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase()
          .includes(normalizedSearch);
      }),
    [movementGroups, normalizedSearch]
  );

  return (
    <div dir={dir}>
      <div className="mb-8">
        <h2 className="text-3xl font-bold text-gray-900">
          {t("expenses.form.title")}
        </h2>
        <p className="mt-1 text-base font-medium text-gray-900">
          {t("expenses.form.description")}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">

        <div>
          <label
            htmlFor="voucher-number"
            className="mb-2 block font-bold text-gray-900"
          >
            {t("expenses.form.voucherNo")}
          </label>
          <VoiceTypingField fieldLabel={t("expenses.form.voucherNo")} mode="identifier"><input
            id="voucher-number"
            type="text"
            placeholder={t("expenses.form.voucherNo")}
            dir="ltr"
            value={expenseNo}
            onChange={(event) => setExpenseNo(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="grid grid-cols-1 gap-5 sm:grid-cols-3">

          <div>
            <label
              htmlFor="voucher-start-date"
              className="mb-2 block font-bold text-gray-900"
            >
              {t("expenses.form.startDate")}
            </label>
            <VoiceTypingField fieldLabel="voucher start date" mode="date"><input
              id="voucher-start-date"
              type="date"
              required
              dir="ltr"
              value={startDate}
              onChange={(event) => setStartDate(event.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            /></VoiceTypingField>
          </div>


          <div>
            <label
              htmlFor="voucher-end-date"
              className="mb-2 block font-bold text-gray-900"
            >
              {t("expenses.form.endDate")}
            </label>
            <VoiceTypingField fieldLabel="voucher end date" mode="date"><input
              id="voucher-end-date"
              type="date"
              required
              dir="ltr"
              min={startDate || undefined}
              value={endDate}
              onChange={(event) => setEndDate(event.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            /></VoiceTypingField>
          </div>

          <div>
            <span className="mb-2 block font-bold text-gray-900">
              {t("expenses.form.totalDays")}
            </span>
            <div className="rounded-lg border border-blue-300 bg-blue-50 p-3 font-extrabold text-blue-950" aria-live="polite">
              {totalDays === null ? "-" : `${totalDays} ${t("expenses.form.days")}`}
              <span className="ms-2 text-xs font-bold uppercase text-blue-700">
                {t("expenses.form.auto")}
              </span>
            </div>
          </div>
        </div>

        {movementSummary && (
          <section className="rounded-xl border border-blue-300 bg-blue-50 p-4 md:col-span-2" aria-label={t("expenses.form.movementGroup")}>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div><div className="text-sm font-bold text-blue-800">{t("expenses.form.movementGroup")}</div><div dir="ltr" className="mt-1 font-black text-blue-950">{movementSummary.label}</div></div>
              <div><div className="text-sm font-bold text-blue-800">{t("expenses.form.outboundBilty")}</div><div dir="ltr" className="mt-1 font-black text-blue-950">{movementSummary.outboundBiltyNo}</div></div>
              <div><div className="text-sm font-bold text-blue-800">{t("expenses.form.selectedChakkars")}</div><div dir="ltr" className="mt-1 font-black text-blue-950">{movementSummary.biltyCount}</div></div>
              <div><div className="text-sm font-bold text-blue-800">{t("expenses.form.tripTypesIncluded")}</div><div className="mt-1 font-black text-blue-950">{movementSummary.tripTypes.join(", ") || "-"}</div></div>
            </div>
            <div className="mt-3 text-sm font-bold text-blue-800">
              {t("expenses.form.groupLoadings")}: {movementSummary.loadingNumbers.length > 0 ? (
                <span dir="ltr" className="text-blue-950">{movementSummary.loadingNumbers.join(", ")}</span>
              ) : (
                <span className="text-blue-950">{t("expenses.form.loadingPreparedOnSelection")}</span>
              )}
            </div>
          </section>
        )}


        <fieldset
          className="rounded-xl border border-gray-300 bg-white p-4 md:col-span-2"
          aria-describedby="voucher-loading-storage-note"
        >
          <legend className="px-2 font-bold text-gray-900">
            {t("expenses.form.selectMovementGroup")}
          </legend>

          <label
            htmlFor="voucher-movement-search"
            className="mb-2 block font-bold text-gray-900"
          >
            {t("expenses.form.searchMovementGroups")}
          </label>
          <VoiceTypingField fieldLabel={t("expenses.form.searchMovementGroupsPlaceholder")} mode="text"><input
            id="voucher-movement-search"
            type="search"
            value={movementSearch}
            onChange={(event) => setMovementSearch(event.target.value)}
            placeholder={t("expenses.form.searchMovementGroupsPlaceholder")}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>

          <div className="mt-3 max-h-60 overflow-y-auto rounded-lg border border-gray-300 bg-white">
            {filteredMovementGroups.length === 0 ? (
              <p className="p-4 font-semibold text-gray-700">
                {t("expenses.form.noCompletedMovementGroups")}
              </p>
            ) : (
              filteredMovementGroups.map((group) => {
                const isSelected = movementSummary?.id === group.id;
                return (
                  <label
                    key={group.id}
                    className={`flex items-start gap-3 border-b border-gray-200 p-3 text-gray-900 last:border-b-0 ${group.selectable ? "cursor-pointer hover:bg-blue-50" : "cursor-not-allowed bg-amber-50"}`}
                  >
                    <input
                      type="radio"
                      name="voucher-movement-group"
                      checked={isSelected}
                      disabled={!group.selectable}
                      onChange={() => onSelectMovementGroup(group.id)}
                      className="mt-1 h-5 w-5 border-gray-400 text-blue-600 focus:ring-blue-600 disabled:cursor-not-allowed"
                    />
                    <span className="min-w-0 flex-1">
                      <span className="flex flex-wrap items-center justify-between gap-2">
                        <span dir="ltr" className="block font-bold">{group.label}</span>
                        <span className={`rounded-full border px-2 py-1 text-xs font-black ${group.voucherStatus === "available" ? "border-green-300 bg-green-50 text-green-800" : "border-amber-400 bg-amber-100 text-amber-950"}`}>
                          {t(`expenses.form.movementVoucherStatus.${group.voucherStatus}`)}
                        </span>
                      </span>
                      <span className="block break-words text-sm font-semibold text-gray-700">
                        {t("expenses.form.selectedChakkars")}: {group.biltyCount} ·{" "}
                        {t("expenses.form.groupLoadings")}:{" "}
                        {group.loadingNumbers.length > 0 ? (
                          <span dir="ltr">{group.loadingNumbers.join(", ")}</span>
                        ) : (
                          <span>{t("expenses.form.loadingPreparedOnSelection")}</span>
                        )}
                      </span>
                      {group.linkedVoucherId !== null && (
                        <span className="mt-1 block text-sm font-black text-amber-950">
                          {t("expenses.form.completedVoucher")}: <span dir="ltr">{group.linkedVoucherNo || group.linkedVoucherId}</span>
                          {group.linkedVoucherDate ? <span dir="ltr"> · {group.linkedVoucherDate}</span> : null}
                        </span>
                      )}
                    </span>
                  </label>
                );
              })
            )}
          </div>

          <p
            id="voucher-loading-storage-note"
            className="mt-3 text-sm font-semibold text-gray-700"
          >
            {t("expenses.form.movementGroupSelectionNotice")}
          </p>

          {!movementSummary && selectedLoadings.length > 0 && (
            <div className="mt-3 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-semibold text-amber-950">
              {t("expenses.form.legacyLoadingSelectionPreserved")}
            </div>
          )}
        </fieldset>


        <div className="md:col-span-2">
          <label
            htmlFor="voucher-description"
            className="mb-2 block font-bold text-gray-900"
          >
            {t("common.description")}
          </label>
          <VoiceTypingField fieldLabel={t("common.description")} value={description} onValueChange={setDescription} contextKey={contextKey}>
          <textarea
            id="voucher-description"
            placeholder={t("common.description")}
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            rows={3}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>
      </div>

      {selectedLoadings.length > 0 && (
        <div className="mt-8 space-y-4">
          {selectedLoadings.map((loading, index) => (
            <section
              key={loading.id}
              aria-label={`${t("common.loading")} ${loading.loading_no}`}
              className="rounded-xl border border-gray-300 bg-white p-4 shadow-sm"
            >
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <h3 className="font-extrabold text-gray-900">
                  {t("common.loading")}{" "}
                  <span dir="ltr">{loading.loading_no}</span>
                </h3>
                {index === 0 && (
                  <span className="rounded-full border border-green-300 bg-green-50 px-3 py-1 text-xs font-bold text-green-800">
                    {t("expenses.form.primaryLoading")}
                  </span>
                )}
              </div>
              <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
                <div>
                  <dt className="text-sm font-bold text-gray-700">
                    {t("expenses.form.vehicleNumber")}
                  </dt>
                  <dd dir="ltr" className="mt-1 font-bold text-gray-900">
                    {loading.vehicles?.vehicle_no ?? "-"}
                  </dd>
                </div>
                <div>
                  <dt className="text-sm font-bold text-gray-700">
                    {t("expenses.form.driverName")}
                  </dt>
                  <dd className="mt-1 font-bold text-gray-900">
                    {loading.drivers?.name ?? "-"}
                  </dd>
                </div>
                <div>
                  <dt className="text-sm font-bold text-gray-700">
                    {t("common.route")}
                  </dt>
                  <dd className="mt-1 font-bold text-gray-900">
                    {loading.route || "-"}
                  </dd>
                </div>
                <div>
                  <dt className="text-sm font-bold text-gray-700">
                    {t("common.loadingDate")}
                  </dt>
                  <dd dir="ltr" className="mt-1 font-bold text-gray-900">
                    {loading.loading_date || "-"}
                  </dd>
                </div>
              </dl>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
