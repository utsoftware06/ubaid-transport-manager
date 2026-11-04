"use client";

import {
  EXPENSE_TYPES_BY_CLASS,
  expenseTypeLabelKey,
  type ExpenseClass,
} from "./expenseClassification";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

import VoucherWorkshopSelector, {
  type VoucherWorkshopOption,
  type VoucherWorkshopMasterOption,
  type VoucherWorkshopMode,
  type VoucherWorkshopCreateData,
} from "./VoucherWorkshopSelector";

import VoucherOilSelector, {
  type VoucherOilOption,
  type VoucherOilProductOption,
  type VoucherOilShopOption,
  type VoucherOilCreatePayload,
} from "./VoucherOilSelector";

import VoucherTyreSelector, {
  type VoucherTyreOption,
  type VoucherTyreShopOption,
  type VoucherTyreCreatePayload,
} from "./VoucherTyreSelector";

import type {
  TyreAsset,
  TyreProduct,
  TyrePosition,
} from "@/components/tyre/types";

import VoucherDriverEarningSelector, {
  type VoucherDriverEarningOption,
} from "./VoucherDriverEarningSelector";

type ExpenseItemRow = {
  rowId: number;
  dbId?: number;
  expenseClass: ExpenseClass;
  expenseType: string;
  amount: string;
  paymentMethod: string;
  remarks: string;
  petrolPumpId: string;
  liters: string;
  rate: string;
  paidAmount: string;
  slipNo: string;
};

type PetrolPumpOption = {
  id: string;
  pumpName: string;
  openingBalance: number;
};

type Props = {
  expenseItems: ExpenseItemRow[];
  grandTotal: number;
  regularTotal: number;
  periodicTotal: number;

  petrolPumps: PetrolPumpOption[];

  // =========================
  // WORKSHOP
  // =========================
  workshopEntries: VoucherWorkshopOption[];
  selectedWorkshopEntryIds: number[];
  onWorkshopSelectionChange: (ids: number[]) => void;
  workshopVoucherVehicleId: string | null;
  workshopMasters: VoucherWorkshopMasterOption[];
  workshopMode: VoucherWorkshopMode;
  onWorkshopModeChange: (
    mode: VoucherWorkshopMode
  ) => void;
  workshopCreateData: VoucherWorkshopCreateData;
  onWorkshopCreateDataChange: (
    data: VoucherWorkshopCreateData
  ) => void;

  // =========================
  // OIL
  // =========================
  oilEntries: VoucherOilOption[];
  selectedOilEntryIds: string[];
  onOilSelectionChange: (ids: string[]) => void;

  oilVoucherVehicleId?: string | null;
  oilVoucherVehicleNo?: string;

  oilProducts?: VoucherOilProductOption[];
  oilShops?: VoucherOilShopOption[];

  oilDefaultEntryDate?: string;

  onCreateOilEntry?: (
    payload: VoucherOilCreatePayload
  ) => Promise<void> | void;

  isCreatingOilEntry?: boolean;

  // =========================
  // TYRE
  // =========================
  tyreEntries: VoucherTyreOption[];
  selectedTyreEntryIds: string[];
  onTyreSelectionChange: (ids: string[]) => void;

  tyreVoucherVehicleId?: string | null;
  tyreVoucherVehicleNo?: string;

  tyreShops?: VoucherTyreShopOption[];
  tyreAssets?: TyreAsset[];
  tyreProducts?: TyreProduct[];
  tyrePositions?: TyrePosition[];

  tyreDefaultEntryDate?: string;

  onCreateTyreEntry?: (
    payload: VoucherTyreCreatePayload
  ) => Promise<void> | void;

  isCreatingTyreEntry?: boolean;

  // =========================
  // DRIVER
  // =========================
  driverEarnings: VoucherDriverEarningOption[];
  selectedDriverEarningIds: string[];
  onDriverEarningSelectionChange: (
    ids: string[]
  ) => void;

  // =========================
  // COMMON
  // =========================
  onAddExpenseItem: (
    expenseClass: ExpenseClass
  ) => void;

  onDeleteExpenseItem: (
    rowId: number
  ) => void;

  onExpenseItemChange: (
    rowId: number,
    field: keyof ExpenseItemRow,
    value: string
  ) => void;

  onSave: () => void;

  isSaving: boolean;
};

const paymentMethods = [
  "Cash",
  "Bank Transfer",
  "JazzCash",
  "EasyPaisa",
  "Cheque",
];

function toNumber(value: string) {
  const numericValue = Number(value || 0);

  return Number.isFinite(numericValue)
    ? numericValue
    : 0;
}

function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString(
    "en-PK",
    {
      maximumFractionDigits: 0,
    }
  )}`;
}

function getDieselStatus(
  paidAmount: number,
  totalAmount: number
) {
  if (paidAmount <= 0) return "Unpaid";

  if (paidAmount >= totalAmount)
    return "Paid";

  return "Partial";
}

function getStatusClass(status: string) {
  if (status === "Paid")
    return "border-green-200 bg-green-100 text-green-700";

  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }

  return "border-red-200 bg-red-100 text-red-700";
}

export default function ExpenseItems({
  expenseItems,
  grandTotal,
  regularTotal,
  periodicTotal,

  petrolPumps,

  workshopEntries,
  selectedWorkshopEntryIds,
  onWorkshopSelectionChange,
  workshopVoucherVehicleId,
  workshopMasters,
  workshopMode,
  onWorkshopModeChange,
  workshopCreateData,
  onWorkshopCreateDataChange,

  oilEntries,
  selectedOilEntryIds,
  onOilSelectionChange,
  oilVoucherVehicleId,
  oilVoucherVehicleNo = "",
  oilProducts = [],
  oilShops = [],
  oilDefaultEntryDate = "",
  onCreateOilEntry,
  isCreatingOilEntry = false,

  tyreEntries,
  selectedTyreEntryIds,
  onTyreSelectionChange,
  tyreVoucherVehicleId,
  tyreVoucherVehicleNo = "",
  tyreShops = [],
  tyreAssets = [],
  tyreProducts = [],
  tyrePositions = [],
  tyreDefaultEntryDate = "",
  onCreateTyreEntry,
  isCreatingTyreEntry = false,

  driverEarnings,
  selectedDriverEarningIds,
  onDriverEarningSelectionChange,

  onAddExpenseItem,
  onDeleteExpenseItem,
  onExpenseItemChange,

  onSave,
  isSaving,
}: Props) {
  const { t, dir } = useLanguage();

  return (
    <div
      dir={dir}
      className="mt-10 rounded-xl border border-gray-200 bg-white p-5"
    >
      {/* =========================
          HEADER
      ========================= */}

      <div className="mb-5 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("expenses.items.title")}
          </h2>

          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("expenses.items.description")}
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() =>
              onAddExpenseItem("regular_trip")
            }
            className="rounded-lg bg-green-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-green-700"
          >
            {t("expenses.items.addRegular")}
          </button>

          <button
            type="button"
            onClick={() =>
              onAddExpenseItem(
                "vehicle_periodic"
              )
            }
            className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
          >
            {t("expenses.items.addPeriodic")}
          </button>
        </div>
      </div>

      {/* =========================
          EXPENSE ITEMS
      ========================= */}

      <div className="space-y-5">
        {expenseItems.map((item) => {
          const totalAmount =
            toNumber(item.liters) *
            toNumber(item.rate);

          const paidAmount =
            toNumber(item.paidAmount);

          const remainingAmount =
            Math.max(
              totalAmount - paidAmount,
              0
            );

          const paymentStatus =
            getDieselStatus(
              paidAmount,
              totalAmount
            );

          return (
            <div
              key={item.rowId}
              className="rounded-xl border border-gray-300 bg-white p-4 shadow-sm"
            >
              {/* =========================
                  BASIC EXPENSE FIELDS
              ========================= */}

              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    {t(
                      "expenses.items.expenseClass"
                    )}
                  </label>

                  <select
                    aria-label={t(
                      "expenses.items.expenseClass"
                    )}
                    value={item.expenseClass}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "expenseClass",
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  >
                    <option value="regular_trip">
                      {t(
                        "expenses.items.regularTrip"
                      )}
                    </option>

                    <option value="vehicle_periodic">
                      {t(
                        "expenses.items.vehiclePeriodic"
                      )}
                    </option>
                  </select>
                </div>

                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    {t(
                      "expenses.items.expenseType"
                    )}
                  </label>

                  <select
                    aria-label={t(
                      "expenses.items.expenseType"
                    )}
                    value={item.expenseType}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "expenseType",
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  >
                    <option value="">
                      {t(
                        "expenses.items.selectType"
                      )}
                    </option>

                    {EXPENSE_TYPES_BY_CLASS[
                      item.expenseClass
                    ].map((type) => (
                      <option
                        key={type}
                        value={type}
                      >
                        {t(
                          expenseTypeLabelKey(
                            type
                          )
                        )}
                      </option>
                    ))}
                  </select>
                </div>

                {/* AMOUNT */}


                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    {t("common.amount")}
                  </label>

                  <VoiceTypingField fieldLabel={t(
                      "common.amount"
                    )} mode="amount"><input
                    type="number"
                    aria-label={t(
                      "common.amount"
                    )}
                    dir="ltr"
                    value={item.amount}
                    readOnly={
                      item.expenseType ===
                        "Fuel" ||
                      item.expenseType ===
                        "Workshop" ||
                      item.expenseType ===
                        "Oil / Lubricants" ||
                      item.expenseType ===
                        "Tyre" ||
                      item.expenseType ===
                        "Driver Salary"
                    }
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "amount",
                        event.target.value
                      )
                    }
                    placeholder="0"
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  /></VoiceTypingField>
                </div>


                {/* PAYMENT METHOD */}

                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    {t(
                      "expenses.items.paymentMethod"
                    )}
                  </label>

                  <select
                    aria-label={t(
                      "expenses.items.paymentMethod"
                    )}
                    value={item.paymentMethod}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "paymentMethod",
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  >
                    {paymentMethods.map(
                      (method) => (
                        <option
                          key={method}
                          value={method}
                        >
                          {t(
                            `expenses.paymentMethods.${method
                              .replaceAll(
                                " ",
                                ""
                              )
                              .toLowerCase()}`
                          )}
                        </option>
                      )
                    )}
                  </select>
                </div>

                {/* REMARKS */}

                <div className="md:col-span-2">
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    {t("common.remarks")}
                  </label>

                  <VoiceTypingField fieldLabel={t("common.remarks")} value={item.remarks} onValueChange={(value) => onExpenseItemChange(item.rowId, "remarks", value)} contextKey={String(item.rowId)}>
                    <input
                      type="text"
                      aria-label={t(
                        "common.remarks"
                      )}
                      value={item.remarks}
                      onChange={(event) =>
                        onExpenseItemChange(
                          item.rowId,
                          "remarks",
                          event.target.value
                        )
                      }
                      placeholder={t(
                        "common.remarks"
                      )}
                      className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                    />
                  </VoiceTypingField>
                </div>

                {/* DELETE ROW */}

                <div className="flex items-end">
                  <button
                    type="button"
                    onClick={() =>
                      onDeleteExpenseItem(
                        item.rowId
                      )
                    }
                    className="w-full rounded-lg bg-red-600 px-4 py-3 text-sm font-bold text-white transition hover:bg-red-700"
                  >
                    {t(
                      "expenses.items.deleteRow"
                    )}
                  </button>
                </div>
              </div>

              {/* =========================
                  DIESEL / FUEL
              ========================= */}

              {item.expenseType ===
                "Fuel" && (
                <div className="mt-5 rounded-xl border border-blue-100 bg-blue-50 p-4">
                  <h3 className="mb-4 text-lg font-bold text-gray-900">
                    {t(
                      "expenses.diesel.title"
                    )}
                  </h3>

                  <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
                    {/* PETROL PUMP */}

                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        {t(
                          "expenses.diesel.petrolPump"
                        )}
                      </label>

                      <select
                        aria-label={t(
                          "expenses.diesel.petrolPump"
                        )}
                        value={
                          item.petrolPumpId
                        }
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "petrolPumpId",
                            event.target
                              .value
                          )
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      >
                        <option value="">
                          {t(
                            "expenses.diesel.selectPetrolPump"
                          )}
                        </option>

                        {petrolPumps.map(
                          (pump) => (
                            <option
                              key={
                                pump.id
                              }
                              value={
                                pump.id
                              }
                            >
                              {
                                pump.pumpName
                              }
                            </option>
                          )
                        )}
                      </select>
                    </div>

                    {/* LITRES */}


                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        {t(
                          "expenses.diesel.litres"
                        )}
                      </label>

                      <VoiceTypingField fieldLabel={t(
                          "expenses.diesel.litres"
                        )} mode="amount"><input
                        type="number"
                        aria-label={t(
                          "expenses.diesel.litres"
                        )}
                        dir="ltr"
                        min="0"
                        value={item.liters}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "liters",
                            event.target
                              .value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      /></VoiceTypingField>
                    </div>


                    {/* RATE */}


                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        {t(
                          "expenses.diesel.rate"
                        )}
                      </label>

                      <VoiceTypingField fieldLabel={t(
                          "expenses.diesel.rate"
                        )} mode="amount"><input
                        type="number"
                        aria-label={t(
                          "expenses.diesel.rate"
                        )}
                        dir="ltr"
                        min="0"
                        value={item.rate}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "rate",
                            event.target
                              .value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      /></VoiceTypingField>
                    </div>


                    {/* TOTAL */}

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">
                        {t("common.total")}
                      </p>

                      <p className="mt-2 text-xl font-extrabold text-gray-900">
                        {formatAmount(
                          totalAmount
                        )}
                      </p>
                    </div>

                    {/* PAID */}


                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        {t(
                          "expenses.diesel.paidAmount"
                        )}
                      </label>

                      <VoiceTypingField fieldLabel={t(
                          "expenses.diesel.paidAmount"
                        )} mode="amount"><input
                        type="number"
                        aria-label={t(
                          "expenses.diesel.paidAmount"
                        )}
                        dir="ltr"
                        min="0"
                        value={
                          item.paidAmount
                        }
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "paidAmount",
                            event.target
                              .value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      /></VoiceTypingField>
                    </div>


                    {/* REMAINING */}

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">
                        {t(
                          "common.remaining"
                        )}
                      </p>

                      <p className="mt-2 text-xl font-extrabold text-red-700">
                        {formatAmount(
                          remainingAmount
                        )}
                      </p>
                    </div>

                    {/* STATUS */}

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">
                        {t("common.status")}
                      </p>

                      <span
                        className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                          paymentStatus
                        )}`}
                      >
                        {t(
                          `common.paymentStatus.${paymentStatus.toLowerCase()}`
                        )}
                      </span>
                    </div>

                    {/* SLIP */}


                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        {t(
                          "expenses.diesel.slipNo"
                        )}
                      </label>

                      <VoiceTypingField fieldLabel={t(
                          "expenses.diesel.slipNo"
                        )} mode="identifier"><input
                        type="text"
                        aria-label={t(
                          "expenses.diesel.slipNo"
                        )}
                        dir="ltr"
                        value={item.slipNo}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "slipNo",
                            event.target
                              .value
                          )
                        }
                        placeholder={t(
                          "expenses.diesel.slipNo"
                        )}
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      /></VoiceTypingField>
                    </div>

                  </div>
                </div>
              )}

              {/* =========================
                  WORKSHOP
              ========================= */}

              {item.expenseClass ===
                "vehicle_periodic" &&
                item.expenseType ===
                  "Workshop" && (
                  <VoucherWorkshopSelector
                    entries={
                      workshopEntries
                    }
                    selectedIds={
                      selectedWorkshopEntryIds
                    }
                    onChange={
                      onWorkshopSelectionChange
                    }
                    voucherVehicleId={
                      workshopVoucherVehicleId
                    }
                    workshops={
                      workshopMasters
                    }
                    mode={workshopMode}
                    onModeChange={
                      onWorkshopModeChange
                    }
                    createData={
                      workshopCreateData
                    }
                    onCreateDataChange={
                      onWorkshopCreateDataChange
                    }
                    disabled={isSaving}
                  />
                )}

              {/* =========================
                  OIL
              ========================= */}

              {item.expenseClass ===
                "vehicle_periodic" &&
                item.expenseType ===
                  "Oil / Lubricants" && (
                  <VoucherOilSelector
                    entries={oilEntries}
                    selectedIds={
                      selectedOilEntryIds
                    }
                    onChange={
                      onOilSelectionChange
                    }
                    voucherVehicleId={
                      oilVoucherVehicleId ??
                      ""
                    }
                    voucherVehicleNo={
                      oilVoucherVehicleNo
                    }
                    products={oilProducts}
                    shops={oilShops}
                    defaultEntryDate={
                      oilDefaultEntryDate
                    }
                    onCreate={
                      onCreateOilEntry
                    }
                    isCreating={
                      isCreatingOilEntry ||
                      isSaving
                    }
                  />
                )}

              {/* =========================
                  TYRE
              ========================= */}

              {item.expenseClass ===
                "vehicle_periodic" &&
                item.expenseType ===
                  "Tyre" && (
                  <VoucherTyreSelector
                    entries={tyreEntries}
                    selectedIds={
                      selectedTyreEntryIds
                    }
                    onChange={
                      onTyreSelectionChange
                    }
                    voucherVehicleId={
                      tyreVoucherVehicleId ??
                      ""
                    }
                    voucherVehicleNo={
                      tyreVoucherVehicleNo
                    }
                    shops={tyreShops}
                    assets={tyreAssets}
                    products={tyreProducts}
                    positions={tyrePositions}
                    defaultEntryDate={
                      tyreDefaultEntryDate
                    }
                    onCreate={
                      onCreateTyreEntry
                    }
                    isCreating={
                      isCreatingTyreEntry ||
                      isSaving
                    }
                  />
                )}

              {/* =========================
                  DRIVER SALARY
              ========================= */}

              {item.expenseClass ===
                "vehicle_periodic" &&
                item.expenseType ===
                  "Driver Salary" && (
                  <VoucherDriverEarningSelector
                    entries={
                      driverEarnings
                    }
                    selectedIds={
                      selectedDriverEarningIds
                    }
                    onChange={
                      onDriverEarningSelectionChange
                    }
                  />
                )}
            </div>
          );
        })}
      </div>

      {/* =========================
          TOTALS + SAVE
      ========================= */}

      <div className="mt-6 flex flex-col justify-between gap-4 rounded-xl border border-gray-300 bg-white p-4 shadow-sm lg:flex-row lg:items-center">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <p className="text-sm font-bold text-gray-700">
              {t(
                "expenses.items.regularTotal"
              )}
            </p>

            <p className="mt-1 text-xl font-extrabold text-gray-900">
              {formatAmount(
                regularTotal
              )}
            </p>
          </div>

          <div>
            <p className="text-sm font-bold text-gray-700">
              {t(
                "expenses.items.periodicTotal"
              )}
            </p>

            <p className="mt-1 text-xl font-extrabold text-gray-900">
              {formatAmount(
                periodicTotal
              )}
            </p>
          </div>

          <div>
            <p className="text-sm font-bold text-gray-900">
              {t(
                "expenses.items.grandTotal"
              )}
            </p>

            <p className="mt-1 text-2xl font-extrabold text-blue-900">
              {formatAmount(
                grandTotal
              )}
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t(
                "common.states.saving"
              )
            : t(
                "expenses.actions.saveVoucher"
              )}
        </button>
      </div>
    </div>
  );
}
