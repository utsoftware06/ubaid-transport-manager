"use client";

import { useEffect, useRef } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  expenseTypeLabelKey,
  normalizeExpenseClass,
} from "./expenseClassification";
import type { ManualVoucherAdjustment } from "./ManualVoucherAdjustmentModal";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicle_id: string | null;
  driver_id: string | null;
  vehicles?: {
    vehicle_no: string | null;
  } | null;
  drivers?: {
    name: string | null;
  } | null;
  bookings?: {
    id: string;
    adda_id: string | null;
    freight: number | string | null;
  } | {
    id: string;
    adda_id: string | null;
    freight: number | string | null;
  }[] | null;
};

type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
  expense_class?: string | null;
  amount: number | string;
  payment_method: string;
  remarks: string | null;
  receipt_url: string | null;
  receipt_name: string | null;
};

type DieselEntryRecord = {
  id: number;
  expense_id: number;
  expense_item_id: number;
  entry_date: string;
  petrol_pump_id: string;
  vehicle_id: string;
  driver_id: string | null;
  loading_id: number | null;
  manual_voucher_id?: string | null;
  manual_request_id?: string | null;
  slip_no: string | null;
  liters: number | string;
  rate: number | string;
  total_amount: number | string;
  paid_amount: number | string;
  remaining_amount: number | string;
  payment_status: string;
  remarks: string | null;
  petrol_pumps?: {
    pump_name: string | null;
  } | null;
};

type VoucherAdjustmentSummary = {
  id: string;
  status: string;
  totalAmount: number;
  finalizedAt: string | null;
};

type ExpenseVoucher = {
  id: number;
  expense_no: string;
  expense_date: string;
  start_date?: string | null;
  end_date?: string | null;
  loading_id: number | null;
  movement_group_id?: string | null;
  voucher_source?: "bilty" | "manual" | null;
  description: string | null;
  created_at?: string | null;
  vehicle_chakkar_settlements?: Array<{
    id: string;
    movement_group_id: string;
    finalized_at: string;
  }>;
  loadings?: LoadingRecord | null;
  voucher_loadings?: Array<{
    loading_id: number;
    loadings?: LoadingRecord | null;
  }>;
  expense_items?: ExpenseItemRecord[];
  diesel_entries?: DieselEntryRecord[];
  voucher_adjustment_summaries?: VoucherAdjustmentSummary[];
  manual_voucher_adjustments?: ManualVoucherAdjustment[];
  manual_voucher_details?: {
    id: string;
    voucher_id: number;
    adda_id: string;
    vehicle_id: string;
    driver_id: string | null;
    voucher_date: string;
    departure_date?: string | null;
    arrival_date?: string | null;
    chakkar_days: number;
    remarks: string | null;
    status: "draft" | "finalized";
    finalized_at?: string | null;
    manual_vehicle_chakkar_settlements?: Array<{
      id: string;
      voucher_id?: number;
      total_freight: number | string;
      regular_expense_total: number | string;
      periodic_expense_total: number | string;
      total_expense_amount: number | string;
      net_vehicle_amount: number | string;
      expense_snapshot?: Array<{ expense_class: string; expense_type: string; amount: number | string; remarks: string | null }>;
      finalized_at: string;
    }>;
    vehicle_no?: string;
    driver_name?: string | null;
    manual_voucher_freight_items?: Array<{
      id: string;
      manual_voucher_id: string;
      freight_type: "outbound" | "local" | "return";
      amount: number | string;
      description: string | null;
      sequence_no: number;
    }>;
  } | null;
  voucher_driver_earnings?: Array<{
    driver_earning_id: string;
    driver_earnings?: {
      id: string; adda_id: string; driver_id: string; vehicle_id: string;
      salary_date: string; salary_month: string; earning_type: string;
      basic_salary: number | string; trip_pay: number | string; bonus_allowance: number | string;
      deduction_fine: number | string; gross_expense: number | string; paid_amount: number | string;
      remaining_amount: number | string; payment_status: string;
      drivers?: { name: string | null } | Array<{ name: string | null }> | null;
      vehicles?: { vehicle_no: string | null } | Array<{ vehicle_no: string | null }> | null;
    } | null;
  }>;
};

type Props = {
  expenseVouchers: ExpenseVoucher[];
  search: string;
  setSearch: (value: string) => void;
  fromDate: string;
  toDate: string;
  vehicleFilter: string;
  driverFilter: string;
  categoryFilter: string;
  paymentMethodFilter: string;
  vehicleOptions: { id: string; label: string }[];
  driverOptions: { id: string; label: string }[];
  page: number;
  setPage: (value: number | ((current: number) => number)) => void;
  onFromDateChange: (value: string) => void;
  onToDateChange: (value: string) => void;
  onVehicleFilterChange: (value: string) => void;
  onDriverFilterChange: (value: string) => void;
  onCategoryFilterChange: (value: string) => void;
  onPaymentMethodFilterChange: (value: string) => void;
  onResetFilters: () => void;
  viewingExpense: ExpenseVoucher | null;
  isLoading: boolean;
  onCloseView: () => void;
  onView: (expense: ExpenseVoucher) => void;
  onEdit: (expense: ExpenseVoucher) => void;
  onFinalize: (expense: ExpenseVoucher) => void;
  onCreateAdjustment: (expense: ExpenseVoucher) => void;
  onDelete: (expense: ExpenseVoucher) => void;
  onPrint: (expense: ExpenseVoucher) => void;
  onPreviewReceipt: (receiptUrl: string) => void;
  isDeleting: boolean;
  finalizingVoucherId: number | null;
};

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function formatAmount(value: number | string | null | undefined) {
  return `Rs. ${toNumber(value).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getStatusClass(status: string) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

function getVoucherTotal(expense: ExpenseVoucher) {
  return (expense.expense_items ?? []).reduce(
    (total, item) => total + toNumber(item.amount),
    0
  );
}

function isFinalizedAdjustment(adjustment: VoucherAdjustmentSummary) {
  const status = adjustment.status.trim().toLowerCase();
  return status === "finalized" || Boolean(adjustment.finalizedAt);
}

function getFinalizedAdjustments(expense: ExpenseVoucher) {
  return (expense.voucher_adjustment_summaries ?? []).filter(
    isFinalizedAdjustment
  );
}

function getFinalizedAdjustmentTotal(expense: ExpenseVoucher) {
  return getFinalizedAdjustments(expense).reduce(
    (total, adjustment) => total + toNumber(adjustment.totalAmount),
    0
  );
}

export default function ExpenseTable({
  expenseVouchers,
  search,
  setSearch,
  fromDate,
  toDate,
  vehicleFilter,
  driverFilter,
  categoryFilter,
  paymentMethodFilter,
  vehicleOptions,
  driverOptions,
  page,
  setPage,
  onFromDateChange,
  onToDateChange,
  onVehicleFilterChange,
  onDriverFilterChange,
  onCategoryFilterChange,
  onPaymentMethodFilterChange,
  onResetFilters,
  viewingExpense,
  isLoading,
  onCloseView,
  onView,
  onEdit,
  onFinalize,
  onCreateAdjustment,
  onDelete,
  onPrint,
  onPreviewReceipt,
  isDeleting,
  finalizingVoucherId,
}: Props) {
  const { t, dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(expenseVouchers.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleExpenseVouchers = expenseVouchers.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  const dieselByItemId = new Map<number, DieselEntryRecord>();

  (viewingExpense?.diesel_entries ?? []).forEach((diesel) => {
    dieselByItemId.set(diesel.expense_item_id, diesel);
  });
  const viewingLoadings = viewingExpense
    ? getVoucherLoadings(viewingExpense)
    : [];
  const viewingLoadingNumbers = viewingLoadings
    .map((loading) => loading.loading_no)
    .filter(Boolean)
    .join(", ");

  useEffect(() => {
    if (!viewingExpense) return;

    previousFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCloseView();
    };
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocusRef.current?.focus();
    };
  }, [onCloseView, viewingExpense]);

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">

      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("expenses.table.title")}
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            {t("expenses.table.description")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("expenses.table.searchPlaceholder")} mode="text"><input
          type="text"
          aria-label={t("expenses.table.searchPlaceholder")}
          placeholder={t("expenses.table.searchPlaceholder")}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        /></VoiceTypingField>
      </div>


      <div className="mb-6 rounded-xl border border-gray-300 bg-white p-4 text-gray-900 shadow-sm">
        <h3 className="mb-3 text-lg font-extrabold text-gray-900">{t("expenses.filters.title")}</h3>
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">

          <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("common.fromDate")}</span>
            <input type="date" dir="ltr" value={fromDate} onChange={(event) => onFromDateChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" />
          </label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("common.toDate")}</span>
            <input type="date" dir="ltr" value={toDate} onChange={(event) => onToDateChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" />
          </label></VoiceTypingField>

          <label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("common.vehicle")}</span>
            <select value={vehicleFilter} onChange={(event) => onVehicleFilterChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
              <option value="">{t("expenses.filters.allVehicles")}</option>
              {vehicleOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
            </select>
          </label>
          <label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("common.driver")}</span>
            <select value={driverFilter} onChange={(event) => onDriverFilterChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
              <option value="">{t("expenses.filters.allDrivers")}</option>
              {driverOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
            </select>
          </label>
          <label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("expenses.items.expenseType")}</span>
            <select value={categoryFilter} onChange={(event) => onCategoryFilterChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
              <option value="">{t("expenses.filters.allCategories")}</option>
              {["Fuel", "Toll Tax", "Food", "Labour", "Maintenance", "Police", "Parking", "Other"].map((value) => <option key={value} value={value}>{t(`expenses.categories.${value.replaceAll(" ", "").toLowerCase()}`)}</option>)}
            </select>
          </label>
          <label className="text-sm font-bold text-gray-900">
            <span className="mb-1 block">{t("expenses.items.paymentMethod")}</span>
            <select value={paymentMethodFilter} onChange={(event) => onPaymentMethodFilterChange(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
              <option value="">{t("expenses.filters.allPaymentMethods")}</option>
              {["Cash", "Bank Transfer", "JazzCash", "EasyPaisa", "Cheque"].map((value) => <option key={value} value={value}>{t(`expenses.paymentMethods.${value.replaceAll(" ", "").toLowerCase()}`)}</option>)}
            </select>
          </label>
        </div>
        <button type="button" onClick={onResetFilters} className="mt-4 rounded-lg border border-gray-300 bg-white px-5 py-3 font-bold text-gray-900 hover:bg-gray-50">{t("common.actions.reset")}</button>
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-300">
        <table className="w-full min-w-[1050px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-start font-bold">{t("expenses.table.voucherNo")}</th>
              <th className="p-3 text-start font-bold">{t("expenses.form.startDate")}</th>
              <th className="p-3 text-start font-bold">{t("expenses.form.endDate")}</th>
              <th className="p-3 text-start font-bold">{t("expenses.table.loadingNumbers")}</th>
              <th className="p-3 text-end font-bold">{t("expenses.table.loadingCount")}</th>
              <th className="p-3 text-end font-bold">{t("expenses.table.voucherTotal")}</th>
              <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
            </tr>
          </thead>

          <tbody>
            {isLoading && (
              <tr>
                <td
                  colSpan={7}
                  className="p-8 text-center text-base font-bold text-gray-900"
                >
                  {t("common.loading")}
                </td>
              </tr>
            )}

            {!isLoading && expenseVouchers.length === 0 && (
              <tr>
                <td
                  colSpan={7}
                  className="p-8 text-center text-base font-bold text-gray-900"
                >
                  {t("expenses.table.empty")}
                </td>
              </tr>
            )}

            {!isLoading && visibleExpenseVouchers.map((expense) => {
              const voucherLoadings = getVoucherLoadings(expense);
              const loadingNumbers = voucherLoadings
                .map((loading) => loading.loading_no)
                .filter(Boolean)
                .join(", ");
              const isManual = expense.voucher_source === "manual";
              const isFinalized =
                (expense.vehicle_chakkar_settlements ?? []).length > 0 ||
                expense.manual_voucher_details?.status === "finalized";
              const finalizedAdjustments = getFinalizedAdjustments(expense);
              const finalizedAdjustmentTotal =
                getFinalizedAdjustmentTotal(expense);
              const finalizedManualAdjustments = (expense.manual_voucher_adjustments ?? [])
                .filter((adjustment) => adjustment.status === "finalized");
              const finalizedManualAdjustmentTotal = finalizedManualAdjustments
                .reduce((sum, adjustment) => sum + toNumber(adjustment.net_adjustment), 0);

              return (
                <tr
                  key={expense.id}
                  className="border-b border-gray-200 text-gray-900 hover:bg-gray-50"
                >
                  <td dir="ltr" className="p-3 font-bold">{expense.expense_no}</td>
                  <td dir="ltr" className="p-3 font-semibold">
                    {expense.start_date ?? expense.expense_date}
                  </td>
                  <td dir="ltr" className="p-3 font-semibold">
                    {expense.end_date ?? expense.expense_date}
                  </td>
                  <td dir="ltr" className="max-w-[320px] p-3 font-semibold">
                    {isManual ? <>
                      <div>{t("expenses.manual.withoutBilty")} · {expense.manual_voucher_details?.vehicle_no ?? "-"}</div>
                      <span className={`mt-1 inline-flex rounded-full px-2 py-1 text-xs font-black ${isFinalized ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-900"}`}>
                        {t(isFinalized ? "expenses.manual.finalized" : "expenses.manual.draft")}
                      </span>
                    </> : loadingNumbers || "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold">
                    {isManual ? "—" : voucherLoadings.length}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-extrabold">
                    <div>{formatAmount(isManual ? getVoucherFreight(expense) : getVoucherTotal(expense))}</div>
                    {isManual && <div className="text-xs font-bold text-slate-600">{t("expenses.manual.totalFreight")}</div>}
                    {finalizedAdjustments.length > 0 && (
                      <div className="mt-1 rounded-md bg-purple-50 px-2 py-1 text-xs font-extrabold text-purple-700">
                        Adjustment: {formatAmount(finalizedAdjustmentTotal)}
                        <span className="ms-1">
                          ({finalizedAdjustments.length})
                        </span>
                      </div>
                    )}
                    {finalizedManualAdjustments.length > 0 && (
                      <div className="mt-1 rounded-md bg-purple-50 px-2 py-1 text-xs font-extrabold text-purple-700">
                        Manual adjustment: {formatAmount(finalizedManualAdjustmentTotal)}
                        <span className="ms-1">({finalizedManualAdjustments.length})</span>
                      </div>
                    )}
                  </td>
                  <td className="min-w-[260px] p-3">
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => onView(expense)}
                      className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                    >
                      {t("common.actions.view")}
                    </button>

                    {!isFinalized && <button
                      type="button"
                      onClick={() => onEdit(expense)}
                      className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                    >
                      {t("common.actions.edit")}
                    </button>}

                    {((isManual && !isFinalized) || (expense.movement_group_id && !isFinalized)) && (
                      <button
                        type="button"
                        onClick={() => onFinalize(expense)}
                        disabled={finalizingVoucherId === expense.id}
                        className="rounded-lg bg-amber-600 px-3 py-2 font-semibold text-white transition hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        {finalizingVoucherId === expense.id
                          ? t("expenses.actions.finalizingVoucher")
                          : t("expenses.actions.finalizeVoucher")}
                      </button>
                    )}

                    {isFinalized && (
                      <button
                        type="button"
                        onClick={() => onCreateAdjustment(expense)}
                        className="rounded-lg bg-purple-600 px-3 py-2 font-semibold text-white transition hover:bg-purple-700"
                      >
                        {isManual
                          ? finalizedManualAdjustments.length > 0
                            ? `Adjustment (${finalizedManualAdjustments.length})`
                            : "Adjustment"
                          : finalizedAdjustments.length > 0
                            ? `Adjustment (${finalizedAdjustments.length})`
                            : "Adjustment"}
                      </button>
                    )}

                    {!isFinalized && <button
                      type="button"
                      onClick={() => onDelete(expense)}
                      disabled={isDeleting}
                      className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                    >
                      {t("expenses.actions.removeOrArchive")}
                    </button>}

                    {
                      <button
                        type="button"
                        onClick={() => onPrint(expense)}
                        className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                      >
                        {t("common.actions.print")}
                      </button>
                    }
                  </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900">
        <span className="font-bold">{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span>
        <div className="flex gap-2">
          <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button>
          <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button>
        </div>
      </div>

      {viewingExpense && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) onCloseView();
          }}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="expense-details-title"
            className="max-h-[90vh] w-full max-w-6xl overflow-y-auto rounded-xl bg-white p-6 shadow-xl"
          >
            <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-start">
              <div>
                <h3
                  id="expense-details-title"
                  className="text-2xl font-bold text-gray-900"
                >
                  {t("expenses.details.title")}
                </h3>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("expenses.table.voucherNo")}: <span dir="ltr">{viewingExpense.expense_no}</span>
                </p>
              </div>

              <button
                ref={closeButtonRef}
                type="button"
                onClick={onCloseView}
                className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
              >
                {t("common.actions.close")}
              </button>
            </div>

            <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-sm font-bold text-gray-900">{t("expenses.form.startDate")}</p>
                <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.start_date ?? viewingExpense.expense_date}
                </p>
              </div>

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-sm font-bold text-gray-900">{t("expenses.form.endDate")}</p>
                <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.end_date ?? viewingExpense.expense_date}
                </p>
              </div>

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-sm font-bold text-gray-900">{t("expenses.table.loadingCount")}</p>
                <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.voucher_source === "manual" ? "—" : viewingLoadings.length}
                </p>
              </div>

              {viewingExpense.voucher_source !== "manual" && (
                <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                  <p className="text-sm font-bold text-gray-900">{t("common.total")}</p>
                  <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
                    {formatAmount(getVoucherTotal(viewingExpense))}
                  </p>
                </div>
              )}

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm md:col-span-2">
                <p className="text-sm font-bold text-gray-900">
                  {viewingExpense.voucher_source === "manual" ? t("common.vehicle") : t("expenses.table.loadingNumbers")}
                </p>
                <p dir="ltr" className="mt-1 font-bold text-gray-900">
                  {viewingExpense.voucher_source === "manual"
                    ? viewingExpense.manual_voucher_details?.vehicle_no ?? "-"
                    : viewingLoadingNumbers || "-"}
                </p>
              </div>

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-sm font-bold text-gray-900">{t("expenses.details.totalFreight")}</p>
                <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
                  {formatAmount(getVoucherFreight(viewingExpense))}
                </p>
              </div>

              <div className="rounded-lg border border-green-300 bg-white p-4 shadow-sm">
                <p className="text-sm font-bold text-gray-900">{t("expenses.details.cashbookStatus")}</p>
                <p className="mt-1 font-bold text-green-700">
                  {viewingExpense.voucher_source === "manual"
                    ? t("expenses.manual.cashbookNotUsed")
                    : t("expenses.details.cashbookSynchronized")}
                </p>
              </div>
            </div>

            <div className="mb-6 rounded-lg border border-gray-300 bg-white p-4 text-gray-900 shadow-sm">
              <p className="text-sm font-bold">{t("common.description")}</p>
              <p className="mt-1 font-semibold">{viewingExpense.voucher_source === "manual" ? viewingExpense.manual_voucher_details?.remarks || viewingExpense.description || "-" : viewingExpense.description || "-"}</p>
            </div>

            {viewingExpense.voucher_source === "manual" && viewingExpense.manual_voucher_details && (
              <section className="mb-6 overflow-x-auto rounded-xl border border-blue-200 bg-white">
                <div className="flex flex-wrap gap-4 border-b border-blue-100 bg-blue-50 p-4 font-bold text-blue-950">
                  <span>{t("expenses.manual.withoutBilty")}</span>
                  <span>{viewingExpense.manual_voucher_details.status === "finalized" ? t("expenses.manual.finalized") : t("expenses.manual.draft")}</span>
                  <span>{t("expenses.manual.voucherDate")}: {viewingExpense.manual_voucher_details.voucher_date}</span>
                  {viewingExpense.manual_voucher_details.departure_date && viewingExpense.manual_voucher_details.arrival_date && (
                    <>
                      <span>{t("expenses.manual.departureDate")}: {viewingExpense.manual_voucher_details.departure_date}</span>
                      <span>{t("expenses.manual.arrivalDate")}: {viewingExpense.manual_voucher_details.arrival_date}</span>
                    </>
                  )}
                  <span>{t("common.vehicle")}: {viewingExpense.manual_voucher_details.vehicle_no ?? "-"}</span>
                  <span>{t("expenses.manual.chakkarDays")}: {viewingExpense.manual_voucher_details.chakkar_days}</span>
                  {viewingExpense.manual_voucher_details.driver_name && (
                    <span>{t("common.driver")}: {viewingExpense.manual_voucher_details.driver_name}</span>
                  )}
                </div>
                <table className="w-full min-w-[600px] border-collapse text-sm text-gray-900">
                  <thead className="bg-blue-600 text-white"><tr>
                    <th className="p-3 text-start">{t("expenses.manual.freightType")}</th>
                    <th className="p-3 text-end">{t("common.amount")}</th>
                    <th className="p-3 text-start">{t("expenses.manual.routeRemarks")}</th>
                  </tr></thead>
                  <tbody>{(viewingExpense.manual_voucher_details.manual_voucher_freight_items ?? []).map((row) => (
                    <tr key={row.id} className="border-t border-gray-200">
                      <td className="p-3 font-bold">{t(`expenses.manual.freightTypes.${row.freight_type}`)}</td>
                      <td dir="ltr" className="p-3 text-end font-black">{formatAmount(row.amount)}</td>
                      <td className="p-3">{row.description || "-"}</td>
                    </tr>
                  ))}</tbody>
                  <tfoot className="bg-blue-50"><tr>
                    <td className="p-3 font-black">{t("expenses.manual.totalFreight")}</td>
                    <td dir="ltr" className="p-3 text-end font-black">{formatAmount(getVoucherFreight(viewingExpense))}</td>
                    <td />
                  </tr></tfoot>
                </table>
                {(() => {
                  const settlement = viewingExpense.manual_voucher_details?.manual_vehicle_chakkar_settlements?.[0];
                  const useFinalizedSnapshot = viewingExpense.manual_voucher_details?.status === "finalized" && Boolean(settlement);
                  const expenses = useFinalizedSnapshot
                    ? settlement?.expense_snapshot ?? []
                    : viewingExpense.expense_items ?? [];
                  const persistedExpenseTotal = expenses.reduce((sum, item) => sum + toNumber(item.amount), 0);
                  const expenseTotal = useFinalizedSnapshot
                    ? toNumber(settlement?.total_expense_amount ?? 0)
                    : persistedExpenseTotal;
                  const freight = toNumber(settlement?.total_freight ?? getVoucherFreight(viewingExpense));
                  const net = useFinalizedSnapshot
                    ? toNumber(settlement?.net_vehicle_amount ?? 0)
                    : freight - expenseTotal;
                  const finalizedManualAdjustments = (viewingExpense.manual_voucher_adjustments ?? [])
                    .filter((adjustment) => adjustment.status === "finalized");
                  const adjustmentFreight = finalizedManualAdjustments.reduce((sum, adjustment) => sum + toNumber(adjustment.freight_adjustment), 0);
                  const adjustmentExpenses = finalizedManualAdjustments.reduce((sum, adjustment) => sum + toNumber(adjustment.expense_adjustment), 0);
                  const adjustmentNet = finalizedManualAdjustments.reduce((sum, adjustment) => sum + toNumber(adjustment.net_adjustment), 0);
                  const manualDieselEntries = [...(viewingExpense.diesel_entries ?? [])]
                    .filter((diesel) => diesel.manual_voucher_id === viewingExpense.manual_voucher_details?.id)
                    .sort((left, right) => left.expense_item_id - right.expense_item_id);
                  return <div className="space-y-4 p-4">
                    <h3 className="font-black text-slate-950">{t("expenses.manual.expensesTitle")}</h3>
                    <div className="overflow-x-auto rounded-lg border border-slate-200"><table className="w-full min-w-[600px] border-collapse text-sm text-gray-900"><thead className="bg-emerald-700 text-white"><tr><th className="p-3 text-start">{t("expenses.items.expenseType")}</th><th className="p-3 text-end">{t("common.amount")}</th><th className="p-3 text-start">{t("common.remarks")}</th></tr></thead><tbody>{expenses.map((item, index) => <tr key={"id" in item ? item.id : `${item.expense_type}-${index}`} className="border-t border-slate-200"><td className="p-3 font-bold">{t(expenseTypeLabelKey(item.expense_type))}</td><td dir="ltr" className="p-3 text-end font-black">{formatAmount(item.amount)}</td><td className="p-3">{item.remarks || "—"}</td></tr>)}{expenses.length === 0 && <tr><td colSpan={3} className="p-3 text-center">{t("expenses.manual.noExpenses")}</td></tr>}</tbody></table></div>
                    {manualDieselEntries.length > 0 && <div className="overflow-x-auto rounded-lg border border-blue-200"><table className="w-full min-w-[950px] border-collapse text-sm text-gray-900"><thead className="bg-blue-700 text-white"><tr><th className="p-3 text-start">{t("expenses.diesel.petrolPump")}</th><th className="p-3 text-start">{t("common.date")}</th><th className="p-3 text-end">{t("expenses.diesel.litres")}</th><th className="p-3 text-end">{t("expenses.diesel.rate")}</th><th className="p-3 text-end">{t("common.total")}</th><th className="p-3 text-end">{t("common.paid")}</th><th className="p-3 text-end">{t("common.remaining")}</th><th className="p-3 text-start">{t("expenses.diesel.slipNo")}</th><th className="p-3 text-start">{t("common.status")}</th></tr></thead><tbody>{manualDieselEntries.map((diesel) => <tr key={diesel.id} className="border-t border-blue-100"><td className="p-3">{diesel.petrol_pumps?.pump_name ?? "—"}</td><td className="p-3">{diesel.entry_date}</td><td dir="ltr" className="p-3 text-end">{diesel.liters}</td><td dir="ltr" className="p-3 text-end">{formatAmount(diesel.rate)}</td><td dir="ltr" className="p-3 text-end font-bold">{formatAmount(diesel.total_amount)}</td><td dir="ltr" className="p-3 text-end">{formatAmount(diesel.paid_amount)}</td><td dir="ltr" className="p-3 text-end">{formatAmount(diesel.remaining_amount)}</td><td className="p-3">{diesel.slip_no || "—"}</td><td className="p-3">{t(`common.paymentStatus.${diesel.payment_status.toLowerCase()}`)}</td></tr>)}</tbody></table></div>}
                    <div className="grid gap-3 sm:grid-cols-3"><div className="rounded-lg border border-blue-200 bg-blue-50 p-3"><span className="text-xs font-bold">Original Freight</span><strong className="mt-1 block">{formatAmount(freight)}</strong></div><div className="rounded-lg border border-amber-200 bg-amber-50 p-3"><span className="text-xs font-bold">Original Expenses</span><strong className="mt-1 block">{formatAmount(expenseTotal)}</strong></div><div className="rounded-lg border border-emerald-200 bg-emerald-50 p-3"><span className="text-xs font-bold">Original Chakkar Net</span><strong className={`mt-1 block ${net < 0 ? "text-red-700" : "text-emerald-800"}`}>{formatAmount(net)}</strong></div></div>
                    <div className="grid gap-3 sm:grid-cols-3"><div className="rounded-lg border border-purple-200 bg-purple-50 p-3"><span className="text-xs font-bold">Freight Adjustment</span><strong className="mt-1 block">{formatAmount(adjustmentFreight)}</strong></div><div className="rounded-lg border border-purple-200 bg-purple-50 p-3"><span className="text-xs font-bold">Expense Adjustment</span><strong className="mt-1 block">{formatAmount(adjustmentExpenses)}</strong></div><div className="rounded-lg border border-purple-300 bg-purple-100 p-3"><span className="text-xs font-bold">Adjusted Chakkar Net</span><strong className={`mt-1 block ${net + adjustmentNet < 0 ? "text-red-700" : "text-emerald-800"}`}>{formatAmount(net + adjustmentNet)}</strong><span className="mt-1 block text-xs">Adjustment total: {formatAmount(adjustmentNet)} · Finalized: {settlement?.finalized_at ?? "—"}</span></div></div>
                    {finalizedManualAdjustments.length > 0 && <div className="overflow-x-auto rounded-lg border border-purple-200"><table className="w-full min-w-[700px] border-collapse text-sm"><thead className="bg-purple-700 text-white"><tr><th className="p-3 text-start">Adjustment</th><th className="p-3 text-start">Date</th><th className="p-3 text-end">Freight</th><th className="p-3 text-end">Expense</th><th className="p-3 text-end">Net</th><th className="p-3 text-start">Reason</th></tr></thead><tbody>{finalizedManualAdjustments.map((adjustment) => <tr key={adjustment.id} className="border-t border-purple-100"><td className="p-3 font-bold">{adjustment.adjustment_no}</td><td className="p-3">{adjustment.adjustment_date}</td><td className="p-3 text-end">{formatAmount(adjustment.freight_adjustment)}</td><td className="p-3 text-end">{formatAmount(adjustment.expense_adjustment)}</td><td className="p-3 text-end font-black">{formatAmount(adjustment.net_adjustment)}</td><td className="p-3">{adjustment.reason}</td></tr>)}</tbody></table></div>}
                  </div>;
                })()}
              </section>
            )}

            {viewingExpense.voucher_source !== "manual" && <div className="overflow-x-auto rounded-xl border border-gray-200">
              <table className="w-full min-w-[1100px] border-collapse text-sm text-gray-900">
                <thead className="bg-blue-600 text-white">
                  <tr>
                    <th className="p-3 text-start font-bold">#</th>
                    <th className="p-3 text-start font-bold">{t("expenses.items.expenseClass")}</th>
                    <th className="p-3 text-start font-bold">{t("expenses.items.expenseType")}</th>
                    <th className="p-3 text-end font-bold">{t("common.amount")}</th>
                    <th className="p-3 text-start font-bold">{t("expenses.items.paymentMethod")}</th>
                    <th className="p-3 text-start font-bold">{t("common.remarks")}</th>
                    <th className="p-3 text-start font-bold">{t("common.receipt")}</th>
                  </tr>
                </thead>

                <tbody>
                  {(viewingExpense.expense_items ?? []).map((item, index) => {
                    const diesel = dieselByItemId.get(item.id);

                    return (
                      <tr key={item.id} className="border-b border-gray-200">
                        <td className="p-3 font-semibold">{index + 1}</td>
                        <td className="p-3 font-semibold">
                          {t(`expenses.items.${normalizeExpenseClass(item.expense_class, item.expense_type) === "regular_trip" ? "regularTrip" : "vehiclePeriodic"}`)}
                        </td>
                        <td className="p-3 font-bold">
                          {t(expenseTypeLabelKey(item.expense_type))}
                        </td>
                        <td dir="ltr" className="p-3 text-end font-bold">
                          {formatAmount(item.amount)}
                        </td>
                        <td className="p-3 font-semibold">
                          {t(`expenses.paymentMethods.${item.payment_method.replaceAll(" ", "").toLowerCase()}`)}
                        </td>
                        <td className="p-3 font-semibold">
                          <div>{item.remarks || "-"}</div>

                          {diesel && (
                            <div className="mt-3 rounded-lg border border-blue-100 bg-blue-50 p-3">
                              <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
                                <div>
                                  <span className="font-bold">
                                    {t("expenses.diesel.petrolPump")}:
                                  </span>{" "}
                                  {diesel.petrol_pumps?.pump_name ?? "-"}
                                </div>
                                <div>
                                  <span className="font-bold">{t("expenses.diesel.litres")}:</span>{" "}
                                  {diesel.liters}
                                </div>
                                <div>
                                  <span className="font-bold">{t("expenses.diesel.rate")}:</span>{" "}
                                  {formatAmount(diesel.rate)}
                                </div>
                                <div>
                                  <span className="font-bold">{t("common.total")}:</span>{" "}
                                  {formatAmount(diesel.total_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">{t("common.paid")}:</span>{" "}
                                  {formatAmount(diesel.paid_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">{t("common.remaining")}:</span>{" "}
                                  {formatAmount(diesel.remaining_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">{t("common.status")}:</span>{" "}
                                  <span
                                    className={`inline-flex rounded-full border px-2 py-1 text-xs font-bold ${getStatusClass(
                                      diesel.payment_status
                                    )}`}
                                  >
                                    {t(`common.paymentStatus.${diesel.payment_status.toLowerCase()}`)}
                                  </span>
                                </div>
                                <div>
                                  <span className="font-bold">{t("expenses.diesel.slipNo")}:</span>{" "}
                                  {diesel.slip_no ?? "-"}
                                </div>
                              </div>
                            </div>
                          )}
                        </td>
                        <td className="p-3 font-semibold">
                          {item.receipt_url ? (
                            <button
                              type="button"
                              onClick={() =>
                                onPreviewReceipt(item.receipt_url ?? "")
                              }
                              className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-bold text-gray-900 hover:bg-gray-50"
                            >
                              {t("expenses.actions.previewReceipt")}
                            </button>
                          ) : (
                            "-"
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>}

            {(viewingExpense.voucher_driver_earnings ?? []).length > 0 && (
              <section className="mt-6 overflow-x-auto rounded-xl border border-blue-200 bg-white">
                <h3 className="p-4 text-lg font-black text-blue-950">{t("expenses.driverLink.printTitle")}</h3>
                <table className="w-full min-w-[900px] border-collapse text-sm text-gray-900">
                  <thead className="bg-blue-600 text-white"><tr>
                    <th className="p-3 text-start">{t("expenses.driverLink.driver")}</th>
                    <th className="p-3 text-start">{t("drivers.account.salaryDate")}</th>
                    <th className="p-3 text-start">{t("drivers.account.salaryMonth")}</th>
                    <th className="p-3 text-start">{t("drivers.master.vehicle")}</th>
                    <th className="p-3 text-start">{t("drivers.account.earningType")}</th>
                    <th className="p-3 text-end">{t("drivers.account.grossExpense")}</th>
                    <th className="p-3 text-end">{t("expenses.driverLink.settled")}</th>
                    <th className="p-3 text-end">{t("common.remaining")}</th>
                  </tr></thead>
                  <tbody>{(viewingExpense.voucher_driver_earnings ?? []).map((link) => {
                    const earning = link.driver_earnings;
                    if (!earning) return null;
                    const driver = relationOne(earning.drivers);
                    const vehicle = relationOne(earning.vehicles);
                    return <tr key={link.driver_earning_id} className="border-t border-gray-200">
                      <td className="p-3 font-bold">{driver?.name ?? "-"}</td>
                      <td className="p-3">{earning.salary_date}</td>
                      <td className="p-3">{earning.salary_month}</td>
                      <td className="p-3">{vehicle?.vehicle_no ?? "-"}</td>
                      <td className="p-3">{t(`drivers.account.earningTypes.${earning.earning_type}`)}</td>
                      <td dir="ltr" className="p-3 text-end font-bold">{formatAmount(earning.gross_expense)}</td>
                      <td dir="ltr" className="p-3 text-end">{formatAmount(earning.paid_amount)}</td>
                      <td dir="ltr" className="p-3 text-end">{formatAmount(earning.remaining_amount)}</td>
                    </tr>;
                  })}</tbody>
                </table>
              </section>
            )}

            <div className="mt-6 flex justify-end">
              <button
                type="button"
                onClick={() => onPrint(viewingExpense)}
                className="rounded-lg bg-green-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-green-700"
              >
                {t("expenses.actions.printVoucher")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function relationOne<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function getVoucherLoadings(expense: ExpenseVoucher) {
  const related = (expense.voucher_loadings ?? []).flatMap((relation) =>
    relation.loadings ? [relation.loadings] : []
  );
  const candidates =
    related.length > 0 ? related : expense.loadings ? [expense.loadings] : [];

  return Array.from(
    new Map(candidates.map((loading) => [String(loading.id), loading])).values()
  );
}

function getVoucherFreight(expense: ExpenseVoucher) {
  if (expense.voucher_source === "manual") {
    return (expense.manual_voucher_details?.manual_voucher_freight_items ?? []).reduce(
      (total, row) => total + toNumber(row.amount),
      0
    );
  }
  const bookings = new Map<string, number>();

  getVoucherLoadings(expense).forEach((loading) => {
    const booking = relationOne(loading.bookings);
    if (booking) bookings.set(String(booking.id), toNumber(booking.freight));
  });

  return Array.from(bookings.values()).reduce((total, freight) => total + freight, 0);
}
