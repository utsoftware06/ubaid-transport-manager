"use client";

import { useEffect, useMemo, useState } from "react";
import ExpenseForm from "@/components/expenses/ExpenseForm";
import ExpenseItems, {
  type ExpenseItemRow,
} from "@/components/expenses/ExpenseItems";
import ExpenseTable from "@/components/expenses/ExpenseTable";
import { supabase } from "@/lib/supabase/client";

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicles?: {
    vehicle_no: string;
  } | null;
  drivers?: {
    name: string;
  } | null;
};

type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
  amount: number;
  payment_method: string;
  remarks: string | null;
  receipt_url: string | null;
  receipt_name: string | null;
};

type ExpenseVoucherRecord = {
  id: number;
  expense_no: string;
  expense_date: string;
  loading_id: number | string;
  description: string | null;
  created_at?: string;
  loadings?: LoadingRecord | null;
  expense_items?: ExpenseItemRecord[];
};

type PreviewReceipt = {
  url: string;
  name: string;
};

const RECEIPT_BUCKET = "expense-receipts";
const MAX_RECEIPT_SIZE = 5 * 1024 * 1024;
const ALLOWED_RECEIPT_EXTENSIONS = ["jpg", "jpeg", "png", "webp", "pdf"];
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp"];

function createEmptyExpenseItem(): ExpenseItemRow {
  return {
    rowId: Date.now() + Math.floor(Math.random() * 100000),
    expenseType: "",
    amount: "",
    paymentMethod: "",
    remarks: "",
    receiptUrl: null,
    receiptName: null,
    receiptFile: null,
    receiptStatus: "idle",
    receiptError: "",
  };
}

function getFileExtension(fileName: string) {
  return fileName.split(".").pop()?.toLowerCase() ?? "";
}

function isImageReceipt(fileName: string) {
  return IMAGE_EXTENSIONS.includes(getFileExtension(fileName));
}

function getStoragePathFromPublicUrl(url: string) {
  const marker = `/${RECEIPT_BUCKET}/`;
  const [, path] = url.split(marker);

  if (!path) return "";

  return decodeURIComponent(path.split("?")[0]);
}

export default function ExpensesPage() {
  const [expenseNo, setExpenseNo] = useState("");
  const [expenseDate, setExpenseDate] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [description, setDescription] = useState("");

  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [expenseVouchers, setExpenseVouchers] = useState<
    ExpenseVoucherRecord[]
  >([]);
  const [expenseItems, setExpenseItems] = useState<ExpenseItemRow[]>([
    createEmptyExpenseItem(),
  ]);

  const [search, setSearch] = useState("");
  const [editingExpenseId, setEditingExpenseId] = useState<number | null>(null);
  const [viewingExpense, setViewingExpense] =
    useState<ExpenseVoucherRecord | null>(null);
  const [previewReceipt, setPreviewReceipt] = useState<PreviewReceipt | null>(
    null
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const selectedLoading = useMemo(() => {
    if (!loadingId) return null;
    return loadings.find((loading) => String(loading.id) === loadingId) ?? null;
  }, [loadingId, loadings]);

  const grandTotal = useMemo(() => {
    return expenseItems.reduce(
      (total, item) => total + Number(item.amount || 0),
      0
    );
  }, [expenseItems]);

  const filteredExpenseVouchers = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return expenseVouchers;

    return expenseVouchers.filter((voucher) => {
      const loading = voucher.loadings;

      const searchableText = [
        voucher.expense_no,
        loading?.loading_no,
        loading?.vehicles?.vehicle_no,
        loading?.drivers?.name,
        loading?.route,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [expenseVouchers, search]);

  useEffect(() => {
    loadLoadings();
    loadExpenseVouchers();
  }, []);

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

    if (data) {
      setLoadings(data as LoadingRecord[]);
    }
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

    if (data) {
      setExpenseVouchers(data as ExpenseVoucherRecord[]);
    }
  }

  function setReceiptState(
    rowId: number,
    values: Partial<
      Pick<
        ExpenseItemRow,
        | "receiptUrl"
        | "receiptName"
        | "receiptFile"
        | "receiptStatus"
        | "receiptError"
      >
    >
  ) {
    setExpenseItems((currentItems) =>
      currentItems.map((item) =>
        item.rowId === rowId
          ? {
              ...item,
              ...values,
            }
          : item
      )
    );
  }

  function validateReceiptFile(file: File) {
    const extension = getFileExtension(file.name);

    if (!ALLOWED_RECEIPT_EXTENSIONS.includes(extension)) {
      return "Only JPG, JPEG, PNG, WEBP and PDF files are allowed.";
    }

    if (file.size > MAX_RECEIPT_SIZE) {
      return "Receipt file size must be 5 MB or less.";
    }

    return "";
  }

  function createReceiptFileName(file: File) {
    const extension = getFileExtension(file.name);
    return `expense-${Date.now()}-${Math.floor(
      Math.random() * 100000
    )}.${extension}`;
  }

  async function removeReceiptFromStorage(receiptUrl: string) {
    const storagePath = getStoragePathFromPublicUrl(receiptUrl);

    if (!storagePath) {
      return {
        ok: false,
        message: "Receipt storage path could not be resolved.",
      };
    }

    const { error } = await supabase.storage
      .from(RECEIPT_BUCKET)
      .remove([storagePath]);

    if (error) {
      return {
        ok: false,
        message: error.message,
      };
    }

    return {
      ok: true,
      message: "",
    };
  }

  async function uploadReceiptFile(file: File) {
    const fileName = createReceiptFileName(file);

    const { error: uploadError } = await supabase.storage
      .from(RECEIPT_BUCKET)
      .upload(fileName, file, {
        cacheControl: "3600",
        upsert: false,
      });

    if (uploadError) {
      return {
        ok: false,
        url: "",
        name: "",
        message: uploadError.message,
      };
    }

    const { data } = supabase.storage
      .from(RECEIPT_BUCKET)
      .getPublicUrl(fileName);

    if (!data.publicUrl) {
      return {
        ok: false,
        url: "",
        name: "",
        message: "Receipt uploaded but public URL was not generated.",
      };
    }

    return {
      ok: true,
      url: data.publicUrl,
      name: fileName,
      message: "",
    };
  }

  async function handleReceiptSelected(rowId: number, file: File) {
    const validationMessage = validateReceiptFile(file);

    if (validationMessage) {
      setReceiptState(rowId, {
        receiptError: validationMessage,
      });
      alert(validationMessage);
      return;
    }

    const row = expenseItems.find((item) => item.rowId === rowId);

    if (!row) return;

    if (!row.dbId) {
      setReceiptState(rowId, {
        receiptFile: file,
        receiptUrl: null,
        receiptName: null,
        receiptError: "",
      });
      return;
    }

    setReceiptState(rowId, {
      receiptStatus: row.receiptUrl ? "replacing" : "uploading",
      receiptError: "",
    });

    if (row.receiptUrl) {
      const removed = await removeReceiptFromStorage(row.receiptUrl);

      if (!removed.ok) {
        setReceiptState(rowId, {
          receiptStatus: "idle",
          receiptError: removed.message,
        });
        alert(removed.message);
        return;
      }
    }

    const uploaded = await uploadReceiptFile(file);

    if (!uploaded.ok) {
      setReceiptState(rowId, {
        receiptStatus: "idle",
        receiptError: uploaded.message,
      });
      alert(uploaded.message);
      return;
    }

    const { error } = await supabase
      .from("expense_items")
      .update({
        receipt_url: uploaded.url,
        receipt_name: uploaded.name,
      })
      .eq("id", row.dbId);

    if (error) {
      await removeReceiptFromStorage(uploaded.url);

      setReceiptState(rowId, {
        receiptStatus: "idle",
        receiptError: error.message,
      });
      alert(error.message);
      return;
    }

    setReceiptState(rowId, {
      receiptUrl: uploaded.url,
      receiptName: uploaded.name,
      receiptFile: null,
      receiptStatus: "idle",
      receiptError: "",
    });

    await loadExpenseVouchers();
  }

  async function handleReceiptDelete(rowId: number) {
    const row = expenseItems.find((item) => item.rowId === rowId);

    if (!row) return;

    if (!row.receiptUrl) {
      setReceiptState(rowId, {
        receiptFile: null,
        receiptUrl: null,
        receiptName: null,
        receiptError: "",
      });
      return;
    }

    const confirmed = window.confirm(`Delete receipt ${row.receiptName}?`);

    if (!confirmed) return;

    setReceiptState(rowId, {
      receiptStatus: "deleting",
      receiptError: "",
    });

    const removed = await removeReceiptFromStorage(row.receiptUrl);

    if (!removed.ok) {
      setReceiptState(rowId, {
        receiptStatus: "idle",
        receiptError: removed.message,
      });
      alert(removed.message);
      return;
    }

    if (row.dbId) {
      const { error } = await supabase
        .from("expense_items")
        .update({
          receipt_url: null,
          receipt_name: null,
        })
        .eq("id", row.dbId);

      if (error) {
        setReceiptState(rowId, {
          receiptStatus: "idle",
          receiptError: error.message,
        });
        alert(error.message);
        return;
      }
    }

    setReceiptState(rowId, {
      receiptUrl: null,
      receiptName: null,
      receiptFile: null,
      receiptStatus: "idle",
      receiptError: "",
    });

    await loadExpenseVouchers();
  }

  function handlePreviewReceipt(url: string, name: string) {
    if (isImageReceipt(name)) {
      setPreviewReceipt({
        url,
        name,
      });
      return;
    }

    window.open(url, "_blank", "noopener,noreferrer");
  }

  function handleAddExpenseItem() {
    setExpenseItems((currentItems) => [...currentItems, createEmptyExpenseItem()]);
  }

  async function handleDeleteExpenseItem(rowId: number) {
    const row = expenseItems.find((item) => item.rowId === rowId);

    if (!row) return;

    if (expenseItems.length === 1) return;

    if (row.receiptUrl) {
      const removed = await removeReceiptFromStorage(row.receiptUrl);

      if (!removed.ok) {
        setReceiptState(rowId, {
          receiptError: removed.message,
        });
        alert(removed.message);
        return;
      }
    }

    if (row.dbId) {
      const { error } = await supabase
        .from("expense_items")
        .delete()
        .eq("id", row.dbId);

      if (error) {
        setReceiptState(rowId, {
          receiptError: error.message,
        });
        alert(error.message);
        return;
      }
    }

    setExpenseItems((currentItems) =>
      currentItems.filter((item) => item.rowId !== rowId)
    );

    await loadExpenseVouchers();
  }

  function handleExpenseItemChange(
    rowId: number,
    field: keyof Pick<
      ExpenseItemRow,
      "expenseType" | "amount" | "paymentMethod" | "remarks"
    >,
    value: string
  ) {
    setExpenseItems((currentItems) =>
      currentItems.map((item) =>
        item.rowId === rowId
          ? {
              ...item,
              [field]: value,
            }
          : item
      )
    );
  }

  function resetForm() {
    setExpenseNo("");
    setExpenseDate("");
    setLoadingId("");
    setDescription("");
    setEditingExpenseId(null);
    setExpenseItems([createEmptyExpenseItem()]);
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
      alert("At least one Expense Item is required.");
      return false;
    }

    for (const item of expenseItems) {
      if (!item.expenseType) {
        alert("Expense Type is required for every row.");
        return false;
      }

      if (!item.amount || Number(item.amount) <= 0) {
        alert("Amount must be greater than zero for every row.");
        return false;
      }

      if (!item.paymentMethod) {
        alert("Payment Method is required for every row.");
        return false;
      }

      if (item.receiptFile) {
        const receiptValidation = validateReceiptFile(item.receiptFile);

        if (receiptValidation) {
          alert(receiptValidation);
          return false;
        }
      }
    }

    return true;
  }

  async function insertExpenseItemsWithReceipts(expenseId: number) {
    const itemsToInsert = expenseItems.map((item) => ({
      expense_id: expenseId,
      expense_type: item.expenseType,
      amount: Number(item.amount),
      payment_method: item.paymentMethod,
      remarks: item.remarks.trim(),
      receipt_url: item.receiptUrl,
      receipt_name: item.receiptName,
    }));

    const { data, error } = await supabase
      .from("expense_items")
      .insert(itemsToInsert)
      .select();

    if (error) {
      alert(error.message);
      return false;
    }

    const insertedItems = (data ?? []) as ExpenseItemRecord[];

    for (let index = 0; index < expenseItems.length; index += 1) {
      const sourceRow = expenseItems[index];
      const insertedRow = insertedItems[index];

      if (!sourceRow.receiptFile || !insertedRow) continue;

      setReceiptState(sourceRow.rowId, {
        receiptStatus: "uploading",
        receiptError: "",
      });

      const uploaded = await uploadReceiptFile(sourceRow.receiptFile);

      if (!uploaded.ok) {
        setReceiptState(sourceRow.rowId, {
          receiptStatus: "idle",
          receiptError: uploaded.message,
        });
        alert(uploaded.message);
        return false;
      }

      const { error: updateError } = await supabase
        .from("expense_items")
        .update({
          receipt_url: uploaded.url,
          receipt_name: uploaded.name,
        })
        .eq("id", insertedRow.id);

      if (updateError) {
        await removeReceiptFromStorage(uploaded.url);

        setReceiptState(sourceRow.rowId, {
          receiptStatus: "idle",
          receiptError: updateError.message,
        });
        alert(updateError.message);
        return false;
      }

      setReceiptState(sourceRow.rowId, {
        dbId: insertedRow.id,
        receiptUrl: uploaded.url,
        receiptName: uploaded.name,
        receiptFile: null,
        receiptStatus: "idle",
        receiptError: "",
      });
    }

    return true;
  }

  async function handleSaveExpenseVoucher() {
    if (!validateExpenseVoucher()) return;

    setIsSaving(true);

    if (editingExpenseId) {
      const oldVoucher = expenseVouchers.find(
        (voucher) => voucher.id === editingExpenseId
      );

      const oldReceiptUrls = oldVoucher?.expense_items
        ?.map((item) => item.receipt_url)
        .filter((url): url is string => Boolean(url));

      const activeReceiptUrls = expenseItems
        .map((item) => item.receiptUrl)
        .filter((url): url is string => Boolean(url));

      const receiptsToDelete =
        oldReceiptUrls?.filter((url) => !activeReceiptUrls.includes(url)) ?? [];

      const { error: updateError } = await supabase
        .from("expenses")
        .update({
          expense_no: expenseNo.trim(),
          expense_date: expenseDate,
          loading_id: loadingId,
          description: description.trim(),
        })
        .eq("id", editingExpenseId);

      if (updateError) {
        setIsSaving(false);
        alert(updateError.message);
        return;
      }

      const { error: deleteItemsError } = await supabase
        .from("expense_items")
        .delete()
        .eq("expense_id", editingExpenseId);

      if (deleteItemsError) {
        setIsSaving(false);
        alert(deleteItemsError.message);
        return;
      }

      const itemsSaved = await insertExpenseItemsWithReceipts(editingExpenseId);

      if (!itemsSaved) {
        setIsSaving(false);
        return;
      }

      for (const receiptUrl of receiptsToDelete) {
        await removeReceiptFromStorage(receiptUrl);
      }

      setIsSaving(false);
      alert("Expense Voucher updated successfully!");
      await loadExpenseVouchers();
      resetForm();
      return;
    }

    const { data: expenseData, error: expenseError } = await supabase
      .from("expenses")
      .insert({
        expense_no: expenseNo.trim(),
        expense_date: expenseDate,
        loading_id: loadingId,
        description: description.trim(),
      })
      .select();

    if (expenseError) {
      setIsSaving(false);
      alert(expenseError.message);
      return;
    }

    if (!expenseData || expenseData.length === 0) {
      setIsSaving(false);
      alert("Expense Voucher was not saved.");
      return;
    }

    const expenseId = expenseData[0].id as number;
    const itemsSaved = await insertExpenseItemsWithReceipts(expenseId);

    setIsSaving(false);

    if (!itemsSaved) return;

    alert("Expense Voucher saved successfully!");
    await loadExpenseVouchers();
    resetForm();
  }

  function handleViewExpenseVoucher(voucher: ExpenseVoucherRecord) {
    setViewingExpense(voucher);
  }

  function handleEditExpenseVoucher(voucher: ExpenseVoucherRecord) {
    setEditingExpenseId(voucher.id);
    setExpenseNo(voucher.expense_no ?? "");
    setExpenseDate(voucher.expense_date ?? "");
    setLoadingId(String(voucher.loading_id ?? ""));
    setDescription(voucher.description ?? "");

    const rows =
      voucher.expense_items && voucher.expense_items.length > 0
        ? voucher.expense_items.map((item) => ({
            rowId: item.id,
            dbId: item.id,
            expenseType: item.expense_type ?? "",
            amount: String(item.amount ?? ""),
            paymentMethod: item.payment_method ?? "",
            remarks: item.remarks ?? "",
            receiptUrl: item.receipt_url ?? null,
            receiptName: item.receipt_name ?? null,
            receiptFile: null,
            receiptStatus: "idle" as const,
            receiptError: "",
          }))
        : [createEmptyExpenseItem()];

    setExpenseItems(rows);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function handleDeleteExpenseVoucher(voucher: ExpenseVoucherRecord) {
    const confirmed = window.confirm(
      `Delete Expense Voucher ${voucher.expense_no}? This will also delete all expense items and receipts.`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    for (const item of voucher.expense_items ?? []) {
      if (item.receipt_url) {
        const removed = await removeReceiptFromStorage(item.receipt_url);

        if (!removed.ok) {
          setIsDeleting(false);
          alert(removed.message);
          return;
        }
      }
    }

    const { error: itemsError } = await supabase
      .from("expense_items")
      .delete()
      .eq("expense_id", voucher.id);

    if (itemsError) {
      setIsDeleting(false);
      alert(itemsError.message);
      return;
    }

    const { error: voucherError } = await supabase
      .from("expenses")
      .delete()
      .eq("id", voucher.id);

    setIsDeleting(false);

    if (voucherError) {
      alert(voucherError.message);
      return;
    }

    if (editingExpenseId === voucher.id) {
      resetForm();
    }

    if (viewingExpense?.id === voucher.id) {
      setViewingExpense(null);
    }

    alert("Expense Voucher deleted successfully!");
    await loadExpenseVouchers();
  }

  function handlePrintExpenseVoucher(voucher: ExpenseVoucherRecord) {
    const printWindow = window.open("", "_blank", "width=950,height=720");

    if (!printWindow) {
      alert("Please allow popups to print the expense voucher.");
      return;
    }

    const items = voucher.expense_items ?? [];
    const grandTotal = items.reduce(
      (total, item) => total + Number(item.amount || 0),
      0
    );

    const itemRows =
      items.length > 0
        ? items
            .map(
              (item, index) => `
                <tr>
                  <td>${index + 1}</td>
                  <td>${item.expense_type ?? ""}</td>
                  <td>${Number(item.amount || 0).toLocaleString()}</td>
                  <td>${item.payment_method ?? ""}</td>
                 <td>
${
  item.receipt_url
    ? (
        item.receipt_name?.toLowerCase().endsWith(".pdf")
          ? `<a href="${item.receipt_url}" target="_blank">View PDF</a>`
          : `<img
               src="${item.receipt_url}"
               alt="${item.receipt_name ?? "Receipt"}"
               style="
                 width:90px;
                 height:90px;
                 object-fit:contain;
                 border:1px solid #d1d5db;
                 border-radius:6px;
                 padding:4px;
               "
             />`
      )
    : "-"
}
</td>
                  <td>${item.remarks ?? ""}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="6" class="empty">No expense items found</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Expense Voucher - ${voucher.expense_no}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .voucher {
              max-width: 950px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 18px;
              margin-bottom: 22px;
            }
            h1 {
              margin: 0;
              font-size: 28px;
              color: #111827;
            }
            .subtitle {
              margin-top: 6px;
              font-size: 14px;
              color: #111827;
            }
            .meta {
              text-align: right;
              font-size: 14px;
              line-height: 1.7;
              color: #111827;
            }
            .details {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 12px 24px;
              margin-bottom: 24px;
              font-size: 15px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 14px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 10px;
              border: 1px solid #2563eb;
            }
            td {
              padding: 10px;
              border: 1px solid #d1d5db;
              color: #111827;
            }
            a {
              color: #2563eb;
              font-weight: 700;
              text-decoration: none;
            }
            tfoot td {
              font-weight: 700;
              background: #f9fafb;
            }
            .empty {
              text-align: center;
              font-weight: 700;
            }
            .description {
              margin: 20px 0;
              min-height: 70px;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 14px;
              font-size: 15px;
              color: #111827;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 24px;
              margin-top: 52px;
              font-size: 14px;
              color: #111827;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
            @media print {
              body { padding: 0; }
              .voucher {
                border: none;
                border-radius: 0;
              }
            }
          </style>
        </head>
        <body>
          <div class="voucher">
            <div class="header">
              <div>
                <h1>Company Header</h1>
                <div class="subtitle">Professional Expense Voucher</div>
              </div>
              <div class="meta">
                <div><strong>Voucher No:</strong> ${voucher.expense_no}</div>
                <div><strong>Date:</strong> ${voucher.expense_date}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Loading Number:</strong> ${
                voucher.loadings?.loading_no ?? "-"
              }</div>
              <div><strong>Vehicle:</strong> ${
                voucher.loadings?.vehicles?.vehicle_no ?? "-"
              }</div>
              <div><strong>Driver:</strong> ${
                voucher.loadings?.drivers?.name ?? "-"
              }</div>
              <div><strong>Route:</strong> ${
                voucher.loadings?.route ?? "-"
              }</div>
              <div><strong>Loading Date:</strong> ${
                voucher.loadings?.loading_date ?? "-"
              }</div>
              <div><strong>Total Items:</strong> ${items.length}</div>
            </div>

            <strong>Description</strong>
            <div class="description">${voucher.description || "-"}</div>

            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Expense Type</th>
                  <th>Amount</th>
                  <th>Payment Method</th>
                  <th>Receipt</th>
                  <th>Remarks</th>
                </tr>
              </thead>
              <tbody>${itemRows}</tbody>
              <tfoot>
                <tr>
                  <td colspan="2">Grand Total</td>
                  <td>${grandTotal.toLocaleString()}</td>
                  <td colspan="3"></td>
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
        <h1 className="text-4xl font-bold text-gray-900">
          Expense Voucher Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Create expense vouchers against loadings and manage receipts for each
          expense item.
        </p>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <ExpenseForm
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
        />

        <ExpenseItems
          expenseItems={expenseItems}
          grandTotal={grandTotal}
          onAddExpenseItem={handleAddExpenseItem}
          onDeleteExpenseItem={handleDeleteExpenseItem}
          onExpenseItemChange={handleExpenseItemChange}
          onReceiptSelected={handleReceiptSelected}
          onReceiptDelete={handleReceiptDelete}
          onPreviewReceipt={handlePreviewReceipt}
          onSave={handleSaveExpenseVoucher}
          isSaving={isSaving}
        />

        {editingExpenseId && (
          <div className="mt-6">
            <button
              type="button"
              onClick={resetForm}
              className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
            >
              Cancel Edit
            </button>
          </div>
        )}
      </div>

      <ExpenseTable
        expenseVouchers={filteredExpenseVouchers}
        search={search}
        setSearch={setSearch}
        viewingExpense={viewingExpense}
        onCloseView={() => setViewingExpense(null)}
        onView={handleViewExpenseVoucher}
        onEdit={handleEditExpenseVoucher}
        onDelete={handleDeleteExpenseVoucher}
        onPrint={handlePrintExpenseVoucher}
        onPreviewReceipt={handlePreviewReceipt}
        isDeleting={isDeleting}
      />

      {previewReceipt && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4">
          <div className="w-full max-w-5xl rounded-xl bg-white p-4 shadow-xl">
            <div className="mb-4 flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
              <h2 className="break-all text-xl font-bold text-gray-900">
                {previewReceipt.name}
              </h2>

              <button
                type="button"
                onClick={() => setPreviewReceipt(null)}
                className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
              >
                Close
              </button>
            </div>

            <div className="max-h-[75vh] overflow-auto rounded-lg border border-gray-200 bg-gray-50 p-3">
              <img
                src={previewReceipt.url}
                alt={previewReceipt.name}
                className="mx-auto h-auto max-h-[70vh] max-w-full rounded-lg object-contain"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}