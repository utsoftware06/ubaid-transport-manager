"use client";

import { useEffect, useMemo, useState } from "react";
import ExpenseForm from "@/components/expenses/ExpenseForm";
import ExpenseItems from "@/components/expenses/ExpenseItems";
import ExpenseTable from "@/components/expenses/ExpenseTable";
import { supabase } from "@/lib/supabase/client";

type ReceiptStatus = "idle" | "uploading" | "replacing" | "deleting";

type ExpenseItemRow = {
  rowId: number;
  dbId?: number;
  expenseType: string;
  amount: string;
  paymentMethod: string;
  remarks: string;
  receiptUrl: string | null;
  receiptName: string | null;
  receiptFile: File | null;
  receiptStatus: ReceiptStatus;
  receiptError: string;
  petrolPumpId: string;
  liters: string;
  rate: string;
  paidAmount: string;
  slipNo: string;
};

type VehicleRelation = {
  vehicle_no: string | null;
};

type DriverRelation = {
  name: string | null;
};

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicle_id: string | null;
  driver_id: string | null;
  vehicles?: VehicleRelation | null;
  drivers?: DriverRelation | null;
};

type PetrolPumpOption = {
  id: string;
  pumpName: string;
  openingBalance: number;
};

type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
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

type ExpenseVoucher = {
  id: number;
  expense_no: string;
  expense_date: string;
  loading_id: number;
  description: string | null;
  created_at?: string | null;
  loadings?: LoadingRecord | null;
  expense_items?: ExpenseItemRecord[];
  diesel_entries?: DieselEntryRecord[];
};

type ExpenseFormProps = {
  expenseNo: string;
  setExpenseNo: (value: string) => void;
  expenseDate: string;
  setExpenseDate: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  description: string;
  setDescription: (value: string) => void;
  loadings: LoadingRecord[];
  selectedLoading: LoadingRecord | null;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

let nextExpenseItemRowId = 1;

function createEmptyExpenseItem(): ExpenseItemRow {
  const row: ExpenseItemRow = {
    rowId: nextExpenseItemRowId,
    expenseType: "",
    amount: "",
    paymentMethod: "Cash",
    remarks: "",
    receiptUrl: null,
    receiptName: null,
    receiptFile: null,
    receiptStatus: "idle",
    receiptError: "",
    petrolPumpId: "",
    liters: "",
    rate: "",
    paidAmount: "",
    slipNo: "",
  };

  nextExpenseItemRowId += 1;
  return row;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function getDieselStatus(paidAmount: number, totalAmount: number) {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalAmount) return "Paid";
  return "Partial";
}

function mapCashbookPaymentMethod(paymentMethod: string) {
  if (paymentMethod === "Bank Transfer") return "Bank";
  if (paymentMethod === "JazzCash") return "Online Transfer";
  if (paymentMethod === "EasyPaisa") return "Online Transfer";
  if (paymentMethod === "Cheque") return "Cheque";
  if (paymentMethod === "Bank") return "Bank";
  return "Cash";
}

function getReceiptPath(fileUrl: string) {
  const marker = "/expense-receipts/";
  const markerIndex = fileUrl.indexOf(marker);

  if (markerIndex >= 0) {
    return fileUrl.slice(markerIndex + marker.length);
  }

  return "";
}

function isAllowedReceipt(file: File) {
  const allowedTypes = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "application/pdf",
  ];
  const allowedExtensions = [".jpg", ".jpeg", ".png", ".webp", ".pdf"];
  const lowerName = file.name.toLowerCase();

  return (
    allowedTypes.includes(file.type) ||
    allowedExtensions.some((extension) => lowerName.endsWith(extension))
  );
}

export default function ExpensesPage() {
  const [expenseNo, setExpenseNo] = useState("");
  const [expenseDate, setExpenseDate] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [description, setDescription] = useState("");

  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [petrolPumps, setPetrolPumps] = useState<PetrolPumpOption[]>([]);
  const [expenseItems, setExpenseItems] = useState<ExpenseItemRow[]>([
    createEmptyExpenseItem(),
  ]);
  const [expenseVouchers, setExpenseVouchers] = useState<ExpenseVoucher[]>([]);
  const [viewingExpense, setViewingExpense] = useState<ExpenseVoucher | null>(
    null
  );

  const [search, setSearch] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const ExpenseFormComponent =
    ExpenseForm as React.ComponentType<ExpenseFormProps>;

  const selectedLoading = useMemo(() => {
    if (!loadingId) return null;
    return loadings.find((loading) => String(loading.id) === loadingId) ?? null;
  }, [loadingId, loadings]);

  const grandTotal = useMemo(() => {
    return expenseItems.reduce((total, item) => total + toNumber(item.amount), 0);
  }, [expenseItems]);

  const filteredExpenseVouchers = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return expenseVouchers;

    return expenseVouchers.filter((voucher) => {
      const text = [
        voucher.expense_no,
        voucher.expense_date,
        voucher.description ?? "",
        voucher.loadings?.loading_no ?? "",
        voucher.loadings?.vehicles?.vehicle_no ?? "",
        voucher.loadings?.drivers?.name ?? "",
        voucher.loadings?.route ?? "",
        ...(voucher.expense_items ?? []).flatMap((item) => [
          item.expense_type,
          String(item.amount ?? ""),
          item.payment_method,
          item.remarks ?? "",
          item.receipt_name ?? "",
        ]),
        ...(voucher.diesel_entries ?? []).flatMap((diesel) => [
          diesel.petrol_pumps?.pump_name ?? "",
          diesel.slip_no ?? "",
          String(diesel.liters ?? ""),
          String(diesel.rate ?? ""),
          String(diesel.paid_amount ?? ""),
          diesel.payment_status,
        ]),
      ]
        .join(" ")
        .toLowerCase();

      return text.includes(keyword);
    });
  }, [expenseVouchers, search]);

  useEffect(() => {
    loadInitialData();
  }, []);

  async function loadInitialData() {
    await Promise.all([loadLoadings(), loadPetrolPumps(), loadExpenseVouchers()]);
  }

  async function loadLoadings() {
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        *,
        vehicles(vehicle_no),
        drivers(name)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    setLoadings((data ?? []) as LoadingRecord[]);
  }

  async function loadPetrolPumps() {
    const { data, error } = await supabase
      .from("petrol_pumps")
      .select("id, pump_name, opening_balance")
      .order("pump_name", { ascending: true });

    if (error) {
      alert(error.message);
      return;
    }

    setPetrolPumps(
      (data ?? []).map((pump) => ({
        id: String(pump.id),
        pumpName: pump.pump_name ?? "-",
        openingBalance: toNumber(pump.opening_balance),
      }))
    );
  }

  async function loadExpenseVouchers() {
    const { data, error } = await supabase
      .from("expenses")
      .select(
        `
        *,
        loadings(
          *,
          vehicles(vehicle_no),
          drivers(name)
        ),
        expense_items(*)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    const vouchers = (data ?? []) as ExpenseVoucher[];
    const voucherIds = vouchers.map((voucher) => voucher.id);

    if (voucherIds.length === 0) {
      setExpenseVouchers([]);
      return;
    }

    const { data: dieselData, error: dieselError } = await supabase
      .from("diesel_entries")
      .select(
        `
        *,
        petrol_pumps(pump_name)
      `
      )
      .in("expense_id", voucherIds);

    if (dieselError) {
      alert(dieselError.message);
      setExpenseVouchers(vouchers);
      return;
    }

    const dieselEntries = (dieselData ?? []) as DieselEntryRecord[];

    setExpenseVouchers(
      vouchers.map((voucher) => ({
        ...voucher,
        diesel_entries: dieselEntries.filter(
          (diesel) => diesel.expense_id === voucher.id
        ),
      }))
    );
  }

  function resetForm() {
    setExpenseNo("");
    setExpenseDate("");
    setLoadingId("");
    setDescription("");
    setExpenseItems([createEmptyExpenseItem()]);
    setEditingId(null);
  }

  function handleAddExpenseItem() {
    setExpenseItems((previous) => [...previous, createEmptyExpenseItem()]);
  }

  function handleDeleteExpenseItem(rowId: number) {
    setExpenseItems((previous) =>
      previous.length === 1
        ? [createEmptyExpenseItem()]
        : previous.filter((item) => item.rowId !== rowId)
    );
  }

  function onExpenseItemChange(
    rowId: number,
    field: keyof ExpenseItemRow,
    value: string
  ) {
    setExpenseItems((previous) =>
      previous.map((item) => {
        if (item.rowId !== rowId) return item;

        const updated: ExpenseItemRow = {
          ...item,
          [field]: value,
        };

        if (field === "expenseType" && value !== "Fuel") {
          updated.petrolPumpId = "";
          updated.liters = "";
          updated.rate = "";
          updated.paidAmount = "";
          updated.slipNo = "";
        }

        if (
          updated.expenseType === "Fuel" &&
          (field === "liters" || field === "rate")
        ) {
          const totalAmount = toNumber(updated.liters) * toNumber(updated.rate);
          updated.amount = totalAmount > 0 ? String(totalAmount) : "";
        }

        return updated;
      })
    );
  }

  function handleReceiptSelected(rowId: number, file: File) {
    setExpenseItems((previous) =>
      previous.map((item) => {
        if (item.rowId !== rowId) return item;

        if (!isAllowedReceipt(file)) {
          return {
            ...item,
            receiptFile: null,
            receiptError: "Only JPG, PNG, WEBP and PDF files are allowed.",
          };
        }

        if (file.size > 5 * 1024 * 1024) {
          return {
            ...item,
            receiptFile: null,
            receiptError: "Receipt file must be 5 MB or less.",
          };
        }

        return {
          ...item,
          receiptFile: file,
          receiptName: file.name,
          receiptError: "",
        };
      })
    );
  }

  async function handleReceiptDelete(rowId: number) {
    const item = expenseItems.find((currentItem) => currentItem.rowId === rowId);

    if (!item) return;

    setExpenseItems((previous) =>
      previous.map((currentItem) =>
        currentItem.rowId === rowId
          ? { ...currentItem, receiptStatus: "deleting", receiptError: "" }
          : currentItem
      )
    );

    try {
      if (item.receiptUrl) {
        const path = getReceiptPath(item.receiptUrl);

        if (path) {
          const { error } = await supabase.storage
            .from("expense-receipts")
            .remove([path]);

          if (error) throw new Error(error.message);
        }
      }

      if (item.dbId) {
        const { error } = await supabase
          .from("expense_items")
          .update({
            receipt_url: null,
            receipt_name: null,
          })
          .eq("id", item.dbId);

        if (error) throw new Error(error.message);
      }

      setExpenseItems((previous) =>
        previous.map((currentItem) =>
          currentItem.rowId === rowId
            ? {
                ...currentItem,
                receiptUrl: null,
                receiptName: null,
                receiptFile: null,
                receiptStatus: "idle",
                receiptError: "",
              }
            : currentItem
        )
      );
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to delete receipt.";

      setExpenseItems((previous) =>
        previous.map((currentItem) =>
          currentItem.rowId === rowId
            ? {
                ...currentItem,
                receiptStatus: "idle",
                receiptError: message,
              }
            : currentItem
        )
      );
    }
  }

  function handlePreviewReceipt(receiptUrl: string) {
    window.open(receiptUrl, "_blank");
  }

  function validateExpenseVoucher() {
    if (!expenseNo.trim()) {
      alert("Expense Voucher No is required.");
      return false;
    }

    if (!expenseDate) {
      alert("Expense Date is required.");
      return false;
    }

    if (!loadingId) {
      alert("Please select a loading.");
      return false;
    }

    if (expenseItems.length === 0) {
      alert("At least one expense item is required.");
      return false;
    }

    for (const item of expenseItems) {
      if (!item.expenseType) {
        alert("Expense Type is required for every row.");
        return false;
      }

      if (toNumber(item.amount) <= 0) {
        alert("Amount must be greater than 0 for every row.");
        return false;
      }

      if (!item.paymentMethod) {
        alert("Payment Method is required for every row.");
        return false;
      }

      if (item.expenseType === "Fuel") {
        if (!selectedLoading) {
          alert("Loading must be selected for Fuel expense.");
          return false;
        }

        if (!selectedLoading.vehicle_id) {
          alert("Selected loading must contain vehicle for Fuel expense.");
          return false;
        }

        if (!item.petrolPumpId) {
          alert("Petrol Pump is required for Fuel expense.");
          return false;
        }

        if (toNumber(item.liters) <= 0) {
          alert("Litres must be greater than 0 for Fuel expense.");
          return false;
        }

        if (toNumber(item.rate) <= 0) {
          alert("Rate must be greater than 0 for Fuel expense.");
          return false;
        }

        const totalAmount = toNumber(item.amount);
        const paid = toNumber(item.paidAmount);

        if (totalAmount <= 0) {
          alert("Total amount must be greater than 0 for Fuel expense.");
          return false;
        }

        if (paid < 0) {
          alert("Paid amount cannot be negative for Fuel expense.");
          return false;
        }

        if (paid > totalAmount) {
          alert("Paid amount cannot exceed total amount for Fuel expense.");
          return false;
        }
      }
    }

    return true;
  }

  async function uploadReceipt(
    expenseId: number,
    expenseItemId: number,
    item: ExpenseItemRow
  ) {
    if (!item.receiptFile) {
      return {
        receiptUrl: item.receiptUrl,
        receiptName: item.receiptName,
      };
    }

    const extension = item.receiptFile.name.split(".").pop() ?? "file";
    const filePath = `${expenseId}/${expenseItemId}-${Date.now()}.${extension}`;

    setExpenseItems((previous) =>
      previous.map((currentItem) =>
        currentItem.rowId === item.rowId
          ? {
              ...currentItem,
              receiptStatus: item.receiptUrl ? "replacing" : "uploading",
              receiptError: "",
            }
          : currentItem
      )
    );

    if (item.receiptUrl) {
      const oldPath = getReceiptPath(item.receiptUrl);

      if (oldPath) {
        await supabase.storage.from("expense-receipts").remove([oldPath]);
      }
    }

    const { error: uploadError } = await supabase.storage
      .from("expense-receipts")
      .upload(filePath, item.receiptFile, { upsert: true });

    if (uploadError) throw new Error(uploadError.message);

    const { data } = supabase.storage
      .from("expense-receipts")
      .getPublicUrl(filePath);

    return {
      receiptUrl: data.publicUrl,
      receiptName: item.receiptFile.name,
    };
  }

  async function deleteDieselCashbookEntries(expenseId: number) {
    const { data, error } = await supabase
      .from("diesel_entries")
      .select("id")
      .eq("expense_id", expenseId);

    if (error) throw new Error(error.message);

    const dieselIds = (data ?? []).map((row) => String(row.id));

    if (dieselIds.length === 0) return;

    const { error: cashbookError } = await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "diesel")
      .in("reference_id", dieselIds);

    if (cashbookError) throw new Error(cashbookError.message);
  }

  async function syncDieselCashbookEntry(
    dieselEntryId: number,
    item: ExpenseItemRow,
    currentLoading: LoadingRecord
  ) {
    const paidAmount = toNumber(item.paidAmount);

    if (paidAmount <= 0) return;

    const selectedPump = petrolPumps.find(
      (pump) => pump.id === item.petrolPumpId
    );
    const pumpName = selectedPump?.pumpName ?? "Petrol Pump";

    const { data: existingEntry, error: checkError } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "diesel")
      .eq("reference_id", String(dieselEntryId))
      .maybeSingle();

    if (checkError) throw new Error(checkError.message);

    const payload = {
      entry_date: expenseDate,
      entry_type: "Cash Out",
      person_type: "Petrol Pump",
      person_name: pumpName,
      vehicle_id: currentLoading.vehicle_id,
      driver_id: currentLoading.driver_id || null,
      loading_id: currentLoading.id,
      payment_method: mapCashbookPaymentMethod(item.paymentMethod),
      amount: paidAmount,
      description: `Diesel payment to ${pumpName} for vehicle ${
        currentLoading.vehicles?.vehicle_no ?? "-"
      }`,
      reference_type: "diesel",
      reference_id: String(dieselEntryId),
    };

    if (existingEntry) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(payload)
        .eq("id", existingEntry.id);

      if (error) throw new Error(error.message);
      return;
    }

    const { error } = await supabase.from("cashbook_entries").insert(payload);

    if (error) throw new Error(error.message);
  }

  async function createDieselEntries(
    expenseId: number,
    insertedItems: ExpenseItemRecord[],
    sourceItems: ExpenseItemRow[]
  ) {
    if (!selectedLoading) return;

    for (let index = 0; index < sourceItems.length; index += 1) {
      const sourceItem = sourceItems[index];
      const insertedItem = insertedItems[index];

      if (!insertedItem || sourceItem.expenseType !== "Fuel") continue;

      const totalAmount = toNumber(sourceItem.amount);
      const paid = toNumber(sourceItem.paidAmount);
      const remaining = Math.max(totalAmount - paid, 0);

      const { data, error } = await supabase
        .from("diesel_entries")
        .insert({
          expense_id: expenseId,
          expense_item_id: insertedItem.id,
          entry_date: expenseDate,
          petrol_pump_id: sourceItem.petrolPumpId,
          vehicle_id: selectedLoading.vehicle_id,
          driver_id: selectedLoading.driver_id || null,
          loading_id: selectedLoading.id,
          slip_no: sourceItem.slipNo.trim(),
          liters: toNumber(sourceItem.liters),
          rate: toNumber(sourceItem.rate),
          total_amount: totalAmount,
          paid_amount: paid,
          remaining_amount: remaining,
          payment_status: getDieselStatus(paid, totalAmount),
          remarks: sourceItem.remarks.trim(),
        })
        .select("id")
        .single();

      if (error) throw new Error(`Diesel entry failed: ${error.message}`);

      if (data?.id) {
        await syncDieselCashbookEntry(Number(data.id), sourceItem, selectedLoading);
      }
    }
  }

  async function insertExpenseItemsWithReceipts(expenseId: number) {
    const itemsPayload = expenseItems.map((item) => ({
      expense_id: expenseId,
      expense_type: item.expenseType,
      amount: toNumber(item.amount),
      payment_method: item.paymentMethod,
      remarks: item.remarks.trim(),
      receipt_url: item.receiptUrl,
      receipt_name: item.receiptName,
    }));

    const { data, error } = await supabase
      .from("expense_items")
      .insert(itemsPayload)
      .select("*");

    if (error) throw new Error(error.message);

    const insertedItems = (data ?? []) as ExpenseItemRecord[];

    for (let index = 0; index < insertedItems.length; index += 1) {
      const insertedItem = insertedItems[index];
      const sourceItem = expenseItems[index];

      if (!sourceItem) continue;

      const receipt = await uploadReceipt(expenseId, insertedItem.id, sourceItem);

      if (receipt.receiptUrl || receipt.receiptName) {
        const { error: receiptError } = await supabase
          .from("expense_items")
          .update({
            receipt_url: receipt.receiptUrl,
            receipt_name: receipt.receiptName,
          })
          .eq("id", insertedItem.id);

        if (receiptError) throw new Error(receiptError.message);

        insertedItem.receipt_url = receipt.receiptUrl;
        insertedItem.receipt_name = receipt.receiptName;
      }
    }

    await createDieselEntries(expenseId, insertedItems, expenseItems);
  }

  async function handleSaveExpenseVoucher() {
    if (!validateExpenseVoucher()) return;

    setIsSaving(true);

    try {
      if (editingId) {
        const { error } = await supabase
          .from("expenses")
          .update({
            expense_no: expenseNo.trim(),
            expense_date: expenseDate,
            loading_id: Number(loadingId),
            description: description.trim(),
          })
          .eq("id", editingId);

        if (error) throw new Error(error.message);

        await deleteDieselCashbookEntries(editingId);

        const { error: deleteItemsError } = await supabase
          .from("expense_items")
          .delete()
          .eq("expense_id", editingId);

        if (deleteItemsError) throw new Error(deleteItemsError.message);

        await insertExpenseItemsWithReceipts(editingId);

        alert("Expense voucher updated successfully!");
        resetForm();
        await loadExpenseVouchers();
        return;
      }

      const { data, error } = await supabase
        .from("expenses")
        .insert({
          expense_no: expenseNo.trim(),
          expense_date: expenseDate,
          loading_id: Number(loadingId),
          description: description.trim(),
        })
        .select("id")
        .single();

      if (error) throw new Error(error.message);

      const expenseId = Number(data.id);
      await insertExpenseItemsWithReceipts(expenseId);

      alert("Expense voucher saved successfully!");
      resetForm();
      await loadExpenseVouchers();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to save expense voucher.";
      alert(message);
    } finally {
      setIsSaving(false);

      setExpenseItems((previous) =>
        previous.map((item) => ({
          ...item,
          receiptStatus: "idle",
        }))
      );
    }
  }

  function handleEditExpenseVoucher(voucher: ExpenseVoucher) {
    setEditingId(voucher.id);
    setExpenseNo(voucher.expense_no ?? "");
    setExpenseDate(voucher.expense_date ?? "");
    setLoadingId(String(voucher.loading_id ?? ""));
    setDescription(voucher.description ?? "");

    const dieselByItemId = new Map<number, DieselEntryRecord>();
    (voucher.diesel_entries ?? []).forEach((diesel) => {
      dieselByItemId.set(diesel.expense_item_id, diesel);
    });

    const mappedItems =
      voucher.expense_items?.map((item) => {
        const diesel = dieselByItemId.get(item.id);

        const row: ExpenseItemRow = {
          rowId: nextExpenseItemRowId,
          dbId: item.id,
          expenseType: item.expense_type ?? "",
          amount: String(item.amount ?? ""),
          paymentMethod: item.payment_method ?? "Cash",
          remarks: item.remarks ?? "",
          receiptUrl: item.receipt_url,
          receiptName: item.receipt_name,
          receiptFile: null,
          receiptStatus: "idle",
          receiptError: "",
          petrolPumpId: diesel?.petrol_pump_id ?? "",
          liters: diesel ? String(diesel.liters ?? "") : "",
          rate: diesel ? String(diesel.rate ?? "") : "",
          paidAmount: diesel ? String(diesel.paid_amount ?? "") : "",
          slipNo: diesel?.slip_no ?? "",
        };

        nextExpenseItemRowId += 1;
        return row;
      }) ?? [];

    setExpenseItems(mappedItems.length > 0 ? mappedItems : [createEmptyExpenseItem()]);
  }

  async function handleDeleteExpenseVoucher(voucher: ExpenseVoucher) {
    const confirmed = window.confirm(
      `Delete expense voucher ${voucher.expense_no}?`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    try {
      for (const item of voucher.expense_items ?? []) {
        if (item.receipt_url) {
          const path = getReceiptPath(item.receipt_url);

          if (path) {
            await supabase.storage.from("expense-receipts").remove([path]);
          }
        }
      }

      await deleteDieselCashbookEntries(voucher.id);

      const { error: itemDeleteError } = await supabase
        .from("expense_items")
        .delete()
        .eq("expense_id", voucher.id);

      if (itemDeleteError) throw new Error(itemDeleteError.message);

      const { error } = await supabase
        .from("expenses")
        .delete()
        .eq("id", voucher.id);

      if (error) throw new Error(error.message);

      if (editingId === voucher.id) resetForm();
      if (viewingExpense?.id === voucher.id) setViewingExpense(null);

      alert("Expense voucher deleted successfully!");
      await loadExpenseVouchers();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to delete expense voucher.";
      alert(message);
    } finally {
      setIsDeleting(false);
    }
  }

  function handlePrintExpenseVoucher(voucher: ExpenseVoucher) {
    const printWindow = window.open("", "_blank", "width=1100,height=800");

    if (!printWindow) {
      alert("Please allow popups to print expense voucher.");
      return;
    }

    const dieselByItemId = new Map<number, DieselEntryRecord>();
    (voucher.diesel_entries ?? []).forEach((diesel) => {
      dieselByItemId.set(diesel.expense_item_id, diesel);
    });

    const totalAmount = (voucher.expense_items ?? []).reduce(
      (total, item) => total + toNumber(item.amount),
      0
    );

    const itemRows =
      voucher.expense_items && voucher.expense_items.length > 0
        ? voucher.expense_items
            .map((item, index) => {
              const diesel = dieselByItemId.get(item.id);
              const dieselDetails = diesel
                ? `
                  <div class="diesel">
                    <strong>Petrol Pump:</strong> ${
                      diesel.petrol_pumps?.pump_name ?? "-"
                    } |
                    <strong>Litres:</strong> ${diesel.liters} |
                    <strong>Rate:</strong> ${diesel.rate} |
                    <strong>Total:</strong> ${diesel.total_amount} |
                    <strong>Paid:</strong> ${diesel.paid_amount} |
                    <strong>Remaining:</strong> ${diesel.remaining_amount} |
                    <strong>Status:</strong> ${diesel.payment_status} |
                    <strong>Slip No:</strong> ${diesel.slip_no ?? "-"}
                  </div>
                `
                : "";

              return `
                <tr>
                  <td>${index + 1}</td>
                  <td>${item.expense_type}</td>
                  <td>${Number(item.amount || 0).toLocaleString()}</td>
                  <td>${item.payment_method}</td>
                  <td>${item.remarks ?? "-"}${dieselDetails}</td>
                  <td>${item.receipt_name ?? "-"}</td>
                </tr>
              `;
            })
            .join("")
        : `<tr><td colspan="6" class="empty">No expense items found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Expense Voucher - ${voucher.expense_no}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 28px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .voucher {
              max-width: 1000px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 24px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 16px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            .meta { text-align: right; line-height: 1.7; font-size: 14px; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 10px 24px;
              margin-bottom: 20px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 9px;
              border: 1px solid #2563eb;
            }
            td {
              padding: 9px;
              border: 1px solid #d1d5db;
              vertical-align: top;
            }
            tfoot td {
              font-weight: 800;
              background: #f9fafb;
            }
            .diesel {
              margin-top: 6px;
              line-height: 1.6;
              font-size: 12px;
            }
            .empty {
              text-align: center;
              font-weight: 700;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 24px;
              margin-top: 48px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
          </style>
        </head>
        <body>
          <div class="voucher">
            <div class="header">
              <div>
                <h1>UT Software</h1>
                <div>Expense Voucher</div>
              </div>
              <div class="meta">
                <div><strong>Voucher:</strong> ${voucher.expense_no}</div>
                <div><strong>Date:</strong> ${voucher.expense_date}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Loading:</strong> ${voucher.loadings?.loading_no ?? "-"}</div>
              <div><strong>Vehicle:</strong> ${voucher.loadings?.vehicles?.vehicle_no ?? "-"}</div>
              <div><strong>Driver:</strong> ${voucher.loadings?.drivers?.name ?? "-"}</div>
              <div><strong>Route:</strong> ${voucher.loadings?.route ?? "-"}</div>
              <div><strong>Description:</strong> ${voucher.description ?? "-"}</div>
              <div><strong>Total:</strong> Rs. ${totalAmount.toLocaleString()}</div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Expense Type</th>
                  <th>Amount</th>
                  <th>Payment</th>
                  <th>Remarks / Diesel Details</th>
                  <th>Receipt</th>
                </tr>
              </thead>
              <tbody>${itemRows}</tbody>
              <tfoot>
                <tr>
                  <td colspan="2">Grand Total</td>
                  <td colspan="4">Rs. ${totalAmount.toLocaleString()}</td>
                </tr>
              </tfoot>
            </table>

            <div class="signatures">
              <div class="signature">Prepared By</div>
              <div class="signature">Approved By</div>
              <div class="signature">Received By</div>
            </div>
          </div>

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <div className="mx-auto max-w-7xl space-y-8">
      <div>
        <h1 className="text-4xl font-bold text-gray-900">Expense Voucher</h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Create expense vouchers, upload receipts, record diesel fuel and sync
          paid diesel amounts with Cashbook.
        </p>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <ExpenseFormComponent
          expenseNo={expenseNo}
          setExpenseNo={setExpenseNo}
          expenseDate={expenseDate}
          setExpenseDate={setExpenseDate}
          loadingId={loadingId}
          setLoadingId={setLoadingId}
          description={description}
          setDescription={setDescription}
          loadings={loadings}
          selectedLoading={selectedLoading}
          onSave={handleSaveExpenseVoucher}
          isSaving={isSaving}
          isEditing={Boolean(editingId)}
          onCancelEdit={resetForm}
        />

        <ExpenseItems
          expenseItems={expenseItems}
          grandTotal={grandTotal}
          petrolPumps={petrolPumps}
          onAddExpenseItem={handleAddExpenseItem}
          onDeleteExpenseItem={handleDeleteExpenseItem}
          onExpenseItemChange={onExpenseItemChange}
          onReceiptSelected={handleReceiptSelected}
          onReceiptDelete={handleReceiptDelete}
          onPreviewReceipt={handlePreviewReceipt}
          onSave={handleSaveExpenseVoucher}
          isSaving={isSaving}
        />
      </div>

      <ExpenseTable
        expenseVouchers={filteredExpenseVouchers}
        search={search}
        setSearch={setSearch}
        viewingExpense={viewingExpense}
        onCloseView={() => setViewingExpense(null)}
        onView={setViewingExpense}
        onEdit={handleEditExpenseVoucher}
        onDelete={handleDeleteExpenseVoucher}
        onPrint={handlePrintExpenseVoucher}
        onPreviewReceipt={handlePreviewReceipt}
        isDeleting={isDeleting}
      />
    </div>
  );
}