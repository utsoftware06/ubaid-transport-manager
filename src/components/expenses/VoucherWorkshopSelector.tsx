"use client";

import { useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import {
  WORKSHOP_WORK_TYPE_GROUPS,
  getWorkCategory,
  getWorkTypeLabel,
} from "@/components/workshop/workshopWorkTypes";

export type VoucherWorkshopOption = {
  id: number;
  addaId?: string;
  workDate: string;
  workshopName: string;
  vehicleId: string;
  vehicleNo: string;
  billNo: string;
  totalCost: number;
  workSummary: string;
  attachedVoucherId: number | null;
  attachedVoucherNo: string | null;
  attachedVoucherDate: string | null;
};

export type VoucherWorkshopMasterOption = {
  id: string;
  workshopName: string;
};

export type VoucherWorkshopCreateItem = {
  workType: string;
  category: string;
  quantity: string;
  rate: string;
  remarks: string;
};

export type VoucherWorkshopCreateData = {
  workDate: string;
  workshopId: string;
  mechanicName: string;
  billNo: string;
  paidAmount: string;
  nextServiceDate: string;
  odometer: string;
  workshopRemarks: string;
  paymentMethod: string;
  voucherItemRemarks: string;
  items: VoucherWorkshopCreateItem[];
};

export type VoucherWorkshopMode = "existing" | "create";

type Props = {
  entries: VoucherWorkshopOption[];
  selectedIds: number[];
  onChange: (ids: number[]) => void;
  voucherVehicleId: string | null;

  workshops?: VoucherWorkshopMasterOption[];
  mode?: VoucherWorkshopMode;
  onModeChange?: (mode: VoucherWorkshopMode) => void;

  createData?: VoucherWorkshopCreateData;
  onCreateDataChange?: (data: VoucherWorkshopCreateData) => void;

  disabled?: boolean;
};

const paymentMethods = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
] as const;

function today() {
  return new Date().toISOString().slice(0, 10);
}

export function createEmptyVoucherWorkshopData(): VoucherWorkshopCreateData {
  return {
    workDate: today(),
    workshopId: "",
    mechanicName: "",
    billNo: "",
    paidAmount: "0",
    nextServiceDate: "",
    odometer: "",
    workshopRemarks: "",
    paymentMethod: "Cash",
    voucherItemRemarks: "",
    items: [
      {
        workType: "",
        category: "",
        quantity: "1",
        rate: "0",
        remarks: "",
      },
    ],
  };
}

function numberValue(value: string | number | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value: number) {
  return `Rs. ${value.toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

export default function VoucherWorkshopSelector({
  entries,
  selectedIds,
  onChange,
  voucherVehicleId,
  workshops = [],
  mode = "existing",
  onModeChange,
  createData,
  onCreateDataChange,
  disabled = false,
}: Props) {
  const { t, dir } = useLanguage();

  const [search, setSearch] = useState("");

  const workTypeOptions = useMemo(
    () =>
      WORKSHOP_WORK_TYPE_GROUPS.flatMap(([category, workTypes]) =>
        workTypes.map((workType) => ({
          category,
          workType,
          label: getWorkTypeLabel(workType, t),
        }))
      ),
    [t]
  );

  const internalCreateData =
    createData ?? createEmptyVoucherWorkshopData();

  const filtered = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return entries;

    return entries.filter((entry) =>
      [
        entry.workDate,
        entry.workshopName,
        entry.vehicleNo,
        entry.billNo,
        entry.workSummary,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [entries, search]);

  const selectedEntries = useMemo(
    () => entries.filter((entry) => selectedIds.includes(entry.id)),
    [entries, selectedIds]
  );

  const selectedTotal = useMemo(
    () =>
      selectedEntries.reduce(
        (sum, entry) => sum + numberValue(entry.totalCost),
        0
      ),
    [selectedEntries]
  );

  const newEntryTotal = useMemo(
    () =>
      internalCreateData.items.reduce(
        (sum, item) =>
          sum +
          numberValue(item.quantity) *
            numberValue(item.rate),
        0
      ),
    [internalCreateData.items]
  );

  const paidAmount = numberValue(internalCreateData.paidAmount);

  const remainingAmount = Math.max(
    newEntryTotal - paidAmount,
    0
  );

  const paymentStatus =
    paidAmount <= 0
      ? "Unpaid"
      : paidAmount >= newEntryTotal && newEntryTotal > 0
      ? "Paid"
      : "Partial";

  function changeMode(nextMode: VoucherWorkshopMode) {
    if (disabled) return;

    /*
      Existing bill aur Create New mutually exclusive hain.
      Create mode select karte hi existing selection clear kar dete hain.
    */
    if (nextMode === "create") {
      onChange([]);
    }

    onModeChange?.(nextMode);
  }

  function updateCreateData(
    patch: Partial<VoucherWorkshopCreateData>
  ) {
    if (!onCreateDataChange || disabled) return;

    onCreateDataChange({
      ...internalCreateData,
      ...patch,
    });
  }

  function updateItem(
    index: number,
    field: keyof VoucherWorkshopCreateItem,
    value: string
  ) {
    const items = internalCreateData.items.map((item, itemIndex) =>
      itemIndex === index
        ? {
            ...item,
            [field]: value,
          }
        : item
    );

    updateCreateData({ items });
  }

  function addItem() {
    updateCreateData({
      items: [
        ...internalCreateData.items,
        {
          workType: "",
          category: "",
          quantity: "1",
          rate: "0",
          remarks: "",
        },
      ],
    });
  }

  function removeItem(index: number) {
    if (internalCreateData.items.length <= 1) return;

    updateCreateData({
      items: internalCreateData.items.filter(
        (_, itemIndex) => itemIndex !== index
      ),
    });
  }

  function toggleExistingEntry(entryId: number) {
    if (disabled) return;

    const checked = selectedIds.includes(entryId);

    onChange(
      checked
        ? selectedIds.filter((id) => id !== entryId)
        : [...selectedIds, entryId]
    );
  }

  return (
    <section
      dir={dir}
      className="mt-4 rounded-xl border border-blue-300 bg-blue-50 p-4"
    >
      <div>
        <h3 className="text-lg font-black text-gray-900">
          {t("expenses.workshopLink.title")}
        </h3>

        <p className="mt-1 text-sm font-semibold text-gray-700">
          {t("expenses.workshopLink.description")}
        </p>
      </div>

      {/* MODE SELECTION */}
      <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
        <button
          type="button"
          disabled={disabled}
          onClick={() => changeMode("existing")}
          className={`rounded-xl border p-4 text-start transition ${
            mode === "existing"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:border-blue-400"
          } disabled:cursor-not-allowed disabled:opacity-60`}
        >
          <div className="font-black">
            Existing Workshop Bill
          </div>

          <div
            className={`mt-1 text-sm font-semibold ${
              mode === "existing"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Workshop module mein pehle se bani hui entry select karein.
          </div>
        </button>

        <button
          type="button"
          disabled={disabled}
          onClick={() => changeMode("create")}
          className={`rounded-xl border p-4 text-start transition ${
            mode === "create"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:border-blue-400"
          } disabled:cursor-not-allowed disabled:opacity-60`}
        >
          <div className="font-black">
            Create New Workshop Bill
          </div>

          <div
            className={`mt-1 text-sm font-semibold ${
              mode === "create"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Voucher ke andar se nayi Workshop entry banayein.
          </div>
        </button>
      </div>

      {/* EXISTING WORKSHOP MODE */}
      {mode === "existing" && (
        <>

          <VoiceTypingField fieldLabel={t(
                "expenses.workshopLink.searchPlaceholder"
              )} mode="text"><label className="mt-4 block text-sm font-bold text-gray-900">
            <span className="mb-2 block">
              {t("expenses.workshopLink.search")}
            </span>

            <input
              value={search}
              disabled={disabled}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={t(
                "expenses.workshopLink.searchPlaceholder"
              )}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:bg-gray-100"
            />
          </label></VoiceTypingField>


          <div className="mt-3 max-h-72 overflow-y-auto rounded-lg border border-gray-300 bg-white">
            {filtered.length === 0 ? (
              <p className="p-5 text-center font-semibold text-gray-700">
                {t("expenses.workshopLink.empty")}
              </p>
            ) : (
              filtered.map((entry) => {
                const checked = selectedIds.includes(entry.id);

                return (
                  <label
                    key={entry.id}
                    className="flex cursor-pointer items-start gap-3 border-b border-gray-200 p-3 last:border-0 hover:bg-blue-50"
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={disabled}
                      onChange={() =>
                        toggleExistingEntry(entry.id)
                      }
                      className="mt-1 h-5 w-5 accent-blue-600"
                    />

                    <span className="min-w-0 flex-1 text-sm text-gray-900">
                      <strong dir="ltr">
                        {entry.workDate}
                      </strong>

                      {" | "}

                      <strong>
                        {entry.workshopName}
                      </strong>

                      {" | "}

                      <span dir="ltr">
                        {entry.vehicleNo}
                      </span>

                      <span className="mt-1 block font-semibold">
                        {entry.workSummary}

                        {entry.billNo
                          ? ` · ${t(
                              "workshop.fields.billNo"
                            )}: ${entry.billNo}`
                          : ""}
                      </span>

                      <span
                        className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-xs font-black ${
                          entry.attachedVoucherId === null
                            ? "border-gray-300 bg-white text-gray-700"
                            : "border-blue-300 bg-blue-100 text-blue-900"
                        }`}
                      >
                        {t(
                          entry.attachedVoucherId === null
                            ? "expenses.workshopLink.notAttached"
                            : "expenses.workshopLink.attached"
                        )}
                      </span>

                      {entry.attachedVoucherId !== null && (
                        <span
                          dir="ltr"
                          className="ms-2 text-xs font-bold text-blue-900"
                        >
                          {entry.attachedVoucherNo ||
                            entry.attachedVoucherId}

                          {entry.attachedVoucherDate
                            ? ` · ${entry.attachedVoucherDate}`
                            : ""}
                        </span>
                      )}
                    </span>

                    <strong
                      dir="ltr"
                      className="whitespace-nowrap text-blue-800"
                    >
                      {money(entry.totalCost)}
                    </strong>
                  </label>
                );
              })
            )}
          </div>

          <div className="mt-3 flex flex-wrap justify-between gap-2 rounded-lg border border-blue-200 bg-white p-3 font-black text-gray-900">
            <span>
              {t("expenses.workshopLink.selectedCount")}:{" "}
              <b dir="ltr">{selectedIds.length}</b>
            </span>

            <span>
              {t("expenses.workshopLink.selectedTotal")}:{" "}
              <b dir="ltr">
                {money(selectedTotal)}
              </b>
            </span>
          </div>
        </>
      )}

      {/* CREATE NEW WORKSHOP MODE */}
      {mode === "create" && (
        <div className="mt-4 space-y-5">
          <div className="rounded-xl border border-gray-300 bg-white p-4">
            <h4 className="text-lg font-black text-gray-900">
              New Workshop Bill
            </h4>

            <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

              <VoiceTypingField fieldLabel="Work Date *" mode="date"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Work Date *
                </span>

                <input
                  type="date"
                  value={internalCreateData.workDate}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      workDate: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Workshop *
                </span>

                <select
                  value={internalCreateData.workshopId}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      workshopId: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="">
                    Select Workshop
                  </option>

                  {workshops.map((workshop) => (
                    <option
                      key={workshop.id}
                      value={workshop.id}
                    >
                      {workshop.workshopName}
                    </option>
                  ))}
                </select>
              </label>

              <VoiceTypingField fieldLabel="Mechanic Name" mode="text"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Mechanic Name
                </span>

                <input
                  value={internalCreateData.mechanicName}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      mechanicName: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <VoiceTypingField fieldLabel="Bill No" mode="identifier"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Bill No
                </span>

                <input
                  dir="ltr"
                  value={internalCreateData.billNo}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      billNo: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>

            </div>
          </div>

          {/* WORK ITEMS */}
          <div className="rounded-xl border border-gray-300 bg-white p-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h4 className="text-lg font-black text-gray-900">
                  Workshop Work Items
                </h4>

                <p className="text-sm font-semibold text-gray-600">
                  Har kaam ko alag row mein enter karein.
                </p>
              </div>

              <button
                type="button"
                disabled={disabled}
                onClick={addItem}
                className="rounded-lg bg-blue-600 px-4 py-2 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-60"
              >
                + Add Work Item
              </button>
            </div>

            <datalist id="voucher-workshop-work-types">
              {workTypeOptions.map((option) => (
                <option key={option.workType} value={option.label}>
                  {t(`workshop.workItems.categories.${option.category}`)}
                </option>
              ))}
            </datalist>

            <div className="mt-4 space-y-3">
              {internalCreateData.items.map(
                (item, index) => {
                  const lineTotal =
                    numberValue(item.quantity) *
                    numberValue(item.rate);

                  return (
                    <div
                      key={index}
                      className="rounded-xl border border-gray-200 bg-gray-50 p-4"
                    >
                      <div className="mb-3 flex items-center justify-between">
                        <strong className="text-gray-900">
                          Item #{index + 1}
                        </strong>

                        {internalCreateData.items.length >
                          1 && (
                          <button
                            type="button"
                            disabled={disabled}
                            onClick={() =>
                              removeItem(index)
                            }
                            className="rounded bg-red-600 px-3 py-1.5 text-sm font-bold text-white disabled:opacity-60"
                          >
                            Remove
                          </button>
                        )}
                      </div>

                      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-6">

                        <VoiceTypingField fieldLabel="Search Brake, Oil, Kamani, Engine..." mode="text"><label className="text-sm font-bold text-gray-900 xl:col-span-2">
                          <span className="mb-1 block">
                            Work Type *
                          </span>

                          <input
                            list="voucher-workshop-work-types"
                            value={
                              item.workType
                                ? getWorkTypeLabel(item.workType, t)
                                : ""
                            }
                            disabled={disabled}
                            onChange={(event) => {
                              const typedValue = event.target.value;
                              const matchedOption = workTypeOptions.find(
                                (option) =>
                                  option.label.toLowerCase() ===
                                  typedValue.trim().toLowerCase()
                              );

                              const nextWorkType =
                                matchedOption?.workType ?? typedValue;
                              const nextCategory =
                                matchedOption?.category ??
                                getWorkCategory(nextWorkType);

                              const items =
                                internalCreateData.items.map(
                                  (currentItem, itemIndex) =>
                                    itemIndex === index
                                      ? {
                                          ...currentItem,
                                          workType: nextWorkType,
                                          category: nextCategory,
                                        }
                                      : currentItem
                                );

                              updateCreateData({ items });
                            }}
                            placeholder="Search Brake, Oil, Kamani, Engine..."
                            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5"
                          />
                        </label></VoiceTypingField>


                        <label className="text-sm font-bold text-gray-900">
                          <span className="mb-1 block">
                            Category
                          </span>

                          <input
                            value={
                              item.category
                                ? t(
                                    `workshop.workItems.categories.${item.category}`
                                  )
                                : ""
                            }
                            readOnly
                            disabled={disabled}
                            placeholder="Auto"
                            className="w-full rounded-lg border border-gray-300 bg-gray-50 px-3 py-2.5 text-gray-700"
                          />
                        </label>


                        <VoiceTypingField fieldLabel="Quantity *" mode="number"><label className="text-sm font-bold text-gray-900">
                          <span className="mb-1 block">
                            Quantity *
                          </span>

                          <input
                            type="number"
                            min="0.01"
                            step="0.01"
                            dir="ltr"
                            value={item.quantity}
                            disabled={disabled}
                            onChange={(event) =>
                              updateItem(
                                index,
                                "quantity",
                                event.target.value
                              )
                            }
                            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5"
                          />
                        </label></VoiceTypingField>



                        <VoiceTypingField fieldLabel="Rate *" mode="amount"><label className="text-sm font-bold text-gray-900">
                          <span className="mb-1 block">
                            Rate *
                          </span>

                          <input
                            type="number"
                            min="0"
                            step="0.01"
                            dir="ltr"
                            value={item.rate}
                            disabled={disabled}
                            onChange={(event) =>
                              updateItem(
                                index,
                                "rate",
                                event.target.value
                              )
                            }
                            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5"
                          />
                        </label></VoiceTypingField>


                        <div className="text-sm font-bold text-gray-900">
                          <span className="mb-1 block">
                            Amount
                          </span>

                          <div
                            dir="ltr"
                            className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2.5 font-black text-blue-900"
                          >
                            {money(lineTotal)}
                          </div>
                        </div>


                        <VoiceTypingField fieldLabel="Item Remarks" mode="text"><label className="text-sm font-bold text-gray-900 md:col-span-2 xl:col-span-6">
                          <span className="mb-1 block">
                            Item Remarks
                          </span>

                          <input
                            value={item.remarks}
                            disabled={disabled}
                            onChange={(event) =>
                              updateItem(
                                index,
                                "remarks",
                                event.target.value
                              )
                            }
                            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5"
                          />
                        </label></VoiceTypingField>

                      </div>
                    </div>
                  );
                }
              )}
            </div>
          </div>

          {/* PAYMENT / SERVICE DETAILS */}
          <div className="rounded-xl border border-gray-300 bg-white p-4">
            <h4 className="text-lg font-black text-gray-900">
              Payment & Service Details
            </h4>

            <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

              <VoiceTypingField fieldLabel="Paid Amount" mode="amount"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Paid Amount
                </span>

                <input
                  type="number"
                  min="0"
                  step="0.01"
                  dir="ltr"
                  value={internalCreateData.paidAmount}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      paidAmount: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Payment Method *
                </span>

                <select
                  value={internalCreateData.paymentMethod}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      paymentMethod: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  {paymentMethods.map((method) => (
                    <option
                      key={method}
                      value={method}
                    >
                      {method}
                    </option>
                  ))}
                </select>
              </label>

              <VoiceTypingField fieldLabel="Next Service Date" mode="date"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Next Service Date
                </span>

                <input
                  type="date"
                  value={
                    internalCreateData.nextServiceDate
                  }
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      nextServiceDate:
                        event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <VoiceTypingField fieldLabel="Odometer" mode="number"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">
                  Odometer
                </span>

                <input
                  type="number"
                  min="0"
                  step="1"
                  dir="ltr"
                  value={internalCreateData.odometer}
                  disabled={disabled}
                  onChange={(event) =>
                    updateCreateData({
                      odometer: event.target.value,
                    })
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="text-sm font-bold text-gray-900 md:col-span-2">
                <span className="mb-2 block">
                  Workshop Remarks
                </span>

                <VoiceTypingField fieldLabel="Workshop Remarks" value={internalCreateData.workshopRemarks} onValueChange={(workshopRemarks) => updateCreateData({ workshopRemarks })} contextKey={`${voucherVehicleId ?? ""}:${selectedIds.join(",")}`}>
                  <textarea
                    rows={3}
                    value={internalCreateData.workshopRemarks}
                    disabled={disabled}
                    onChange={(event) =>
                      updateCreateData({
                        workshopRemarks:
                          event.target.value,
                      })
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  />
                </VoiceTypingField>
              </label>

              <label className="text-sm font-bold text-gray-900 md:col-span-2">
                <span className="mb-2 block">
                  Voucher Item Remarks
                </span>

                <VoiceTypingField fieldLabel="Voucher Item Remarks" value={internalCreateData.voucherItemRemarks} onValueChange={(voucherItemRemarks) => updateCreateData({ voucherItemRemarks })} contextKey={`${voucherVehicleId ?? ""}:${selectedIds.join(",")}`}>
                  <textarea
                    rows={3}
                    value={internalCreateData.voucherItemRemarks}
                    disabled={disabled}
                    onChange={(event) =>
                      updateCreateData({
                        voucherItemRemarks:
                          event.target.value,
                      })
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  />
                </VoiceTypingField>
              </label>
            </div>
          </div>

          {/* TOTAL SUMMARY */}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <div className="rounded-xl border border-blue-200 bg-white p-4">
              <div className="text-sm font-bold text-gray-600">
                Total Workshop Bill
              </div>

              <div
                dir="ltr"
                className="mt-1 text-xl font-black text-gray-900"
              >
                {money(newEntryTotal)}
              </div>
            </div>

            <div className="rounded-xl border border-blue-200 bg-white p-4">
              <div className="text-sm font-bold text-gray-600">
                Paid Amount
              </div>

              <div
                dir="ltr"
                className="mt-1 text-xl font-black text-gray-900"
              >
                {money(paidAmount)}
              </div>
            </div>

            <div className="rounded-xl border border-blue-200 bg-white p-4">
              <div className="text-sm font-bold text-gray-600">
                Remaining
              </div>

              <div
                dir="ltr"
                className="mt-1 text-xl font-black text-gray-900"
              >
                {money(remainingAmount)}
              </div>
            </div>

            <div className="rounded-xl border border-blue-200 bg-white p-4">
              <div className="text-sm font-bold text-gray-600">
                Status
              </div>

              <div className="mt-1 text-xl font-black text-blue-800">
                {paymentStatus}
              </div>
            </div>
          </div>

          {paidAmount > newEntryTotal &&
            newEntryTotal > 0 && (
              <div className="rounded-lg border border-red-300 bg-red-50 p-3 font-bold text-red-700">
                Paid Amount Workshop Total se zyada
                nahi ho sakta.
              </div>
            )}
        </div>
      )}
    </section>
  );
}
