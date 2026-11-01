"use client";

import { useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";

import type {
  EntryLine,
  TyreAsset,
  TyrePosition,
  TyreProduct,
  TyreSourceType,
  TyreWorkType,
} from "@/components/tyre/types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export type VoucherTyreOption = {
  id: string;
  addaId?: string;
  entryDate: string;
  vehicleId: string;
  vehicleNo: string;
  shopName: string;
  billNo: string;
  workType: string;
  serials: string[];
  positions: string[];
  totalAmount: number;
  attachedVoucherId: number | null;
  attachedVoucherNo: string | null;
  attachedVoucherDate: string | null;
};

export type VoucherTyreShopOption = {
  id: string;
  addaId?: string;
  shopName: string;
};

export type VoucherTyreCreateLine = {
  workType: TyreWorkType;
  tyreAssetId: string;
  positionId: string;
  quantity: number;
  rate: number;
  remarks: string;
  removalReason: string;
};

export type VoucherTyreCreatePayload = {
  entryDate: string;
  sourceType: TyreSourceType;
  tyreShopId: string;
  workType: TyreWorkType;
  billNo: string;
  odometer: number | null;
  tyreRemarks: string;
  paymentMethod: string;
  voucherItemRemarks: string;
  items: VoucherTyreCreateLine[];
};

type Mode = "existing" | "create";

type Props = {
  entries: VoucherTyreOption[];
  selectedIds: string[];
  onChange: (ids: string[]) => void;

  /*
   * Optional for now so the existing Voucher parent keeps compiling.
   * ExpenseItems/page.tsx wiring will be the next step.
   */
  voucherVehicleId?: string;
  voucherVehicleNo?: string;
  shops?: VoucherTyreShopOption[];
  assets?: TyreAsset[];
  products?: TyreProduct[];
  positions?: TyrePosition[];
  defaultEntryDate?: string;
  onCreate?: (
    payload: VoucherTyreCreatePayload
  ) => Promise<void> | void;
  isCreating?: boolean;
  mode?: Mode;
  onModeChange?: (mode: Mode) => void;
};

const WORK_TYPES: TyreWorkType[] = [
  "new_tyre",
  "used_tyre",
  "replacement",
  "puncture",
  "retread",
  "tube",
  "flap",
  "wheel_alignment",
  "wheel_balancing",
  "other",
];

function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

function numberValue(value: string) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function isFittingWork(workType: TyreWorkType) {
  return ["new_tyre", "used_tyre", "replacement"].includes(
    workType
  );
}

function newLine(): EntryLine {
  return {
    key: crypto.randomUUID(),
    workType: "new_tyre",
    tyreAssetId: "",
    positionId: "",
    quantity: "1",
    rate: "",
    remarks: "",
    removalReason: "",
  };
}

export default function VoucherTyreSelector({
  entries,
  selectedIds,
  onChange,
  voucherVehicleId = "",
  voucherVehicleNo = "",
  shops = [],
  assets = [],
  products = [],
  positions = [],
  defaultEntryDate = "",
  onCreate,
  isCreating = false,
  mode: controlledMode,
  onModeChange,
}: Props) {
  const { t, dir } = useLanguage();

  const [internalMode, setInternalMode] = useState<Mode>("existing");
  const mode = controlledMode ?? internalMode;
  const [search, setSearch] = useState("");

  const [entryDate, setEntryDate] =
    useState(defaultEntryDate);

  const [sourceType, setSourceType] =
    useState<TyreSourceType>("adda_stock");

  const [tyreShopId, setTyreShopId] = useState("");
  const [billNo, setBillNo] = useState("");
  const [odometer, setOdometer] = useState("");
  const [tyreRemarks, setTyreRemarks] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState("Cash");
  const [voucherItemRemarks, setVoucherItemRemarks] =
    useState("");

  const [lines, setLines] = useState<EntryLine[]>([
    newLine(),
  ]);

  /*
   * Existing mode:
   * frontend par bhi Voucher ki authoritative Gari filter.
   * Database remains final authority.
   */
  const vehicleEntries = useMemo(() => {
    if (!voucherVehicleId) return entries;

    return entries.filter(
      (entry) => entry.vehicleId === voucherVehicleId
    );
  }, [entries, voucherVehicleId]);

  const filteredEntries = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return vehicleEntries;

    return vehicleEntries.filter((entry) =>
      [
        entry.entryDate,
        entry.vehicleNo,
        entry.shopName,
        entry.billNo,
        entry.workType,
        ...entry.serials,
        ...entry.positions,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [search, vehicleEntries]);

  const selectedEntries = useMemo(
    () =>
      vehicleEntries.filter((entry) =>
        selectedIds.includes(entry.id)
      ),
    [selectedIds, vehicleEntries]
  );

  const selectedTotal = useMemo(
    () =>
      selectedEntries.reduce(
        (sum, entry) => sum + entry.totalAmount,
        0
      ),
    [selectedEntries]
  );

  const createTotal = useMemo(
    () =>
      lines.reduce(
        (sum, line) =>
          sum +
          numberValue(line.quantity) *
            numberValue(line.rate),
        0
      ),
    [lines]
  );

  const vehiclePositions = useMemo(
    () =>
      positions
        .filter(
          (position) =>
            position.isActive &&
            (!voucherVehicleId ||
              position.vehicleId === voucherVehicleId)
        )
        .sort(
          (a, b) =>
            a.sortOrder - b.sortOrder ||
            a.positionCode.localeCompare(
              b.positionCode
            )
        ),
    [positions, voucherVehicleId]
  );

  function assetLabel(asset: TyreAsset) {
    const product = products.find(
      (item) => item.id === asset.tyreProductId
    );

    const productText = product
      ? [
          product.brand,
          product.size,
          product.modelPattern,
        ]
          .filter(Boolean)
          .join(" · ")
      : "";

    return [asset.serialNumber, productText]
      .filter(Boolean)
      .join(" · ");
  }

  function updateLine(
    key: string,
    patch: Partial<EntryLine>
  ) {
    setLines((current) =>
      current.map((line) =>
        line.key === key
          ? {
              ...line,
              ...patch,
            }
          : line
      )
    );
  }

  function switchMode(nextMode: Mode) {
    if (controlledMode === undefined) setInternalMode(nextMode);
    onModeChange?.(nextMode);

    /*
     * Existing and Create-New are mutually exclusive.
     */
    if (nextMode === "create") {
      onChange([]);
    }
  }

  function resetCreateForm() {
    setEntryDate(defaultEntryDate);
    setSourceType("adda_stock");
    setTyreShopId("");
    setBillNo("");
    setOdometer("");
    setTyreRemarks("");
    setPaymentMethod("Cash");
    setVoucherItemRemarks("");
    setLines([newLine()]);
  }

  function changeSource(nextSource: TyreSourceType) {
    setSourceType(nextSource);
    setTyreShopId("");

    /*
     * Source change par old asset selection invalid ho
     * sakti hai, isliye asset reset kar rahe hain.
     */
    setLines((current) =>
      current.map((line) => ({
        ...line,
        tyreAssetId: "",
      }))
    );
  }

  function availableAssetsForLine(line: EntryLine) {
    const fitting = isFittingWork(line.workType);

    const selectedElsewhere = new Set(
      lines
        .filter(
          (other) =>
            other.key !== line.key &&
            other.tyreAssetId
        )
        .map((other) => other.tyreAssetId)
    );

    return assets.filter((asset) => {
      if (selectedElsewhere.has(asset.id)) {
        return false;
      }

      if (fitting) {
        const validStatus = [
          "in_stock",
          "removed",
          "repair",
          "retread",
        ].includes(asset.currentStatus);

        const validSource =
          sourceType === "adda_stock"
            ? asset.sourceType === "adda_stock"
            : asset.sourceType ===
                "external_shop" &&
              asset.tyreShopId === tyreShopId;

        return validStatus && validSource;
      }

      if (
        line.workType === "puncture" ||
        line.workType === "retread"
      ) {
        return (
          !!voucherVehicleId &&
          asset.currentVehicleId ===
            voucherVehicleId
        );
      }

      return true;
    });
  }

  function availablePositionsForLine(
    line: EntryLine
  ) {
    const positionsSelectedElsewhere = new Set(
      lines
        .filter(
          (other) =>
            other.key !== line.key &&
            isFittingWork(other.workType) &&
            other.positionId
        )
        .map((other) => other.positionId)
    );

    return vehiclePositions.filter((position) => {
      if (
        positionsSelectedElsewhere.has(position.id)
      ) {
        return false;
      }

      /*
       * Replacement occupied position par allowed hai.
       * Normal fitting ke liye occupied position hide.
       */
      if (line.workType === "replacement") {
        return true;
      }

      return !assets.some(
        (asset) =>
          asset.currentPositionId === position.id
      );
    });
  }

  async function handleCreate() {
    if (!onCreate) {
      alert(
        "Create New Tyre Entry backend connection next Voucher wiring step mein add hogi."
      );
      return;
    }

    if (!voucherVehicleId) {
      alert("Voucher ki Gari select karein.");
      return;
    }

    if (!entryDate) {
      alert("Tyre Entry Date required hai.");
      return;
    }

    if (
      sourceType === "external_shop" &&
      !tyreShopId
    ) {
      alert("External Tyre Shop select karein.");
      return;
    }

    if (lines.length === 0) {
      alert("Kam az kam 1 Tyre line required hai.");
      return;
    }

    if (createTotal <= 0) {
      alert("Tyre Total 0 se zyada hona chahiye.");
      return;
    }

    const selectedAssets = lines
      .filter((line) => line.tyreAssetId)
      .map((line) => line.tyreAssetId);

    if (
      new Set(selectedAssets).size !==
      selectedAssets.length
    ) {
      alert(
        "Same Tyre Asset aik entry mein do dafa select nahi ho sakta."
      );
      return;
    }

    const selectedFittingPositions = lines
      .filter(
        (line) =>
          isFittingWork(line.workType) &&
          line.positionId
      )
      .map((line) => line.positionId);

    if (
      new Set(selectedFittingPositions).size !==
      selectedFittingPositions.length
    ) {
      alert(
        "Same Gari position aik se zyada fitting line mein select nahi ho sakti."
      );
      return;
    }

    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      const quantity = numberValue(line.quantity);
      const rate = numberValue(line.rate);

      if (quantity <= 0) {
        alert(
          `Tyre line ${index + 1}: quantity 0 se zyada honi chahiye.`
        );
        return;
      }

      if (rate < 0) {
        alert(
          `Tyre line ${index + 1}: rate valid hona chahiye.`
        );
        return;
      }

      if (isFittingWork(line.workType)) {
        if (!line.tyreAssetId) {
          alert(
            `Tyre line ${index + 1}: Tyre Asset / Serial select karein.`
          );
          return;
        }

        if (!line.positionId) {
          alert(
            `Tyre line ${index + 1}: Gari Position select karein.`
          );
          return;
        }

        if (quantity !== 1) {
          alert(
            `Tyre line ${index + 1}: fitting quantity 1 honi chahiye.`
          );
          return;
        }
      }

      if (
        line.workType === "replacement" &&
        !line.removalReason.trim()
      ) {
        alert(
          `Tyre line ${index + 1}: Replacement Removal Reason required hai.`
        );
        return;
      }
    }

    const meter =
      odometer.trim() === ""
        ? null
        : Number(odometer);

    if (
      meter !== null &&
      (!Number.isFinite(meter) || meter < 0)
    ) {
      alert("Odometer valid hona chahiye.");
      return;
    }

    await onCreate({
      entryDate,
      sourceType,
      tyreShopId:
        sourceType === "external_shop"
          ? tyreShopId
          : "",
      workType:
        lines[0]?.workType ?? "other",
      billNo: billNo.trim(),
      odometer: meter,
      tyreRemarks: tyreRemarks.trim(),
      paymentMethod,
      voucherItemRemarks:
        voucherItemRemarks.trim(),
      items: lines.map((line) => ({
        workType: line.workType,
        tyreAssetId: line.tyreAssetId,
        positionId: line.positionId,
        quantity: numberValue(line.quantity),
        rate: numberValue(line.rate),
        remarks: line.remarks.trim(),
        removalReason:
          line.removalReason.trim(),
      })),
    });
  }

  return (
    <section
      dir={dir}
      className="mt-4 rounded-xl border border-blue-300 bg-blue-50 p-4"
    >
      <h3 className="text-lg font-black text-gray-900">
        {t("expenses.tyreLink.title")}
      </h3>

      <p className="mt-1 text-sm font-semibold text-gray-700">
        {t("expenses.tyreLink.description")}
      </p>

      {voucherVehicleNo && (
        <div className="mt-3 inline-flex rounded-full border border-blue-300 bg-white px-3 py-1 text-sm font-black text-blue-900">
          Voucher Gari:&nbsp;
          <span dir="ltr">{voucherVehicleNo}</span>
        </div>
      )}

      {/* MODE SELECTION */}
      <div className="mt-5 grid grid-cols-1 gap-3 md:grid-cols-2">
        <button
          type="button"
          disabled={isCreating}
          onClick={() => switchMode("existing")}
          className={`rounded-xl border p-5 text-start transition disabled:cursor-not-allowed disabled:opacity-60 ${
            mode === "existing"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:bg-blue-50"
          }`}
        >
          <span className="block text-xl font-black">
            Existing Tyre Entry
          </span>

          <span
            className={`mt-1 block text-sm font-semibold ${
              mode === "existing"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Tyre module mein pehle se bani hui entry
            select karein.
          </span>
        </button>

        <button
          type="button"
          disabled={isCreating}
          onClick={() => switchMode("create")}
          className={`rounded-xl border p-5 text-start transition disabled:cursor-not-allowed disabled:opacity-60 ${
            mode === "create"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:bg-blue-50"
          }`}
        >
          <span className="block text-xl font-black">
            Create New Tyre Entry
          </span>

          <span
            className={`mt-1 block text-sm font-semibold ${
              mode === "create"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Isi Voucher ke andar nayi Tyre entry
            create karein.
          </span>
        </button>
      </div>

      {/* ================= EXISTING ================= */}

      {mode === "existing" && (

        <div className="mt-5">
          <VoiceTypingField fieldLabel={t(
              "expenses.tyreLink.searchPlaceholder"
            )} mode="text"><input
            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold text-gray-900"
            value={search}
            onChange={(event) =>
              setSearch(event.target.value)
            }
            placeholder={t(
              "expenses.tyreLink.searchPlaceholder"
            )}
          /></VoiceTypingField>

          <div className="mt-3 max-h-72 overflow-y-auto rounded-lg border bg-white">
            {filteredEntries.length === 0 ? (
              <p className="p-5 text-center font-semibold">
                {t("expenses.tyreLink.empty")}
              </p>
            ) : (
              filteredEntries.map((entry) => {
                const checked =
                  selectedIds.includes(entry.id);

                return (
                  <label
                    key={entry.id}
                    className="flex cursor-pointer gap-3 border-b p-3 last:border-0 hover:bg-blue-50"
                  >
                    <input
                      type="checkbox"
                      disabled={isCreating}
                      checked={checked}
                      onChange={() =>
                        onChange(
                          checked
                            ? selectedIds.filter(
                                (id) =>
                                  id !== entry.id
                              )
                            : [
                                ...selectedIds,
                                entry.id,
                              ]
                        )
                      }
                      className="mt-1 h-5 w-5 accent-blue-600"
                    />

                    <span className="min-w-0 flex-1 text-sm">
                      <strong>
                        {entry.entryDate} ·{" "}
                        <span dir="ltr">
                          {entry.vehicleNo}
                        </span>{" "}
                        · {entry.shopName || "-"}
                      </strong>

                      <span className="block font-semibold">
                        {t(
                          `tyre.work.${entry.workType}`
                        )}{" "}
                        · {entry.billNo || "-"}
                      </span>

                      <span className="block">
                        {entry.serials.join(", ") || "-"} ·{" "}
                        {entry.positions.join(", ") || "-"}
                      </span>

                      <span
                        className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-xs font-black ${
                          entry.attachedVoucherId
                            ? "border-blue-300 bg-blue-100 text-blue-900"
                            : "border-gray-300 bg-white text-gray-700"
                        }`}
                      >
                        {t(
                          entry.attachedVoucherId
                            ? "expenses.tyreLink.attached"
                            : "expenses.tyreLink.notAttached"
                        )}
                      </span>

                      {entry.attachedVoucherId && (
                        <span className="ms-2 text-xs font-bold text-blue-900">
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
                      {money(entry.totalAmount)}
                    </strong>
                  </label>
                );
              })
            )}
          </div>

          <div className="mt-3 flex flex-wrap justify-between gap-2 rounded-lg border border-blue-200 bg-white p-3 font-black">
            <span>
              {t("expenses.tyreLink.selectedCount")}:{" "}
              {selectedIds.length}
            </span>

            <span dir="ltr">
              {t("expenses.tyreLink.selectedTotal")}:{" "}
              {money(selectedTotal)}
            </span>
          </div>
        </div>

      )}

      {/* ================= CREATE NEW ================= */}

      {mode === "create" && (
        <div className="mt-5 space-y-5">
          <div className="rounded-xl border border-gray-300 bg-white p-5">
            <div>
              <h4 className="text-xl font-black text-gray-900">
                Create New Tyre Entry
              </h4>

              <p className="mt-1 text-sm font-semibold text-gray-600">
                Entry automatically isi Voucher ki
                authoritative Gari ke against create hogi.
              </p>
            </div>

            <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

              <VoiceTypingField fieldLabel="Entry Date *" mode="date"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Entry Date *
                </span>

                <input
                  type="date"
                  dir="ltr"
                  disabled={isCreating}
                  value={entryDate}
                  onChange={(event) =>
                    setEntryDate(event.target.value)
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Source Type *
                </span>

                <select
                  disabled={isCreating}
                  value={sourceType}
                  onChange={(event) =>
                    changeSource(
                      event.target
                        .value as TyreSourceType
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="adda_stock">
                    Adda Stock
                  </option>

                  <option value="external_shop">
                    External Tyre Shop
                  </option>
                </select>
              </label>

              {sourceType === "external_shop" && (
                <label className="font-bold text-gray-900">
                  <span className="mb-2 block">
                    Tyre Shop *
                  </span>

                  <select
                    disabled={isCreating}
                    value={tyreShopId}
                    onChange={(event) => {
                      setTyreShopId(
                        event.target.value
                      );

                      setLines((current) =>
                        current.map((line) => ({
                          ...line,
                          tyreAssetId: "",
                        }))
                      );
                    }}
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  >
                    <option value="">
                      Select Tyre Shop
                    </option>

                    {shops.map((shop) => (
                      <option
                        key={shop.id}
                        value={shop.id}
                      >
                        {shop.shopName}
                      </option>
                    ))}
                  </select>
                </label>
              )}


              <VoiceTypingField fieldLabel="Bill No" mode="identifier"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Bill No
                </span>

                <input
                  disabled={isCreating}
                  value={billNo}
                  onChange={(event) =>
                    setBillNo(event.target.value)
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  placeholder="Bill No"
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Odometer" mode="number"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Odometer
                </span>

                <input
                  type="number"
                  dir="ltr"
                  min="0"
                  disabled={isCreating}
                  value={odometer}
                  onChange={(event) =>
                    setOdometer(event.target.value)
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  placeholder="0"
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Remarks" mode="text"><label className="font-bold text-gray-900 md:col-span-2">
                <span className="mb-2 block">
                  Tyre Remarks
                </span>

                <input
                  disabled={isCreating}
                  value={tyreRemarks}
                  onChange={(event) =>
                    setTyreRemarks(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  placeholder="Remarks"
                />
              </label></VoiceTypingField>


              <label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Payment Method
                </span>

                <select
                  disabled={isCreating}
                  value={paymentMethod}
                  onChange={(event) =>
                    setPaymentMethod(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="Cash">Cash</option>
                  <option value="Bank">Bank</option>
                </select>
              </label>


              <VoiceTypingField fieldLabel="Voucher Tyre expense remarks" mode="text"><label className="font-bold text-gray-900 md:col-span-2 xl:col-span-4">
                <span className="mb-2 block">
                  Voucher Item Remarks
                </span>

                <input
                  disabled={isCreating}
                  value={voucherItemRemarks}
                  onChange={(event) =>
                    setVoucherItemRemarks(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  placeholder="Voucher Tyre expense remarks"
                />
              </label></VoiceTypingField>

            </div>
          </div>

          {/* TYRE LINES */}

          <div className="space-y-3">
            {lines.map((line, index) => {
              const fitting = isFittingWork(
                line.workType
              );

              const lineAssets =
                availableAssetsForLine(line);

              const linePositions =
                availablePositionsForLine(line);

              return (
                <div
                  key={line.key}
                  className="rounded-xl border border-blue-200 bg-white p-4"
                >
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
                    <h5 className="font-black text-gray-900">
                      Tyre Line {index + 1}
                    </h5>

                    <button
                      type="button"
                      disabled={
                        isCreating ||
                        lines.length === 1
                      }
                      onClick={() =>
                        setLines((current) =>
                          current.filter(
                            (item) =>
                              item.key !== line.key
                          )
                        )
                      }
                      className="rounded-lg bg-red-600 px-3 py-2 text-sm font-black text-white disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Remove Line
                    </button>
                  </div>

                  <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-6">
                    <label className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Work Type *
                      </span>

                      <select
                        disabled={isCreating}
                        value={line.workType}
                        onChange={(event) => {
                          const nextWork =
                            event.target
                              .value as TyreWorkType;

                          updateLine(line.key, {
                            workType: nextWork,
                            tyreAssetId: "",
                            positionId: "",
                            quantity: isFittingWork(
                              nextWork
                            )
                              ? "1"
                              : line.quantity,
                            removalReason: "",
                          });
                        }}
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                      >
                        {WORK_TYPES.map(
                          (workType) => (
                            <option
                              key={workType}
                              value={workType}
                            >
                              {t(
                                `tyre.work.${workType}`
                              )}
                            </option>
                          )
                        )}
                      </select>
                    </label>

                    <label className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Tyre Asset / Serial
                        {fitting ? " *" : ""}
                      </span>

                      <select
                        disabled={isCreating}
                        value={line.tyreAssetId}
                        onChange={(event) => {
                          const assetId =
                            event.target.value;

                          const asset =
                            assets.find(
                              (item) =>
                                item.id === assetId
                            );

                          updateLine(line.key, {
                            tyreAssetId: assetId,
                            rate: asset
                              ? String(
                                  asset.purchaseCost ||
                                    line.rate
                                )
                              : line.rate,
                          });
                        }}
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                      >
                        <option value="">
                          Select Tyre Asset
                        </option>

                        {lineAssets.map((asset) => (
                          <option
                            key={asset.id}
                            value={asset.id}
                          >
                            {assetLabel(asset)}
                          </option>
                        ))}
                      </select>
                    </label>

                    <label className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Gari Position
                        {fitting ? " *" : ""}
                      </span>

                      <select
                        disabled={isCreating}
                        value={line.positionId}
                        onChange={(event) =>
                          updateLine(line.key, {
                            positionId:
                              event.target.value,
                          })
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                      >
                        <option value="">
                          Select Position
                        </option>

                        {linePositions.map(
                          (position) => (
                            <option
                              key={position.id}
                              value={position.id}
                            >
                              {position.positionCode} ·{" "}
                              {
                                position.positionLabel
                              }
                            </option>
                          )
                        )}
                      </select>
                    </label>


                    <VoiceTypingField fieldLabel="Quantity *" mode="number"><label className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Quantity *
                      </span>

                      <input
                        type="number"
                        dir="ltr"
                        min="1"
                        step="1"
                        disabled={
                          isCreating || fitting
                        }
                        value={line.quantity}
                        onChange={(event) =>
                          updateLine(line.key, {
                            quantity:
                              event.target.value,
                          })
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 disabled:bg-gray-100"
                      />
                    </label></VoiceTypingField>



                    <VoiceTypingField fieldLabel="Rate *" mode="amount"><label className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Rate *
                      </span>

                      <input
                        type="number"
                        dir="ltr"
                        min="0"
                        disabled={isCreating}
                        value={line.rate}
                        onChange={(event) =>
                          updateLine(line.key, {
                            rate: event.target.value,
                          })
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                      />
                    </label></VoiceTypingField>


                    <div className="font-bold text-gray-900">
                      <span className="mb-1 block">
                        Line Amount
                      </span>

                      <div
                        dir="ltr"
                        className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-3 font-black text-blue-900"
                      >
                        {money(
                          numberValue(
                            line.quantity
                          ) *
                            numberValue(
                              line.rate
                            )
                        )}
                      </div>
                    </div>

                    {line.workType ===
                      "replacement" && (

                      <VoiceTypingField fieldLabel="Old tyre removal reason" mode="text"><label className="font-bold text-gray-900 md:col-span-2 xl:col-span-3">
                        <span className="mb-1 block">
                          Removal Reason *
                        </span>

                        <input
                          disabled={isCreating}
                          value={
                            line.removalReason
                          }
                          onChange={(event) =>
                            updateLine(line.key, {
                              removalReason:
                                event.target.value,
                            })
                          }
                          className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                          placeholder="Old tyre removal reason"
                        />
                      </label></VoiceTypingField>

                    )}


                    <VoiceTypingField fieldLabel="Remarks" mode="text"><label className="font-bold text-gray-900 md:col-span-2 xl:col-span-3">
                      <span className="mb-1 block">
                        Line Remarks
                      </span>

                      <input
                        disabled={isCreating}
                        value={line.remarks}
                        onChange={(event) =>
                          updateLine(line.key, {
                            remarks:
                              event.target.value,
                          })
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                        placeholder="Remarks"
                      />
                    </label></VoiceTypingField>

                  </div>
                </div>
              );
            })}
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-200 bg-white p-4">
            <button
              type="button"
              disabled={isCreating}
              onClick={() =>
                setLines((current) => [
                  ...current,
                  newLine(),
                ])
              }
              className="rounded-lg border border-slate-300 bg-slate-100 px-4 py-3 font-black text-slate-900 hover:bg-slate-200 disabled:opacity-50"
            >
              + Add Tyre Line
            </button>

            <div
              dir="ltr"
              className="text-xl font-black text-blue-900"
            >
              Total: {money(createTotal)}
            </div>
          </div>

          <div className="flex flex-wrap justify-end gap-3">
            <button
              type="button"
              disabled={isCreating}
              onClick={resetCreateForm}
              className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-black text-gray-900 hover:bg-gray-50 disabled:opacity-50"
            >
              Reset
            </button>

            <button
              type="button"
              disabled={
                isCreating ||
                !voucherVehicleId ||
                createTotal <= 0
              }
              onClick={() => void handleCreate()}
              className="rounded-lg bg-blue-600 px-5 py-3 font-black text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {isCreating
                ? "Creating Tyre Entry..."
                : "Create Tyre Entry"}
            </button>
          </div>

          {!onCreate && (
            <p className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-bold text-amber-900">
              Create-New UI ready hai. Backend Voucher
              connection next parent wiring step mein
              connect hogi.
            </p>
          )}
        </div>
      )}
    </section>
  );
}
