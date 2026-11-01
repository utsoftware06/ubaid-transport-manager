"use client";

import { useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export type VoucherOilOption = {
  id: string;
  addaId?: string;
  entryDate: string;
  vehicleId: string;
  vehicleNo: string;
  productName: string;
  liters: number;
  ratePerLiter: number;
  totalAmount: number;
  billNo: string;
  sourceType: "external_shop" | "adda_stock";
  oilShopName: string;
  attachedVoucherId: number | null;
  attachedVoucherNo: string | null;
  attachedVoucherDate: string | null;
};

export type VoucherOilProductOption = {
  id: string;
  addaId?: string;
  oilType: string;
  brand: string;
  grade: string;
};

export type VoucherOilShopOption = {
  id: string;
  addaId?: string;
  shopName: string;
};

export type VoucherOilCreatePayload = {
  entryDate: string;
  sourceType: "external_shop" | "adda_stock";
  oilShopId: string;
  oilProductId: string;
  liters: number;
  ratePerLiter: number;
  billNo: string;
  odometer: number | null;
  nextOilChangeDate: string;
  oilRemarks: string;
  paymentMethod: string;
  voucherItemRemarks: string;
};

type Props = {
  entries: VoucherOilOption[];
  selectedIds: string[];
  onChange: (ids: string[]) => void;

  /*
   * Ye props abhi optional hain.
   * Next step mein ExpenseItems.tsx aur expenses/page.tsx se pass karenge.
   */
  voucherVehicleId?: string;
  voucherVehicleNo?: string;
  products?: VoucherOilProductOption[];
  shops?: VoucherOilShopOption[];
  defaultEntryDate?: string;
  onCreate?: (payload: VoucherOilCreatePayload) => Promise<void> | void;
  isCreating?: boolean;
  mode?: Mode;
  onModeChange?: (mode: Mode) => void;
};

type Mode = "existing" | "create";

function amount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

function productLabel(product: VoucherOilProductOption) {
  return [product.oilType, product.brand, product.grade]
    .filter(Boolean)
    .join(" · ");
}

export default function VoucherOilSelector({
  entries,
  selectedIds,
  onChange,
  voucherVehicleId = "",
  voucherVehicleNo = "",
  products = [],
  shops = [],
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

  const [entryDate, setEntryDate] = useState(defaultEntryDate);
  const [sourceType, setSourceType] =
    useState<"external_shop" | "adda_stock">("external_shop");
  const [oilShopId, setOilShopId] = useState("");
  const [oilProductId, setOilProductId] = useState("");
  const [liters, setLiters] = useState("");
  const [ratePerLiter, setRatePerLiter] = useState("");
  const [billNo, setBillNo] = useState("");
  const [odometer, setOdometer] = useState("");
  const [nextOilChangeDate, setNextOilChangeDate] = useState("");
  const [oilRemarks, setOilRemarks] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [voucherItemRemarks, setVoucherItemRemarks] = useState("");

  /*
   * Extra frontend protection:
   * voucherVehicleId milne ke baad sirf isi gari ki Oil entries show hongi.
   *
   * Backend already same Adda + same authoritative Vehicle enforce karta hai.
   */
  const vehicleEntries = useMemo(() => {
    if (!voucherVehicleId) return entries;

    return entries.filter(
      (entry) => entry.vehicleId === voucherVehicleId
    );
  }, [entries, voucherVehicleId]);

  const filtered = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return vehicleEntries;

    return vehicleEntries.filter((entry) =>
      [
        entry.entryDate,
        entry.vehicleNo,
        entry.productName,
        entry.billNo,
        entry.oilShopName,
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

  const litersNumber = Number(liters || 0);
  const rateNumber = Number(ratePerLiter || 0);

  const createTotal =
    Number.isFinite(litersNumber) &&
    Number.isFinite(rateNumber)
      ? litersNumber * rateNumber
      : 0;

  function switchMode(nextMode: Mode) {
    if (controlledMode === undefined) setInternalMode(nextMode);
    onModeChange?.(nextMode);

    /*
     * Existing aur Create mode mutually exclusive rahenge.
     */
    if (nextMode === "create") {
      onChange([]);
    }
  }

  function resetCreateForm() {
    setEntryDate(defaultEntryDate);
    setSourceType("external_shop");
    setOilShopId("");
    setOilProductId("");
    setLiters("");
    setRatePerLiter("");
    setBillNo("");
    setOdometer("");
    setNextOilChangeDate("");
    setOilRemarks("");
    setPaymentMethod("Cash");
    setVoucherItemRemarks("");
  }

  async function handleCreate() {
    if (!onCreate) {
      alert(
        "Create New Oil Entry backend connection abhi next step mein add hogi."
      );
      return;
    }

    if (!entryDate) {
      alert("Entry Date required hai.");
      return;
    }

    if (!oilProductId) {
      alert("Oil Product select karein.");
      return;
    }

    if (sourceType === "external_shop" && !oilShopId) {
      alert("External Oil Shop select karein.");
      return;
    }

    if (
      !Number.isFinite(litersNumber) ||
      litersNumber <= 0
    ) {
      alert("Litres 0 se zyada honi chahiye.");
      return;
    }

    if (
      !Number.isFinite(rateNumber) ||
      rateNumber < 0
    ) {
      alert("Rate valid hona chahiye.");
      return;
    }

    if (createTotal <= 0) {
      alert("Oil Total 0 se zyada hona chahiye.");
      return;
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
      oilShopId:
        sourceType === "external_shop"
          ? oilShopId
          : "",
      oilProductId,
      liters: litersNumber,
      ratePerLiter: rateNumber,
      billNo: billNo.trim(),
      odometer: meter,
      nextOilChangeDate,
      oilRemarks: oilRemarks.trim(),
      paymentMethod,
      voucherItemRemarks:
        voucherItemRemarks.trim(),
    });
  }

  return (
    <section
      dir={dir}
      className="mt-4 rounded-xl border border-blue-300 bg-blue-50 p-4"
    >
      <h3 className="text-lg font-black text-gray-900">
        {t("expenses.oilLink.title")}
      </h3>

      <p className="mt-1 text-sm font-semibold text-gray-700">
        {t("expenses.oilLink.description")}
      </p>

      {voucherVehicleNo && (
        <div className="mt-3 inline-flex rounded-full border border-blue-300 bg-white px-3 py-1 text-sm font-black text-blue-900">
          Voucher Vehicle:&nbsp;
          <span dir="ltr">{voucherVehicleNo}</span>
        </div>
      )}

      {/* MODE BUTTONS */}
      <div className="mt-5 grid grid-cols-1 gap-3 md:grid-cols-2">
        <button
          type="button"
          onClick={() => switchMode("existing")}
          className={`rounded-xl border p-5 text-start transition ${
            mode === "existing"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:bg-blue-50"
          }`}
        >
          <span className="block text-xl font-black">
            Existing Oil Entry
          </span>

          <span
            className={`mt-1 block text-sm font-semibold ${
              mode === "existing"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Oil module mein pehle se bani hui entry
            select karein.
          </span>
        </button>

        <button
          type="button"
          onClick={() => switchMode("create")}
          className={`rounded-xl border p-5 text-start transition ${
            mode === "create"
              ? "border-blue-600 bg-blue-600 text-white"
              : "border-gray-300 bg-white text-gray-900 hover:bg-blue-50"
          }`}
        >
          <span className="block text-xl font-black">
            Create New Oil Entry
          </span>

          <span
            className={`mt-1 block text-sm font-semibold ${
              mode === "create"
                ? "text-blue-50"
                : "text-gray-600"
            }`}
          >
            Isi Voucher ke andar se nayi Oil entry
            create karein.
          </span>
        </button>
      </div>

      {/* ================= EXISTING ================= */}

      {mode === "existing" && (

        <div className="mt-5">
          <label className="block text-sm font-bold text-gray-900">
            Search Oil Entry
          </label>

          <VoiceTypingField fieldLabel={t(
              "expenses.oilLink.searchPlaceholder"
            )} mode="text"><input
            value={search}
            onChange={(event) =>
              setSearch(event.target.value)
            }
            placeholder={t(
              "expenses.oilLink.searchPlaceholder"
            )}
            className="mt-2 w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>

          <div className="mt-3 max-h-72 overflow-y-auto rounded-lg border border-gray-300 bg-white">
            {filtered.length === 0 ? (
              <p className="p-5 text-center font-semibold text-gray-700">
                {t("expenses.oilLink.empty")}
              </p>
            ) : (
              filtered.map((entry) => {
                const checked =
                  selectedIds.includes(entry.id);

                return (
                  <label
                    key={entry.id}
                    className="flex cursor-pointer items-start gap-3 border-b border-gray-200 p-3 last:border-0 hover:bg-blue-50"
                  >
                    <input
                      type="checkbox"
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

                    <span className="min-w-0 flex-1 text-sm text-gray-900">
                      <span className="block">
                        <strong dir="ltr">
                          {entry.entryDate}
                        </strong>
                        {" | "}
                        <strong>
                          {entry.productName}
                        </strong>
                        {" | "}
                        <span dir="ltr">
                          {entry.vehicleNo}
                        </span>
                      </span>

                      <span
                        className="mt-1 block font-semibold"
                        dir="ltr"
                      >
                        {entry.liters} L × Rs.{" "}
                        {entry.ratePerLiter.toLocaleString(
                          "en-PK"
                        )}

                        {entry.billNo
                          ? ` · ${t(
                              "oil.fields.billNo"
                            )}: ${entry.billNo}`
                          : ""}
                      </span>

                      <span className="mt-1 block font-semibold">
                        {t(
                          `oil.options.${
                            entry.sourceType ===
                            "adda_stock"
                              ? "addaStock"
                              : "externalShop"
                          }`
                        )}

                        {entry.oilShopName
                          ? ` · ${entry.oilShopName}`
                          : ""}
                      </span>

                      <span
                        className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-xs font-black ${
                          entry.attachedVoucherId ===
                          null
                            ? "border-gray-300 bg-white text-gray-700"
                            : "border-blue-300 bg-blue-100 text-blue-900"
                        }`}
                      >
                        {t(
                          entry.attachedVoucherId ===
                            null
                            ? "expenses.oilLink.notAttached"
                            : "expenses.oilLink.attached"
                        )}
                      </span>

                      {entry.attachedVoucherId !==
                        null && (
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
                      {amount(entry.totalAmount)}
                    </strong>
                  </label>
                );
              })
            )}
          </div>

          <div className="mt-3 flex flex-wrap justify-between gap-2 rounded-lg border border-blue-200 bg-white p-3 font-black text-gray-900">
            <span>
              {t("expenses.oilLink.selectedCount")}:{" "}
              <b dir="ltr">{selectedIds.length}</b>
            </span>

            <span>
              {t("expenses.oilLink.selectedTotal")}:{" "}
              <b dir="ltr">
                {amount(selectedTotal)}
              </b>
            </span>
          </div>
        </div>

      )}

      {/* ================= CREATE NEW ================= */}

      {mode === "create" && (
        <div className="mt-5 space-y-5">
          <div className="rounded-xl border border-gray-300 bg-white p-5">
            <h4 className="text-xl font-black text-gray-900">
              New Oil Entry
            </h4>

            <p className="mt-1 text-sm font-semibold text-gray-600">
              Entry automatically isi Voucher ki gari
              ke against create hogi.
            </p>

            <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

              <VoiceTypingField fieldLabel="Entry Date *" mode="date"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Entry Date *
                </span>

                <input
                  type="date"
                  dir="ltr"
                  value={entryDate}
                  onChange={(event) =>
                    setEntryDate(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Source Type *
                </span>

                <select
                  value={sourceType}
                  onChange={(event) => {
                    const next =
                      event.target.value as
                        | "external_shop"
                        | "adda_stock";

                    setSourceType(next);

                    if (
                      next === "adda_stock"
                    ) {
                      setOilShopId("");
                    }
                  }}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="external_shop">
                    External Oil Shop
                  </option>

                  <option value="adda_stock">
                    Adda Oil Stock
                  </option>
                </select>
              </label>

              {sourceType ===
                "external_shop" && (
                <label className="font-bold text-gray-900">
                  <span className="mb-2 block">
                    Oil Shop *
                  </span>

                  <select
                    value={oilShopId}
                    onChange={(event) =>
                      setOilShopId(
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                  >
                    <option value="">
                      Select Oil Shop
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

              <label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Oil Product *
                </span>

                <select
                  value={oilProductId}
                  onChange={(event) =>
                    setOilProductId(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="">
                    Select Oil Product
                  </option>

                  {products.map((product) => (
                    <option
                      key={product.id}
                      value={product.id}
                    >
                      {productLabel(product)}
                    </option>
                  ))}
                </select>
              </label>


              <VoiceTypingField fieldLabel="Litres *" mode="number"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Litres *
                </span>

                <input
                  type="number"
                  dir="ltr"
                  min="0.01"
                  step="any"
                  value={liters}
                  onChange={(event) =>
                    setLiters(
                      event.target.value
                    )
                  }
                  placeholder="0"
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Rate Per Litre *" mode="amount"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Rate Per Litre *
                </span>

                <input
                  type="number"
                  dir="ltr"
                  min="0"
                  step="any"
                  value={ratePerLiter}
                  onChange={(event) =>
                    setRatePerLiter(
                      event.target.value
                    )
                  }
                  placeholder="0"
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
                <span className="block text-sm font-bold text-gray-700">
                  Total Oil Amount
                </span>

                <strong
                  dir="ltr"
                  className="mt-2 block text-2xl font-black text-blue-900"
                >
                  {amount(createTotal)}
                </strong>
              </div>


              <VoiceTypingField fieldLabel="Bill No" mode="identifier"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Bill No
                </span>

                <input
                  dir="ltr"
                  value={billNo}
                  onChange={(event) =>
                    setBillNo(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
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
                  value={odometer}
                  onChange={(event) =>
                    setOdometer(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Next Oil Change Date" mode="date"><label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Next Oil Change Date
                </span>

                <input
                  type="date"
                  dir="ltr"
                  value={nextOilChangeDate}
                  onChange={(event) =>
                    setNextOilChangeDate(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </label></VoiceTypingField>


              <label className="font-bold text-gray-900">
                <span className="mb-2 block">
                  Payment Method
                </span>

                <select
                  value={paymentMethod}
                  onChange={(event) =>
                    setPaymentMethod(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                >
                  <option value="Cash">
                    Cash
                  </option>
                  <option value="Bank Transfer">
                    Bank Transfer
                  </option>
                  <option value="JazzCash">
                    JazzCash
                  </option>
                  <option value="EasyPaisa">
                    EasyPaisa
                  </option>
                  <option value="Cheque">
                    Cheque
                  </option>
                </select>

                <small className="mt-1 block font-semibold text-amber-700">
                  External shop payment yahan se
                  Cashbook payment create nahi
                  karegi. Supplier payment Oil
                  Account se hogi.
                </small>
              </label>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <label className="font-bold text-gray-900">
              <span className="mb-2 block">
                Oil Remarks
              </span>

              <VoiceTypingField fieldLabel="Oil Remarks" value={oilRemarks} onValueChange={setOilRemarks} contextKey={`${voucherVehicleId}:${selectedIds.join(",")}`}>
                <textarea
                  rows={3}
                  value={oilRemarks}
                  disabled={isCreating}
                  onChange={(event) =>
                    setOilRemarks(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </VoiceTypingField>
            </label>

            <label className="font-bold text-gray-900">
              <span className="mb-2 block">
                Voucher Item Remarks
              </span>

              <VoiceTypingField fieldLabel="Voucher Item Remarks" value={voucherItemRemarks} onValueChange={setVoucherItemRemarks} contextKey={`${voucherVehicleId}:${selectedIds.join(",")}`}>
                <textarea
                  rows={3}
                  value={voucherItemRemarks}
                  disabled={isCreating}
                  onChange={(event) =>
                    setVoucherItemRemarks(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3"
                />
              </VoiceTypingField>
            </label>
          </div>

          <div className="flex flex-col justify-between gap-3 rounded-xl border border-blue-300 bg-white p-4 sm:flex-row sm:items-center">
            <div>
              <div className="text-sm font-bold text-gray-600">
                New Oil Entry Total
              </div>

              <div
                dir="ltr"
                className="mt-1 text-2xl font-black text-blue-900"
              >
                {amount(createTotal)}
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={resetCreateForm}
                disabled={isCreating}
                className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-bold text-gray-900 disabled:cursor-not-allowed"
              >
                Reset
              </button>

              <button
                type="button"
                onClick={() =>
                  void handleCreate()
                }
                disabled={
                  isCreating || createTotal <= 0
                }
                className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
              >
                {isCreating
                  ? "Creating..."
                  : "Create Oil Entry"}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
