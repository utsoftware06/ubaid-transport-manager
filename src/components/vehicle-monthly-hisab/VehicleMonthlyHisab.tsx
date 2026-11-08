"use client";

import Link from "next/link";
import {
  CalendarDays,
  CircleDollarSign,
  ClipboardList,
  Printer,
  RotateCcw,
  Search,
  Trash2,
  TrendingDown,
  TrendingUp,
  Truck,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { supabase } from "@/lib/supabase/client";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { bilingual, printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type VehicleOption = {
  id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

type MonthlySummary = {
  total_chakkar: number;
  total_vehicle_freight: number;
  total_regular_trip_expenses: number;
  total_vehicle_periodic_expenses: number;
  total_expenses: number;
  vehicle_monthly_profit: number;
  total_manual_chakkar_freight_adjustments?: number;
  total_manual_chakkar_expense_adjustments?: number;
  total_manual_chakkar_adjustments?: number;
  manual_chakkar_adjustment_count?: number;
};

type ExpenseBreakdown = {
  status: "RECONCILED" | "SNAPSHOT_MISMATCH";
  unreconciled_chakkar_count: number;
  regular_trip_expenses: number;
  vehicle_periodic_expenses: number;
  diesel: number | null;
  workshop: number | null;
  tyre: number | null;
  oil: number | null;
  driver: number | null;
  other: number | null;
  unallocated_vehicle_expenses: number | null;
  unallocated_status: "NOT_SNAPSHOTTED";
  manual_chakkar_freight_adjustments?: number;
  manual_chakkar_expense_adjustments?: number;
  manual_chakkar_net_adjustments?: number;
};

type ChakkarRow = {
  settlement_id: string;
  source_type?: "bilty" | "manual";
  voucher_type?: string;
  manual_settlement_id?: string | null;
  movement_group_id: string | null;
  movement_group_status: string;
  chakkar_date: string;
  return_bilty_id: string | null;
  return_bilty_no: string | null;
  voucher_id: number;
  voucher_no: string | null;
  vehicle_id: string;
  vehicle_no: string | null;
  vehicle_freight: number;
  regular_trip_expenses: number;
  vehicle_periodic_expenses: number;
  total_expenses: number;
  net_vehicle_amount: number;
  original_chakkar_net?: number;
  adjustment_freight_total?: number;
  adjustment_expense_total?: number;
  adjustment_total?: number;
  adjustment_count?: number;
  adjusted_net_vehicle_amount?: number;
  adjusted_vehicle_freight?: number;
  adjusted_total_expenses?: number;
  breakdown_status: "RECONCILED" | "SNAPSHOT_MISMATCH";
  diesel: number | null;
  workshop: number | null;
  tyre: number | null;
  oil: number | null;
  driver: number | null;
  other: number | null;
  accounting_version: number;
  finalized_at: string;
  chakkar_days?: number | null;
};

type MonthlyHisabReport = {
  vehicle: {
    id: string;
    adda_id: string;
    vehicle_no: string | null;
    owner_name: string | null;
    adda_name: string;
  };
  accounting_month: string;
  report_scope?: "MONTH" | "DATE_RANGE";
  date_from?: string | null;
  date_to?: string | null;
  summary: MonthlySummary;
  expense_breakdown: ExpenseBreakdown;
  chakkars: ChakkarRow[];
};

function currentMonthValue() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
}

function monthToDate(month: string) {
  return /^\d{4}-\d{2}$/.test(month) ? `${month}-01` : "";
}

function amount(value: number | null | undefined) {
  if (value === null || value === undefined) return "—";
  return `Rs. ${Number(value).toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })}`;
}

function display(value: string | null | undefined) {
  return value?.trim() || "—";
}

function rowFreight(row: ChakkarRow) {
  return row.source_type === "manual" ? row.adjusted_vehicle_freight ?? row.vehicle_freight : row.vehicle_freight;
}

function rowExpenses(row: ChakkarRow) {
  return row.source_type === "manual" ? row.adjusted_total_expenses ?? row.total_expenses : row.total_expenses;
}

function rowNet(row: ChakkarRow) {
  return row.source_type === "manual" ? row.adjusted_net_vehicle_amount ?? row.net_vehicle_amount : row.net_vehicle_amount;
}

function categoryValue(breakdown: ExpenseBreakdown, value: number | null) {
  return breakdown.status === "RECONCILED"
    ? amount(value)
    : bilingual("Unavailable (snapshot mismatch)", "دستیاب نہیں (اسنیپ شاٹ میں فرق)");
}

export default function VehicleMonthlyHisab() {
  const { t, dir, language } = useLanguage();
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [vehicleId, setVehicleId] = useState("");
  const [month, setMonth] = useState(currentMonthValue);
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [search, setSearch] = useState("");
  const [report, setReport] = useState<MonthlyHisabReport | null>(null);
  const [loadingVehicles, setLoadingVehicles] = useState(true);
  const [loadingReport, setLoadingReport] = useState(false);
  const [reversingSettlementId, setReversingSettlementId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const modulePrint = useModuleTransportPrint("vehicle_monthly_hisab", report?.vehicle.adda_id ?? null, language === "ur" ? "ur" : "en");

  useEffect(() => {
    let active = true;

    async function loadVehicles() {
      setLoadingVehicles(true);
      const result = await supabase
        .from("vehicles")
        .select("id, vehicle_no, owner_name")
        .order("vehicle_no");

      if (!active) return;
      if (result.error) {
        console.error("Vehicle Monthly Hisab vehicle load failed", result.error);
        setError(t("vehicleMonthlyHisab.messages.vehiclesFailed"));
        setVehicles([]);
      } else {
        const rows = (result.data ?? []) as VehicleOption[];
        setVehicles(rows);
        setVehicleId((current) => current || rows[0]?.id || "");
      }
      setLoadingVehicles(false);
    }

    void loadVehicles();
    return () => {
      active = false;
    };
  }, [t]);

  const loadReport = useCallback(async () => {
    const reportDate = monthToDate(month);
    const customRangeActive = Boolean(dateFrom || dateTo);
    if (dateFrom && dateTo && dateFrom > dateTo) {
      setReport(null);
      setLoadingReport(false);
      setError(t("vehicleMonthlyHisab.messages.invalidDateRange"));
      return;
    }
    if (!vehicleId || (!customRangeActive && !reportDate)) {
      setReport(null);
      return;
    }

    setLoadingReport(true);
    setError("");
    const result = await supabase.rpc("get_vehicle_monthly_hisab_v3", {
      p_vehicle_id: vehicleId,
      p_month: reportDate || null,
      p_date_from: dateFrom || null,
      p_date_to: dateTo || null,
    });

    if (result.error) {
      console.error("Vehicle Monthly Hisab RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setReport(null);
      setError(result.error.message || t("vehicleMonthlyHisab.messages.loadFailed"));
    } else {
      setReport(result.data as unknown as MonthlyHisabReport);
    }
    setLoadingReport(false);
  }, [dateFrom, dateTo, month, t, vehicleId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadReport(), 0);
    return () => window.clearTimeout(timer);
  }, [loadReport]);

  const visibleRows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (!needle) return report?.chakkars ?? [];
    return (report?.chakkars ?? []).filter((row) =>
      [
        row.movement_group_id ?? "",
        row.return_bilty_no,
        row.voucher_no,
        row.chakkar_date,
        row.vehicle_no,
      ]
        .join(" ")
        .toLowerCase()
        .includes(needle)
    );
  }, [report, search]);

  const printReportLegacy = () => {
    if (!report) return;
    const popup = window.open("", "_blank", "width=1200,height=850");
    if (!popup) {
      window.alert(t("vehicleMonthlyHisab.messages.allowPopups"));
      return;
    }

    const summary = report.summary;
    const breakdown = report.expense_breakdown;
    const customRangeActive = Boolean(dateFrom || dateTo);
    const reportPeriod = customRangeActive
      ? `${dateFrom || "—"} ${t("vehicleMonthlyHisab.print.to")} ${dateTo || "—"}`
      : month;
    const rowHtml = report.chakkars
      .map(
        (row) => `<tr>
          <td>${escapeHtml(row.chakkar_date)}</td>
          <td>${escapeHtml(row.movement_group_id ?? t("vehicleMonthlyHisab.source.manual"))}</td>
          <td>${escapeHtml(display(row.return_bilty_no))}</td>
          <td>${escapeHtml(display(row.voucher_no))}</td>
          <td class="money">${escapeHtml(amount(rowFreight(row)))}</td>
          <td class="money">${escapeHtml(amount(row.regular_trip_expenses))}</td>
          <td class="money">${escapeHtml(amount(row.vehicle_periodic_expenses))}</td>
          <td class="money">${escapeHtml(amount(rowExpenses(row)))}</td>
          <td class="money">${escapeHtml(row.source_type === "manual" ? amount(row.adjustment_total ?? 0) : "—")}</td>
          <td class="money ${rowNet(row) < 0 ? "loss" : "profit"}">${escapeHtml(amount(rowNet(row)))}</td>
        </tr>`
      )
      .join("");

    const categoryValue = (value: number | null) =>
      breakdown.status === "RECONCILED"
        ? escapeHtml(amount(value))
        : escapeHtml(t("vehicleMonthlyHisab.breakdown.unavailable"));

    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
      <title>${escapeHtml(t("vehicleMonthlyHisab.print.title"))}</title>
      <style>@page{size:A4 landscape;margin:10mm}body{font-family:Arial,sans-serif;color:#0f172a;padding:18px}h1,h2{text-align:center;margin:4px}.meta{text-align:center;margin:12px 0 18px}.cards,.breakdown{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:14px 0}.box{border:1px solid #cbd5e1;border-radius:8px;padding:10px}.box p{font-size:11px;font-weight:700;margin:0}.box strong{display:block;margin-top:5px}.profit{color:#047857}.loss{color:#b91c1c}.money{direction:ltr;unicode-bidi:isolate;text-align:end}table{width:100%;border-collapse:collapse;font-size:10px}th,td{border:1px solid #cbd5e1;padding:6px;text-align:start}th{background:#1d4ed8;color:#fff}</style>
      </head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${escapeHtml(t("vehicleMonthlyHisab.print.title"))}</h2>
      <div class="meta">${escapeHtml(t("common.vehicle"))}: <strong>${escapeHtml(display(report.vehicle.vehicle_no))}</strong> · ${escapeHtml(t("vehicleMonthlyHisab.fields.owner"))}: <strong>${escapeHtml(display(report.vehicle.owner_name))}</strong> · ${escapeHtml(customRangeActive ? t("vehicleMonthlyHisab.print.period") : t("vehicleMonthlyHisab.fields.month"))}: <strong>${escapeHtml(reportPeriod)}</strong></div>
      <div class="cards"><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.cards.totalChakkar"))}</p><strong>${summary.total_chakkar}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.cards.totalFreight"))}</p><strong class="money">${escapeHtml(amount(summary.total_vehicle_freight))}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.cards.totalExpenses"))}</p><strong class="money">${escapeHtml(amount(summary.total_expenses))}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.cards.vehicleProfit"))}</p><strong class="money ${summary.vehicle_monthly_profit < 0 ? "loss" : "profit"}">${escapeHtml(amount(summary.vehicle_monthly_profit))}</strong></div></div>
      <div class="breakdown"><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.regular"))}</p><strong class="money">${escapeHtml(amount(breakdown.regular_trip_expenses))}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.periodic"))}</p><strong class="money">${escapeHtml(amount(breakdown.vehicle_periodic_expenses))}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.diesel"))}</p><strong class="money">${categoryValue(breakdown.diesel)}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.workshop"))}</p><strong class="money">${categoryValue(breakdown.workshop)}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.tyre"))}</p><strong class="money">${categoryValue(breakdown.tyre)}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.oil"))}</p><strong class="money">${categoryValue(breakdown.oil)}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.driver"))}</p><strong class="money">${categoryValue(breakdown.driver)}</strong></div><div class="box"><p>${escapeHtml(t("vehicleMonthlyHisab.breakdown.other"))}</p><strong class="money">${categoryValue(breakdown.other)}</strong></div></div>
      <table><thead><tr><th>${escapeHtml(t("vehicleMonthlyHisab.table.date"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.chakkar"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.returnBilty"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.voucher"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.freight"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.regular"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.periodic"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.totalExpenses"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.adjustment"))}</th><th>${escapeHtml(t("vehicleMonthlyHisab.table.net"))}</th></tr></thead><tbody>${rowHtml}</tbody></table>
      <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}</script></body></html>`, report.vehicle.adda_id, language === "ur" ? "ur" : "en");
  };

  const printChakkarLegacy = (row: ChakkarRow) => {
    if (!report) return;
    const popup = window.open("", "_blank", "width=900,height=800");
    if (!popup) {
      window.alert(t("vehicleMonthlyHisab.messages.allowPopups"));
      return;
    }

    const netTone = rowNet(row) < 0 ? "loss" : "profit";
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
      <title>${escapeHtml(t("vehicleMonthlyHisab.print.chakkarTitle"))}</title>
      <style>@page{size:A4 portrait;margin:14mm}*{box-sizing:border-box}body{font-family:Arial,sans-serif;color:#0f172a;padding:18px}h1,h2{text-align:center;margin:4px}.meta{margin:18px 0;display:grid;grid-template-columns:repeat(2,1fr);gap:10px}.field,.amount{border:1px solid #cbd5e1;border-radius:8px;padding:11px}.field span,.amount span{display:block;font-size:11px;font-weight:700;color:#475569}.field strong,.amount strong{display:block;margin-top:5px;overflow-wrap:anywhere}.amounts{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-top:16px}.amount strong{direction:ltr;unicode-bidi:isolate;text-align:end;font-size:16px}.profit{color:#047857}.loss{color:#b91c1c}.footer{margin-top:24px;border-top:1px solid #cbd5e1;padding-top:10px;font-size:11px;color:#475569}@media print{body{padding:0}}</style>
      </head><body>
      <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
      <h2>${escapeHtml(t("vehicleMonthlyHisab.print.chakkarTitle"))}</h2>
      <div class="meta">
        <div class="field"><span>${escapeHtml(t("common.vehicle"))}</span><strong>${escapeHtml(display(row.vehicle_no))}</strong></div>
        <div class="field"><span>${escapeHtml(row.source_type === "manual" ? t("vehicleMonthlyHisab.source.type") : t("vehicleMonthlyHisab.table.chakkar"))}</span><strong>${escapeHtml(row.movement_group_id ?? t("vehicleMonthlyHisab.source.manual"))}</strong></div>
        <div class="field"><span>${escapeHtml(t("vehicleMonthlyHisab.table.status"))}</span><strong>${escapeHtml(row.source_type === "manual" ? t("expenses.manual.finalized") : row.movement_group_status)}</strong></div>
        <div class="field"><span>${escapeHtml(t("vehicleMonthlyHisab.table.returnBilty"))}</span><strong>${escapeHtml(row.source_type === "manual" ? t("vehicleMonthlyHisab.source.notApplicable") : display(row.return_bilty_no))}</strong></div>
        <div class="field"><span>${escapeHtml(t("vehicleMonthlyHisab.table.voucher"))}</span><strong>${escapeHtml(display(row.voucher_no))}</strong></div>
        <div class="field"><span>${escapeHtml(t("vehicleMonthlyHisab.table.date"))}</span><strong>${escapeHtml(row.chakkar_date)}</strong></div>
        ${row.source_type === "manual" ? `<div class="field"><span>${escapeHtml(t("expenses.manual.chakkarDays"))}</span><strong>${escapeHtml(String(row.chakkar_days ?? "—"))}</strong></div>` : ""}
      </div>
      <div class="amounts">
        <div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.freight"))}</span><strong>${escapeHtml(amount(rowFreight(row)))}</strong></div>
        <div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.regular"))}</span><strong>${escapeHtml(amount(row.regular_trip_expenses))}</strong></div>
        <div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.periodic"))}</span><strong>${escapeHtml(amount(row.vehicle_periodic_expenses))}</strong></div>
        <div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.totalExpenses"))}</span><strong>${escapeHtml(amount(rowExpenses(row)))}</strong></div>
        ${row.source_type === "manual" ? `<div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.adjustment"))}</span><strong>${escapeHtml(amount(row.adjustment_total ?? 0))}</strong></div><div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.originalNet"))}</span><strong>${escapeHtml(amount(row.original_chakkar_net ?? row.net_vehicle_amount))}</strong></div>` : ""}
        <div class="amount"><span>${escapeHtml(t("vehicleMonthlyHisab.table.net"))}</span><strong class="${netTone}">${escapeHtml(amount(rowNet(row)))}</strong></div>
      </div>
      <div class="footer">${escapeHtml(t("vehicleMonthlyHisab.print.snapshotNotice"))} · ${escapeHtml(t("vehicleMonthlyHisab.print.accountingVersion"))}: ${escapeHtml(String(row.accounting_version))}</div>
      <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}</script>
      </body></html>`, report.vehicle.adda_id, language === "ur" ? "ur" : "en");
  };

  const printReport = () => {
    if (!report) return;
    const customRangeActive = Boolean(report.date_from || report.date_to || dateFrom || dateTo);
    const period = customRangeActive
      ? `${report.date_from || dateFrom || "—"} — ${report.date_to || dateTo || "—"}`
      : report.accounting_month;
    const presentation: ModulePrintPresentation = {
      documentType: "vehicle_monthly_hisab",
      title: printLabel("vehicleMonthlyHisab.print.title"),
      documentDate: printValue(period),
      subtitle: printLabel(customRangeActive ? "vehicleMonthlyHisab.print.period" : "vehicleMonthlyHisab.fields.month"),
      fields: [
        { label: printLabel("common.vehicle"), value: printValue(report.vehicle.vehicle_no) },
        { label: printLabel("vehicleMonthlyHisab.fields.owner"), value: printValue(report.vehicle.owner_name) },
        { label: printLabel("vehicleMonthlyHisab.table.status"), value: report.expense_breakdown.status === "RECONCILED" ? bilingual("Reconciled", "مطابقت شدہ") : bilingual("Snapshot mismatch", "اسنیپ شاٹ میں فرق") },
        { label: printLabel("vehicleMonthlyHisab.breakdown.unallocatedGap"), value: printValue(report.expense_breakdown.unreconciled_chakkar_count) },
      ],
      totals: [
        { label: printLabel("vehicleMonthlyHisab.cards.totalChakkar"), value: printValue(report.summary.total_chakkar) },
        { label: printLabel("vehicleMonthlyHisab.cards.totalFreight"), value: amount(report.summary.total_vehicle_freight) },
        { label: printLabel("vehicleMonthlyHisab.cards.totalExpenses"), value: amount(report.summary.total_expenses) },
        { label: printLabel("vehicleMonthlyHisab.cards.vehicleProfit"), value: amount(report.summary.vehicle_monthly_profit) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.regular"), value: amount(report.expense_breakdown.regular_trip_expenses) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.periodic"), value: amount(report.expense_breakdown.vehicle_periodic_expenses) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.diesel"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.diesel) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.workshop"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.workshop) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.tyre"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.tyre) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.oil"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.oil) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.driver"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.driver) },
        { label: printLabel("vehicleMonthlyHisab.breakdown.other"), value: categoryValue(report.expense_breakdown, report.expense_breakdown.other) },
      ],
      tables: [{
        title: printLabel("vehicleMonthlyHisab.table.chakkar"),
        columns: ["vehicleMonthlyHisab.table.date", "vehicleMonthlyHisab.table.chakkar", "vehicleMonthlyHisab.table.returnBilty", "vehicleMonthlyHisab.table.voucher", "vehicleMonthlyHisab.table.freight", "vehicleMonthlyHisab.table.regular", "vehicleMonthlyHisab.table.periodic", "vehicleMonthlyHisab.table.totalExpenses", "vehicleMonthlyHisab.table.adjustment", "vehicleMonthlyHisab.table.net"].map(printLabel),
        rows: report.chakkars.map((row) => [
          printValue(row.chakkar_date), printValue(row.movement_group_id ?? t("vehicleMonthlyHisab.source.manual")), printValue(row.return_bilty_no), printValue(row.voucher_no),
          amount(rowFreight(row)), amount(row.regular_trip_expenses), amount(row.vehicle_periodic_expenses), amount(rowExpenses(row)),
          row.source_type === "manual" ? amount(row.adjustment_total ?? 0) : "—", amount(rowNet(row)),
        ]),
      }],
    };
    modulePrint.openPresentation(presentation, printReportLegacy, report.vehicle.adda_id);
  };

  const printChakkar = (row: ChakkarRow) => {
    if (!report) return;
    const statusKey = row.movement_group_status === "voucher_created" ? "bilty.movement.voucherCreated" : row.movement_group_status === "completed" ? "bilty.movement.completed" : "bilty.movement.open";
    const presentation: ModulePrintPresentation = {
      documentType: "vehicle_monthly_hisab",
      title: printLabel("vehicleMonthlyHisab.print.chakkarTitle"),
      documentNo: printValue(row.voucher_no ?? row.movement_group_id ?? row.settlement_id),
      documentDate: printValue(row.chakkar_date),
      fields: [
        { label: printLabel("common.vehicle"), value: printValue(row.vehicle_no ?? report.vehicle.vehicle_no) },
        { label: printLabel("vehicleMonthlyHisab.table.chakkar"), value: printValue(row.source_type === "manual" ? t("vehicleMonthlyHisab.source.manual") : row.movement_group_id) },
        { label: printLabel("common.status"), value: row.source_type === "manual" ? printLabel("expenses.manual.finalized") : printLabel(statusKey) },
        { label: printLabel("vehicleMonthlyHisab.table.returnBilty"), value: printValue(row.return_bilty_no) },
        { label: printLabel("vehicleMonthlyHisab.table.voucher"), value: printValue(row.voucher_no) },
        ...(row.source_type === "manual" ? [{ label: printLabel("expenses.manual.chakkarDays"), value: printValue(row.chakkar_days) }] : []),
        { label: printLabel("vehicleMonthlyHisab.print.accountingVersion"), value: printValue(row.accounting_version) },
      ],
      totals: [
        { label: printLabel("vehicleMonthlyHisab.table.freight"), value: amount(rowFreight(row)) },
        { label: printLabel("vehicleMonthlyHisab.table.regular"), value: amount(row.regular_trip_expenses) },
        { label: printLabel("vehicleMonthlyHisab.table.periodic"), value: amount(row.vehicle_periodic_expenses) },
        { label: printLabel("vehicleMonthlyHisab.table.totalExpenses"), value: amount(rowExpenses(row)) },
        ...(row.source_type === "manual" ? [
          { label: printLabel("vehicleMonthlyHisab.table.adjustment"), value: amount(row.adjustment_total ?? 0) },
          { label: printLabel("vehicleMonthlyHisab.table.originalNet"), value: amount(row.original_chakkar_net ?? row.net_vehicle_amount) },
        ] : []),
        { label: printLabel("vehicleMonthlyHisab.table.net"), value: amount(rowNet(row)) },
      ],
      remarks: row.breakdown_status === "SNAPSHOT_MISMATCH" ? printLabel("vehicleMonthlyHisab.print.snapshotNotice") : null,
    };
    modulePrint.openPresentation(presentation, () => printChakkarLegacy(row), report.vehicle.adda_id);
  };

  const reverseChakkarSettlement = async (row: ChakkarRow) => {
    if (row.source_type === "manual") return;
    if (!window.confirm(t("vehicleMonthlyHisab.messages.deleteConfirm"))) return;

    setReversingSettlementId(row.settlement_id);
    setError("");
    try {
      const result = await supabase.rpc("reverse_vehicle_chakkar_settlement", {
        p_settlement_id: row.settlement_id,
      });
      if (result.error) {
        console.error("Vehicle Chakkar settlement reversal failed", {
          code: result.error.code,
          message: result.error.message,
          details: result.error.details,
          hint: result.error.hint,
          settlementId: row.settlement_id,
          movementGroupId: row.movement_group_id,
          voucherId: row.voucher_id,
        });
        window.alert(`${t("vehicleMonthlyHisab.messages.deleteFailed")}\n${result.error.message}`);
        return;
      }

      await loadReport();
      window.alert(t("vehicleMonthlyHisab.messages.deletedSuccessfully"));
    } catch (reversalError) {
      console.error("Vehicle Chakkar settlement reversal request failed", reversalError);
      const message = reversalError instanceof Error ? reversalError.message : String(reversalError);
      window.alert(`${t("vehicleMonthlyHisab.messages.deleteFailed")}\n${message}`);
    } finally {
      setReversingSettlementId(null);
    }
  };

  const summary = report?.summary;
  const breakdown = report?.expense_breakdown;
  const cards = [
    { label: t("vehicleMonthlyHisab.cards.totalChakkar"), value: String(summary?.total_chakkar ?? 0), icon: ClipboardList, tone: "bg-blue-50 text-blue-700" },
    { label: t("vehicleMonthlyHisab.cards.totalFreight"), value: amount(summary?.total_vehicle_freight ?? 0), icon: CircleDollarSign, tone: "bg-emerald-50 text-emerald-700" },
    { label: t("vehicleMonthlyHisab.cards.totalExpenses"), value: amount(summary?.total_expenses ?? 0), icon: TrendingDown, tone: "bg-amber-50 text-amber-700" },
    { label: summary && summary.vehicle_monthly_profit < 0 ? t("vehicleMonthlyHisab.cards.vehicleLoss") : t("vehicleMonthlyHisab.cards.vehicleProfit"), value: amount(summary?.vehicle_monthly_profit ?? 0), icon: summary && summary.vehicle_monthly_profit < 0 ? TrendingDown : TrendingUp, tone: summary && summary.vehicle_monthly_profit < 0 ? "bg-red-50 text-red-700" : "bg-violet-50 text-violet-700" },
  ];

  const categories = breakdown
    ? [
        { label: t("vehicleMonthlyHisab.breakdown.regular"), value: breakdown.regular_trip_expenses, authoritative: true },
        { label: t("vehicleMonthlyHisab.breakdown.periodic"), value: breakdown.vehicle_periodic_expenses, authoritative: true },
        { label: t("vehicleMonthlyHisab.breakdown.diesel"), value: breakdown.diesel, authoritative: false },
        { label: t("vehicleMonthlyHisab.breakdown.workshop"), value: breakdown.workshop, authoritative: false },
        { label: t("vehicleMonthlyHisab.breakdown.tyre"), value: breakdown.tyre, authoritative: false },
        { label: t("vehicleMonthlyHisab.breakdown.oil"), value: breakdown.oil, authoritative: false },
        { label: t("vehicleMonthlyHisab.breakdown.driver"), value: breakdown.driver, authoritative: false },
        { label: t("vehicleMonthlyHisab.breakdown.other"), value: breakdown.other, authoritative: false },
      ]
    : [];

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <ModulePageHeading icon="ledger" accent="blue" title={t("vehicleMonthlyHisab.title")} description={t("vehicleMonthlyHisab.description")} />
          <button type="button" onClick={printReport} disabled={!report || loadingReport} className="inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-3 font-black text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50">
            <Printer size={19} /> {t("vehicleMonthlyHisab.actions.print")}
          </button>
        </div>
      </section>

      <section className="rounded-2xl bg-white p-5 shadow-md">
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.2fr)_auto] xl:items-end">
          <label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("vehicleMonthlyHisab.filters.vehicle")}</span>
            <select value={vehicleId} onChange={(event) => setVehicleId(event.target.value)} disabled={loadingVehicles} className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100">
              <option value="">{t("vehicleMonthlyHisab.filters.selectVehicle")}</option>
              {vehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{display(vehicle.vehicle_no)}{vehicle.owner_name ? ` — ${vehicle.owner_name}` : ""}</option>)}
            </select>
          </label>

          <VoiceTypingField fieldLabel={t("vehicleMonthlyHisab.filters.month")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("vehicleMonthlyHisab.filters.month")}</span>
            <div className="relative"><CalendarDays className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} /><input type="month" value={month} onChange={(event) => setMonth(event.target.value)} className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" /></div>
          </label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("vehicleMonthlyHisab.filters.dateFrom")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("vehicleMonthlyHisab.filters.dateFrom")}</span>
            <div className="relative"><CalendarDays className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} /><input type="date" value={dateFrom} max={dateTo || undefined} onChange={(event) => setDateFrom(event.target.value)} className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" /></div>
          </label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("vehicleMonthlyHisab.filters.dateTo")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("vehicleMonthlyHisab.filters.dateTo")}</span>
            <div className="relative"><CalendarDays className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} /><input type="date" value={dateTo} min={dateFrom || undefined} onChange={(event) => setDateTo(event.target.value)} className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" /></div>
          </label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("vehicleMonthlyHisab.filters.searchPlaceholder")} mode="text"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("vehicleMonthlyHisab.filters.search")}</span>
            <div className="relative"><Search className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t("vehicleMonthlyHisab.filters.searchPlaceholder")} className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" /></div>
          </label></VoiceTypingField>

          <button type="button" onClick={() => { setMonth(currentMonthValue()); setDateFrom(""); setDateTo(""); setSearch(""); }} className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-300 px-4 py-3 font-bold text-slate-700 hover:bg-slate-50"><RotateCcw size={18} />{t("common.actions.reset")}</button>
        </div>
      </section>

      {error && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 font-bold text-red-700">{error}</div>}
      {loadingReport && <div role="status" className="rounded-xl bg-white p-6 text-center font-bold text-slate-700 shadow">{t("common.loading")}</div>}

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map((card) => <article key={card.label} className="rounded-2xl bg-white p-5 shadow-md"><div className={`mb-4 inline-flex rounded-xl p-3 ${card.tone}`}><card.icon size={24} /></div><p className="font-bold text-slate-600">{card.label}</p><p className="mt-2 text-2xl font-black text-slate-950 [direction:ltr] [unicode-bidi:isolate]">{card.value}</p></article>)}
      </section>

      <section className="rounded-2xl bg-white p-5 shadow-md">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="text-xl font-black text-slate-950">{t("vehicleMonthlyHisab.breakdown.title")}</h2><p className="mt-1 font-medium text-slate-600">{t("vehicleMonthlyHisab.breakdown.description")}</p></div>{breakdown?.status === "SNAPSHOT_MISMATCH" && <span className="rounded-full bg-amber-100 px-3 py-1 text-sm font-black text-amber-800">{t("vehicleMonthlyHisab.breakdown.mismatch")}</span>}</div>
        <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{categories.map((category) => <div key={category.label} className="rounded-xl border border-slate-200 bg-slate-50 p-4"><p className="text-sm font-bold text-slate-600">{category.label}</p><p className="mt-2 text-lg font-black text-slate-950 [direction:ltr] [unicode-bidi:isolate]">{breakdown?.status === "SNAPSHOT_MISMATCH" && !category.authoritative ? t("vehicleMonthlyHisab.breakdown.unavailable") : amount(category.value)}</p></div>)}</div>
        <div className="mt-4 rounded-xl border border-dashed border-slate-300 bg-slate-50 p-4"><p className="font-bold text-slate-700">{t("vehicleMonthlyHisab.breakdown.unallocated")}</p><p className="mt-1 text-sm font-semibold text-slate-600">{t("vehicleMonthlyHisab.breakdown.unallocatedGap")}</p></div>
      </section>

      <section className="overflow-hidden rounded-2xl bg-white shadow-md">
        <div className="border-b border-slate-200 p-5">
          <h2 className="text-xl font-black text-slate-950">{t("vehicleMonthlyHisab.table.title")}</h2>
          <p className="mt-1 font-medium text-slate-600">{t("vehicleMonthlyHisab.table.description")}</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1500px] text-sm">
            <thead className="bg-blue-700 text-white">
              <tr>
                {["date","chakkar","status","returnBilty","voucher","freight","regular","periodic","totalExpenses","adjustment","net","actions"].map((key) => (
                  <th key={key} className="px-4 py-3 text-start font-black">{t(`vehicleMonthlyHisab.table.${key}`)}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {visibleRows.map((row) => (
                <tr key={row.settlement_id} className="hover:bg-blue-50/60">
                  <td className="px-4 py-3 font-semibold">{row.chakkar_date}</td>
                  <td className="max-w-44 truncate px-4 py-3 font-mono text-xs" title={row.movement_group_id ?? t("vehicleMonthlyHisab.source.manual")}>{row.movement_group_id ?? t("vehicleMonthlyHisab.source.manual")}</td>
                  <td className="px-4 py-3"><span className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-black text-emerald-800">{row.source_type === "manual" ? t("expenses.manual.finalized") : row.movement_group_status}</span>{row.source_type === "manual" && row.chakkar_days ? <span className="ms-2 text-xs font-bold text-slate-600">{t("expenses.manual.chakkarDays")}: {row.chakkar_days}</span> : null}</td>
                  <td className="px-4 py-3 font-semibold">{display(row.return_bilty_no)}</td>
                  <td className="px-4 py-3 font-semibold">{display(row.voucher_no)}</td>
                  <td className="px-4 py-3 text-end font-bold [direction:ltr]">{amount(rowFreight(row))}</td>
                  <td className="px-4 py-3 text-end [direction:ltr]">{amount(row.regular_trip_expenses)}</td>
                  <td className="px-4 py-3 text-end [direction:ltr]">{amount(row.vehicle_periodic_expenses)}</td>
                  <td className="px-4 py-3 text-end font-bold [direction:ltr]">{amount(rowExpenses(row))}</td>
                  <td className="px-4 py-3 text-end [direction:ltr]">{row.source_type === "manual" ? amount(row.adjustment_total ?? 0) : "—"}</td>
                  <td className={`px-4 py-3 text-end font-black [direction:ltr] ${rowNet(row) < 0 ? "text-red-700" : "text-emerald-700"}`}>{amount(rowNet(row))}{row.source_type === "manual" && <div className="mt-1 text-xs font-semibold text-slate-600">{t("vehicleMonthlyHisab.table.originalNet")}: {amount(row.original_chakkar_net ?? row.net_vehicle_amount)} · {t("vehicleMonthlyHisab.table.adjustment")}: {amount(row.adjustment_total ?? 0)}</div>}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-2">
                      {row.movement_group_id && <Link href={`/bilty?movementGroupId=${encodeURIComponent(row.movement_group_id)}`} className="rounded-lg bg-blue-100 px-3 py-2 font-bold text-blue-800 hover:bg-blue-200">{t("vehicleMonthlyHisab.actions.viewChakkar")}</Link>}
                      <Link href={`/expenses?voucherId=${row.voucher_id}`} className="rounded-lg bg-violet-100 px-3 py-2 font-bold text-violet-800 hover:bg-violet-200">{t("vehicleMonthlyHisab.actions.viewVoucher")}</Link>
                      <button type="button" onClick={() => printChakkar(row)} className="inline-flex items-center gap-1 rounded-lg border border-slate-300 bg-white px-3 py-2 font-bold text-slate-800 hover:bg-slate-100">
                        <Printer size={15} /> {t("vehicleMonthlyHisab.actions.printChakkar")}
                      </button>
                      {row.source_type !== "manual" && <button type="button" onClick={() => void reverseChakkarSettlement(row)} disabled={reversingSettlementId === row.settlement_id} className="inline-flex items-center gap-1 rounded-lg bg-red-600 px-3 py-2 font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-60">
                        <Trash2 size={15} /> {reversingSettlementId === row.settlement_id ? t("vehicleMonthlyHisab.actions.deletingChakkar") : t("vehicleMonthlyHisab.actions.deleteChakkar")}
                      </button>}
                    </div>
                  </td>
                </tr>
              ))}
              {!loadingReport && visibleRows.length === 0 && (
                <tr><td colSpan={12} className="px-4 py-12 text-center font-bold text-slate-500"><Truck className="mx-auto mb-3" />{t("vehicleMonthlyHisab.table.empty")}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      {modulePrint.dialog}
    </div>
  );
}
