

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type VoucherSummary = {
  id: number;
  expenseNo: string;
  expenseDate: string;
};

type AdjustmentItemDraft = {
  rowId: number;
  expenseClass: "regular_trip" | "vehicle_periodic";
  expenseType: string;
  amount: string;
  remarks: string;
};

type SettlementContext = {
  id: string;
  voucher_id: number;
  movement_group_id: string;
  adda_id: string;
  vehicle_id: string;
  net_vehicle_amount: number | string;
};

type WorkshopEntryRow = {
  id: number;
  adda_id: string;
  work_date: string | null;
  workshop_name: string | null;
  vehicle_id: string | null;
  bill_no: string | null;
  work_type: string | null;
  total_cost: number | string | null;
};

type WorkshopVoucherLinkRow = {
  workshop_entry_id: number;
};

type WorkshopAdjustmentLinkRow = {
  adjustment_id: string;
  workshop_entry_id: number;
};

type VoucherAdjustmentRow = {
  id: string;
  voucher_id: number;
  adjustment_no: string;
  adjustment_date: string;
  reason: string | null;
  status: "draft" | "finalized" | "reversed";
};

type VoucherAdjustmentItemRow = {
  id: string;
  adjustment_id: string;
  line_no: number;
  expense_class: "regular_trip" | "vehicle_periodic";
  expense_type: string;
  amount: number | string;
  remarks: string | null;
};

type FinalizedAdjustmentWithItems = {
  id: string;
  status: string;
  voucher_adjustment_items?: Array<{
    amount: number | string;
  }> | null;
};

type Props = {
  open: boolean;
  voucher: VoucherSummary | null;
  onClose: () => void;
  onChanged?: () => void | Promise<void>;
};

const REGULAR_TYPES = [
  "Toll Tax",
  "Food",
  "Labour",
  "Police",
  "Parking",
  "Maintenance",
  "Other",
];

const PERIODIC_TYPES = [
  "Maintenance",
  "Other",
];

let nextRowId = 1;

function toNumber(value: number | string | null | undefined) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

function localDateString() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function createEmptyRow(): AdjustmentItemDraft {
  const row: AdjustmentItemDraft = {
    rowId: nextRowId++,
    expenseClass: "regular_trip",
    expenseType: "Other",
    amount: "",
    remarks: "",
  };
  return row;
}

function makeAdjustmentNo(expenseNo: string) {
  const suffix = String(Date.now()).slice(-6);
  return `ADJ-${expenseNo}-${suffix}`;
}

export default function VoucherAdjustmentModal({
  open,
  voucher,
  onClose,
  onChanged,
}: Props) {
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isFinalizing, setIsFinalizing] = useState(false);

  const [adjustmentId, setAdjustmentId] = useState<string | null>(null);
  const [adjustmentNo, setAdjustmentNo] = useState("");
  const [adjustmentDate, setAdjustmentDate] = useState(localDateString());
  const [reason, setReason] = useState("");

  const [context, setContext] = useState<SettlementContext | null>(null);
  const [vehicleNo, setVehicleNo] = useState("-");
  const [finalizedAdjustmentTotal, setFinalizedAdjustmentTotal] = useState(0);

  const [rows, setRows] = useState<AdjustmentItemDraft[]>([createEmptyRow()]);
  const [workshopEntries, setWorkshopEntries] = useState<WorkshopEntryRow[]>([]);
  const [selectedWorkshopIds, setSelectedWorkshopIds] = useState<number[]>([]);

  const workshopTotal = useMemo(
    () =>
      workshopEntries
        .filter((entry) => selectedWorkshopIds.includes(entry.id))
        .reduce((sum, entry) => sum + toNumber(entry.total_cost), 0),
    [selectedWorkshopIds, workshopEntries]
  );

  const genericTotal = useMemo(
    () => rows.reduce((sum, row) => sum + toNumber(row.amount), 0),
    [rows]
  );

  const draftTotal = genericTotal + workshopTotal;
  const originalNet = toNumber(context?.net_vehicle_amount);
  const effectiveNet =
    originalNet - finalizedAdjustmentTotal - draftTotal;

  useEffect(() => {
    if (!open || !voucher) return;

    const activeVoucher = voucher;
    let cancelled = false;

    async function load() {
      setIsLoading(true);

      try {
        setAdjustmentId(null);
        setAdjustmentNo(makeAdjustmentNo(activeVoucher.expenseNo));
        setAdjustmentDate(localDateString());
        setReason("");
        setRows([createEmptyRow()]);
        setSelectedWorkshopIds([]);
        setContext(null);
        setVehicleNo("-");
        setFinalizedAdjustmentTotal(0);
        setWorkshopEntries([]);

        const { data: settlementData, error: settlementError } = await supabase
          .from("vehicle_chakkar_settlements")
          .select(
            "id, voucher_id, movement_group_id, adda_id, vehicle_id, net_vehicle_amount"
          )
          .eq("voucher_id", activeVoucher.id)
          .maybeSingle();

        if (settlementError) throw settlementError;
        if (!settlementData) {
          throw new Error("Finalized Voucher settlement was not found.");
        }

        const settlement = settlementData as SettlementContext;
        if (cancelled) return;
        setContext(settlement);

        const [
          vehicleResult,
          draftResult,
          finalizedResult,
          workshopResult,
        ] = await Promise.all([
          supabase
            .from("vehicles")
            .select("id, vehicle_no")
            .eq("id", settlement.vehicle_id)
            .maybeSingle(),

          supabase
            .from("voucher_adjustments")
            .select("id, voucher_id, adjustment_no, adjustment_date, reason, status")
            .eq("voucher_id", activeVoucher.id)
            .eq("status", "draft")
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle(),

          supabase
            .from("voucher_adjustments")
            .select("id, status, voucher_adjustment_items(amount)")
            .eq("voucher_id", activeVoucher.id)
            .eq("status", "finalized"),

          supabase
            .from("workshop_entries")
            .select(
              "id, adda_id, work_date, workshop_name, vehicle_id, bill_no, work_type, total_cost"
            )
            .eq("adda_id", settlement.adda_id)
            .eq("vehicle_id", settlement.vehicle_id)
            .gt("total_cost", 0)
            .order("work_date", { ascending: false }),
        ]);

        if (vehicleResult.error) throw vehicleResult.error;
        if (draftResult.error) throw draftResult.error;
        if (finalizedResult.error) throw finalizedResult.error;
        if (workshopResult.error) throw workshopResult.error;

        if (cancelled) return;

        setVehicleNo(vehicleResult.data?.vehicle_no ?? "-");

        const finalizedRows =
          (finalizedResult.data ?? []) as FinalizedAdjustmentWithItems[];

        setFinalizedAdjustmentTotal(
          finalizedRows.reduce(
            (total, adjustment) =>
              total +
              (adjustment.voucher_adjustment_items ?? []).reduce(
                (itemTotal, item) => itemTotal + toNumber(item.amount),
                0
              ),
            0
          )
        );

        const candidateWorkshopRows =
          (workshopResult.data ?? []) as WorkshopEntryRow[];

        const workshopIds = candidateWorkshopRows.map((entry) => entry.id);

        const [voucherLinksResult, adjustmentLinksResult] =
          workshopIds.length === 0
            ? [
                { data: [] as WorkshopVoucherLinkRow[], error: null },
                { data: [] as WorkshopAdjustmentLinkRow[], error: null },
              ]
            : await Promise.all([
                supabase
                  .from("voucher_workshop_entries")
                  .select("workshop_entry_id")
                  .in("workshop_entry_id", workshopIds),

                supabase
                  .from("voucher_adjustment_workshop_entries")
                  .select("adjustment_id, workshop_entry_id")
                  .in("workshop_entry_id", workshopIds),
              ]);

        if (voucherLinksResult.error) throw voucherLinksResult.error;
        if (adjustmentLinksResult.error) throw adjustmentLinksResult.error;

        const voucherClaimed = new Set(
          ((voucherLinksResult.data ?? []) as WorkshopVoucherLinkRow[]).map(
            (row) => row.workshop_entry_id
          )
        );

        const adjustmentClaims = new Map<number, string>(
          (
            (adjustmentLinksResult.data ?? []) as WorkshopAdjustmentLinkRow[]
          ).map((row) => [row.workshop_entry_id, row.adjustment_id])
        );

        const draft =
          (draftResult.data as VoucherAdjustmentRow | null) ?? null;

        const availableWorkshopRows = candidateWorkshopRows.filter(
          (entry) =>
            !voucherClaimed.has(entry.id) &&
            (!adjustmentClaims.has(entry.id) ||
              adjustmentClaims.get(entry.id) === draft?.id)
        );

        setWorkshopEntries(availableWorkshopRows);

        if (!draft) return;

        setAdjustmentId(draft.id);
        setAdjustmentNo(draft.adjustment_no);
        setAdjustmentDate(draft.adjustment_date);
        setReason(draft.reason ?? "");

        const [itemsResult, linksResult] = await Promise.all([
          supabase
            .from("voucher_adjustment_items")
            .select(
              "id, adjustment_id, line_no, expense_class, expense_type, amount, remarks"
            )
            .eq("adjustment_id", draft.id)
            .order("line_no", { ascending: true }),

          supabase
            .from("voucher_adjustment_workshop_entries")
            .select("adjustment_id, workshop_entry_id")
            .eq("adjustment_id", draft.id),
        ]);

        if (itemsResult.error) throw itemsResult.error;
        if (linksResult.error) throw linksResult.error;

        if (cancelled) return;

        const itemRows =
          (itemsResult.data ?? []) as VoucherAdjustmentItemRow[];

        const genericRows = itemRows
          .filter(
            (item) => item.expense_type.trim().toLowerCase() !== "workshop"
          )
          .map((item) => ({
            rowId: nextRowId++,
            expenseClass: item.expense_class,
            expenseType: item.expense_type,
            amount: String(item.amount ?? ""),
            remarks: item.remarks ?? "",
          }));

        setRows(genericRows.length > 0 ? genericRows : [createEmptyRow()]);

        setSelectedWorkshopIds(
          ((linksResult.data ?? []) as WorkshopAdjustmentLinkRow[]).map(
            (row) => row.workshop_entry_id
          )
        );
      } catch (error) {
        console.error("Unable to load Voucher Adjustment:", error);
        alert(
          error instanceof Error
            ? error.message
            : "Unable to load Voucher Adjustment."
        );
        onClose();
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    }

    void load();

    return () => {
      cancelled = true;
    };
  }, [open, voucher, onClose]);

  if (!open || !voucher) return null;

  function updateRow(
    rowId: number,
    field: keyof AdjustmentItemDraft,
    value: string
  ) {
    setRows((current) =>
      current.map((row) =>
        row.rowId === rowId ? { ...row, [field]: value } : row
      )
    );
  }

  function addRow() {
    setRows((current) => [...current, createEmptyRow()]);
  }

  function removeRow(rowId: number) {
    setRows((current) => {
      const next = current.filter((row) => row.rowId !== rowId);
      return next.length > 0 ? next : [createEmptyRow()];
    });
  }

  function buildItemsPayload() {
    const payload: Array<{
      line_no: number;
      expense_class: "regular_trip" | "vehicle_periodic";
      expense_type: string;
      amount: number;
      remarks: string | null;
    }> = [];

    rows.forEach((row) => {
      const amount = toNumber(row.amount);
      const expenseType = row.expenseType.trim();

      if (!expenseType && amount <= 0 && !row.remarks.trim()) return;

      if (!expenseType) {
        throw new Error("Expense Type is required.");
      }

      if (amount <= 0) {
        throw new Error(
          `Amount must be greater than zero for ${expenseType}.`
        );
      }

      if (
        ["workshop", "oil / lubricants", "tyre", "driver salary"].includes(
          expenseType.toLowerCase()
        )
      ) {
        throw new Error(
          `${expenseType} must be added through its dedicated linked section.`
        );
      }

      payload.push({
        line_no: payload.length + 1,
        expense_class: row.expenseClass,
        expense_type: expenseType,
        amount: Number(amount.toFixed(2)),
        remarks: row.remarks.trim() || null,
      });
    });

    if (selectedWorkshopIds.length > 0) {
      if (workshopTotal <= 0) {
        throw new Error("Selected Workshop total is invalid.");
      }

      payload.push({
        line_no: payload.length + 1,
        expense_class: "vehicle_periodic",
        expense_type: "Workshop",
        amount: Number(workshopTotal.toFixed(2)),
        remarks: "Linked Workshop bill adjustment",
      });
    }

    if (payload.length === 0) {
      throw new Error("Add at least one Adjustment expense.");
    }

    return payload;
  }

  async function saveDraft(showSuccess = true) {
    if (!voucher || !context) {
      throw new Error("Finalized Voucher context is not available.");
    }

    if (!adjustmentNo.trim()) {
      throw new Error("Adjustment No is required.");
    }

    if (!adjustmentDate) {
      throw new Error("Adjustment Date is required.");
    }

    const itemsPayload = buildItemsPayload();

    const { data: savedIdData, error: saveHeaderError } = await supabase.rpc(
      "save_voucher_adjustment",
      {
        p_adjustment_id: adjustmentId,
        p_voucher_id: voucher.id,
        p_adjustment_no: adjustmentNo.trim(),
        p_adjustment_date: adjustmentDate,
        p_reason: reason.trim() || null,
      }
    );

    if (saveHeaderError) {
      throw new Error(saveHeaderError.message);
    }

    const savedId = String(savedIdData ?? adjustmentId ?? "");
    if (!savedId) {
      throw new Error("Adjustment ID was not returned.");
    }

    const { error: itemSaveError } = await supabase.rpc(
      "save_voucher_adjustment_items",
      {
        p_adjustment_id: savedId,
        p_items: itemsPayload,
      }
    );

    if (itemSaveError) {
      throw new Error(itemSaveError.message);
    }

    const { error: workshopSyncError } = await supabase.rpc(
      "sync_voucher_adjustment_workshop_entries",
      {
        p_adjustment_id: savedId,
        p_workshop_entry_ids: selectedWorkshopIds,
      }
    );

    if (workshopSyncError) {
      throw new Error(workshopSyncError.message);
    }

    setAdjustmentId(savedId);

    if (showSuccess) {
      alert("Adjustment draft saved successfully.");
    }

    await onChanged?.();

    return savedId;
  }

  async function handleSaveDraft() {
    if (isSaving || isFinalizing) return;

    setIsSaving(true);
    try {
      await saveDraft(true);
    } catch (error) {
      console.error("Unable to save Voucher Adjustment:", error);
      alert(
        error instanceof Error
          ? error.message
          : "Unable to save Voucher Adjustment."
      );
    } finally {
      setIsSaving(false);
    }
  }

  async function handleFinalize() {
    if (isSaving || isFinalizing) return;

    const confirmed = window.confirm(
      "Finalize this Adjustment? After finalization it will become read-only and will reduce the Owner/Gari balance by the Adjustment total."
    );
    if (!confirmed) return;

    setIsFinalizing(true);

    try {
      const savedId = await saveDraft(false);

      const { error: finalizeError } = await supabase.rpc(
        "finalize_voucher_adjustment",
        {
          p_adjustment_id: savedId,
        }
      );

      if (finalizeError) {
        throw new Error(finalizeError.message);
      }

      alert("Adjustment finalized successfully.");
      await onChanged?.();
      onClose();
    } catch (error) {
      console.error("Unable to finalize Voucher Adjustment:", error);
      alert(
        error instanceof Error
          ? error.message
          : "Unable to finalize Voucher Adjustment."
      );
    } finally {
      setIsFinalizing(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-3"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isSaving && !isFinalizing) {
          onClose();
        }
      }}
    >
      <div className="max-h-[94vh] w-full max-w-7xl overflow-y-auto rounded-2xl bg-white p-5 shadow-2xl md:p-7">
        <div className="flex flex-col justify-between gap-3 border-b border-gray-200 pb-4 md:flex-row md:items-start">
          <div>
            <h2 className="text-2xl font-black text-gray-900">
              Voucher Adjustment
            </h2>
            <p className="mt-1 font-semibold text-gray-700">
              Finalized Voucher{" "}
              <span dir="ltr" className="font-black">
                {voucher.expenseNo}
              </span>{" "}
              will remain unchanged.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={isSaving || isFinalizing}
            className="rounded-lg bg-gray-200 px-5 py-3 font-bold text-gray-900 hover:bg-gray-300 disabled:opacity-60"
          >
            Close
          </button>
        </div>

        {isLoading ? (
          <div className="p-12 text-center text-lg font-black text-gray-900">
            Loading Adjustment...
          </div>
        ) : (
          <>
            <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <div className="rounded-xl border border-gray-300 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-600">
                  Original Voucher
                </p>
                <p dir="ltr" className="mt-1 text-lg font-black text-gray-900">
                  {voucher.expenseNo}
                </p>
              </div>

              <div className="rounded-xl border border-gray-300 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-600">
                  Vehicle
                </p>
                <p dir="ltr" className="mt-1 text-lg font-black text-gray-900">
                  {vehicleNo}
                </p>
              </div>

              <div className="rounded-xl border border-gray-300 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-600">
                  Original Net
                </p>
                <p dir="ltr" className="mt-1 text-lg font-black text-gray-900">
                  {money(originalNet)}
                </p>
              </div>

              <div className="rounded-xl border border-gray-300 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-600">
                  Previous Finalized Adjustments
                </p>
                <p dir="ltr" className="mt-1 text-lg font-black text-red-700">
                  {money(finalizedAdjustmentTotal)}
                </p>
              </div>
            </div>

            <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-3">

              <VoiceTypingField fieldLabel="Adjustment No" mode="text"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">Adjustment No</span>
                <input
                  dir="ltr"
                  value={adjustmentNo}
                  onChange={(event) => setAdjustmentNo(event.target.value)}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold outline-none focus:border-purple-600 focus:ring-2 focus:ring-purple-100"
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Adjustment Date" mode="date"><label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">Adjustment Date</span>
                <input
                  type="date"
                  dir="ltr"
                  value={adjustmentDate}
                  onChange={(event) => setAdjustmentDate(event.target.value)}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold outline-none focus:border-purple-600 focus:ring-2 focus:ring-purple-100"
                />
              </label></VoiceTypingField>


              <label className="text-sm font-bold text-gray-900">
                <span className="mb-2 block">Reason</span>
                <VoiceTypingField fieldLabel="Reason" value={reason} onValueChange={setReason} contextKey={String(voucher.id)}>
                  <input
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                    placeholder="Late expense / correction..."
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold outline-none focus:border-purple-600 focus:ring-2 focus:ring-purple-100"
                  />
                </VoiceTypingField>
              </label>
            </div>

            <section className="mt-6 rounded-xl border border-gray-300 bg-white p-4">
              <div className="flex flex-col justify-between gap-3 md:flex-row md:items-center">
                <div>
                  <h3 className="text-xl font-black text-gray-900">
                    Additional Expenses
                  </h3>
                  <p className="mt-1 text-sm font-semibold text-gray-600">
                    Add late regular or general periodic expenses here.
                  </p>
                </div>

                <button
                  type="button"
                  onClick={addRow}
                  className="rounded-lg bg-purple-600 px-4 py-3 font-bold text-white hover:bg-purple-700"
                >
                  + Add Expense
                </button>
              </div>

              <div className="mt-4 space-y-4">
                {rows.map((row) => {
                  const typeOptions =
                    row.expenseClass === "regular_trip"
                      ? REGULAR_TYPES
                      : PERIODIC_TYPES;

                  return (
                    <div
                      key={row.rowId}
                      className="grid grid-cols-1 gap-3 rounded-xl border border-gray-200 bg-gray-50 p-4 md:grid-cols-2 xl:grid-cols-5"
                    >
                      <label className="text-sm font-bold text-gray-900">
                        <span className="mb-1 block">Expense Class</span>
                        <select
                          value={row.expenseClass}
                          onChange={(event) => {
                            const nextClass = event.target.value as
                              | "regular_trip"
                              | "vehicle_periodic";
                            setRows((current) =>
                              current.map((item) =>
                                item.rowId === row.rowId
                                  ? {
                                      ...item,
                                      expenseClass: nextClass,
                                      expenseType:
                                        nextClass === "regular_trip"
                                          ? "Other"
                                          : "Other",
                                    }
                                  : item
                              )
                            );
                          }}
                          className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold"
                        >
                          <option value="regular_trip">Regular Trip</option>
                          <option value="vehicle_periodic">
                            Vehicle / Periodic
                          </option>
                        </select>
                      </label>

                      <label className="text-sm font-bold text-gray-900">
                        <span className="mb-1 block">Expense Type</span>
                        <select
                          value={row.expenseType}
                          onChange={(event) =>
                            updateRow(
                              row.rowId,
                              "expenseType",
                              event.target.value
                            )
                          }
                          className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold"
                        >
                          {typeOptions.map((type) => (
                            <option key={type} value={type}>
                              {type}
                            </option>
                          ))}
                        </select>
                      </label>


                      <VoiceTypingField fieldLabel="Amount" mode="amount"><label className="text-sm font-bold text-gray-900">
                        <span className="mb-1 block">Amount</span>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          dir="ltr"
                          value={row.amount}
                          onChange={(event) =>
                            updateRow(
                              row.rowId,
                              "amount",
                              event.target.value
                            )
                          }
                          placeholder="0"
                          className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold"
                        />
                      </label></VoiceTypingField>


                      <label className="text-sm font-bold text-gray-900">
                        <span className="mb-1 block">Remarks</span>
                        <VoiceTypingField fieldLabel="Remarks" value={row.remarks} onValueChange={(value) => updateRow(row.rowId, "remarks", value)} contextKey={`${voucher.id}:${row.rowId}`}>
                          <input
                            value={row.remarks}
                            onChange={(event) =>
                              updateRow(
                                row.rowId,
                                "remarks",
                                event.target.value
                              )
                            }
                            placeholder="Optional"
                            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold"
                          />
                        </VoiceTypingField>
                      </label>

                      <div className="flex items-end">
                        <button
                          type="button"
                          onClick={() => removeRow(row.rowId)}
                          className="w-full rounded-lg bg-red-600 px-4 py-3 font-bold text-white hover:bg-red-700"
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>

            <section className="mt-6 rounded-xl border border-blue-300 bg-blue-50 p-4">
              <h3 className="text-xl font-black text-gray-900">
                Workshop Expense
              </h3>
              <p className="mt-1 text-sm font-semibold text-gray-700">
                Only unclaimed Workshop bills for this same vehicle are shown.
              </p>

              <div className="mt-4 max-h-72 overflow-y-auto rounded-xl border border-gray-300 bg-white">
                {workshopEntries.length === 0 ? (
                  <p className="p-5 text-center font-semibold text-gray-600">
                    No available Workshop bill found for this vehicle.
                  </p>
                ) : (
                  workshopEntries.map((entry) => {
                    const checked = selectedWorkshopIds.includes(entry.id);
                    return (
                      <label
                        key={entry.id}
                        className="flex cursor-pointer items-start gap-3 border-b border-gray-200 p-3 last:border-0 hover:bg-blue-50"
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() =>
                            setSelectedWorkshopIds((current) =>
                              checked
                                ? current.filter((id) => id !== entry.id)
                                : [...current, entry.id]
                            )
                          }
                          className="mt-1 h-5 w-5 accent-blue-600"
                        />

                        <span className="min-w-0 flex-1 text-sm text-gray-900">
                          <strong dir="ltr">
                            {entry.work_date ?? "-"}
                          </strong>{" "}
                          |{" "}
                          <strong>
                            {entry.workshop_name ?? "-"}
                          </strong>

                          <span className="mt-1 block font-semibold">
                            {entry.work_type ?? "Workshop"}
                            {entry.bill_no
                              ? ` · Bill: ${entry.bill_no}`
                              : ""}
                          </span>
                        </span>

                        <strong
                          dir="ltr"
                          className="whitespace-nowrap text-blue-800"
                        >
                          {money(toNumber(entry.total_cost))}
                        </strong>
                      </label>
                    );
                  })
                )}
              </div>

              <div className="mt-3 flex flex-wrap justify-between gap-3 rounded-lg border border-blue-200 bg-white p-3 font-black text-gray-900">
                <span>
                  Selected Bills:{" "}
                  <b dir="ltr">{selectedWorkshopIds.length}</b>
                </span>
                <span>
                  Workshop Total:{" "}
                  <b dir="ltr">{money(workshopTotal)}</b>
                </span>
              </div>
            </section>

            <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-3">
              <div className="rounded-xl border border-gray-300 bg-white p-4">
                <p className="text-sm font-bold text-gray-600">
                  Current Adjustment
                </p>
                <p
                  dir="ltr"
                  className="mt-1 text-2xl font-black text-red-700"
                >
                  {money(draftTotal)}
                </p>
              </div>

              <div className="rounded-xl border border-gray-300 bg-white p-4">
                <p className="text-sm font-bold text-gray-600">
                  Total Adjustments After This
                </p>
                <p
                  dir="ltr"
                  className="mt-1 text-2xl font-black text-red-700"
                >
                  {money(finalizedAdjustmentTotal + draftTotal)}
                </p>
              </div>

              <div className="rounded-xl border border-green-300 bg-green-50 p-4">
                <p className="text-sm font-bold text-gray-700">
                  Effective Owner/Gari Net
                </p>
                <p
                  dir="ltr"
                  className="mt-1 text-2xl font-black text-green-800"
                >
                  {money(effectiveNet)}
                </p>
              </div>
            </div>

            <div className="mt-6 flex flex-col-reverse justify-end gap-3 border-t border-gray-200 pt-5 sm:flex-row">
              <button
                type="button"
                onClick={onClose}
                disabled={isSaving || isFinalizing}
                className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-bold text-gray-900 hover:bg-gray-50 disabled:opacity-60"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={handleSaveDraft}
                disabled={isSaving || isFinalizing}
                className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isSaving ? "Saving..." : "Save Draft"}
              </button>

              <button
                type="button"
                onClick={handleFinalize}
                disabled={isSaving || isFinalizing}
                className="rounded-lg bg-purple-700 px-6 py-3 font-bold text-white hover:bg-purple-800 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isFinalizing ? "Finalizing..." : "Finalize Adjustment"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
