"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import { translations } from "@/i18n/translations";
import {
  aggregateOwnerTotals,
  aggregateVehicleTotals,
  assertUniqueVehicleBundles,
  buildReportPeriodArgs,
  canLoadVehicleOwnerSummary,
  calculateEarningsReconciliation,
  calculateOwnerMovementBreakdown,
  expenseCategoriesForPrint,
  groupOwnersByCurrentName,
  reconcileExpenseBreakdown,
  validateVehicleBundle,
  type SourceLinkIssue,
  type PeriodSelection,
  type SummaryVehicle,
  type VehicleReportBundle,
} from "@/lib/reports/vehicleOwnerSummary";
import { bilingual, type BilingualText, type ModulePrintPresentation, type PrintCell } from "@/lib/print/modulePresentation";

type AddaOption = { id: string; name: string };
type Props = { role: "super_admin" | "adda_admin"; profileAddaId: string | null };
type DraftPeriod = { mode: "month" | "custom"; month: string; from: string; to: string };

const PAGE_SIZE = 500;

function currentMonth() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

function amount(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function amountValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  const parsed = Number(value);
  return Number.isFinite(parsed) ? amount(parsed) : "—";
}

function text(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  return String(value);
}

function dictionaryValue(language: "en" | "ur", key: string): string {
  let value: unknown = translations[language];
  for (const part of key.split(".")) {
    if (!value || typeof value !== "object") return key;
    value = (value as Record<string, unknown>)[part];
  }
  return typeof value === "string" ? value : key;
}

function summaryUrTranslation(key: string): string {
  return dictionaryValue("ur", `reports.vehicleOwnerSummary.${key}`);
}

function summaryEnglishTranslation(key: string): string {
  return dictionaryValue("en", `reports.vehicleOwnerSummary.${key}`);
}

function bilingualOwnerTransactionLabel(type: string) {
  const key = `ownerGariAccount.transactionTypes.${type}`;
  const en = dictionaryValue("en", key);
  const ur = dictionaryValue("ur", key);
  return en === key && ur === key ? type || "—" : bilingual(en === key ? type : en, ur === key ? type : ur);
}

function printableOptionalAmount(value: number | null, unavailable: PrintCell): PrintCell {
  return value === null ? unavailable : amount(value);
}

function sourceLinkIssueKey(scope: "chakkars" | "voucherAdjustments", issue: SourceLinkIssue) {
  const issueKey = issue === "missing_source_id" ? "missingSourceId" : "duplicateSourceId";
  return `reports.vehicleOwnerSummary.sourceLinkIssues.${scope}.${issueKey}`;
}

function linkedAmountText(
  value: number | null,
  issue: SourceLinkIssue | null,
  scope: "chakkars" | "voucherAdjustments",
  t: (key: string) => string,
) {
  return value === null
    ? <><span>{t("reports.vehicleOwnerSummary.table.unavailable")}</span>{issue ? <small className="block max-w-64 text-xs font-normal text-slate-500">{t(sourceLinkIssueKey(scope, issue))}</small> : null}</>
    : amount(value);
}

function savedChakkarValues(row: Record<string, unknown>) {
  const manual = row.source_type === "manual";
  return {
    freight: manual ? row.adjusted_vehicle_freight ?? row.vehicle_freight : row.vehicle_freight,
    expenses: manual ? row.adjusted_total_expenses ?? row.total_expenses : row.total_expenses,
    net: manual ? row.adjusted_net_vehicle_amount ?? row.net_vehicle_amount : row.net_vehicle_amount,
  };
}

async function loadAllVehicles(addaId: string): Promise<SummaryVehicle[]> {
  const rows: SummaryVehicle[] = [];
  for (let start = 0; ; start += PAGE_SIZE) {
    const result = await supabase.from("vehicles")
      .select("id,adda_id,vehicle_no,owner_name")
      .eq("adda_id", addaId)
      .order("vehicle_no", { ascending: true })
      .range(start, start + PAGE_SIZE - 1);
    if (result.error) throw result.error;
    const page = (result.data ?? []) as SummaryVehicle[];
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

async function mapWithLimit<T, R>(items: readonly T[], limit: number, map: (item: T) => Promise<R>): Promise<R[]> {
  const output = new Array<R>(items.length);
  let cursor = 0;
  async function worker() {
    while (true) {
      const index = cursor++;
      if (index >= items.length) return;
      output[index] = await map(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => worker()));
  return output;
}

export default function VehicleOwnerSummary({ role, profileAddaId }: Props) {
  const { t, dir, language } = useLanguage();
  const root = "reports.vehicleOwnerSummary";
  const tRef = useRef(t);
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [selectedAddaId, setSelectedAddaId] = useState(role === "adda_admin" ? profileAddaId ?? "" : "");
  const [vehicles, setVehicles] = useState<SummaryVehicle[]>([]);
  const [loadingAddas, setLoadingAddas] = useState(true);
  const [loadingVehicles, setLoadingVehicles] = useState(false);
  const [draftPeriod, setDraftPeriod] = useState<DraftPeriod>({ mode: "month", month: currentMonth(), from: "", to: "" });
  const [draftOwner, setDraftOwner] = useState("");
  const [draftVehicle, setDraftVehicle] = useState("");
  const [report, setReport] = useState<VehicleReportBundle[] | null>(null);
  const [reportAddaId, setReportAddaId] = useState<string | null>(null);
  const [reportPeriod, setReportPeriod] = useState<PeriodSelection | null>(null);
  const [reportFilters, setReportFilters] = useState<{ owner: string; vehicleId: string } | null>(null);
  const [loadingReport, setLoadingReport] = useState(false);
  const [error, setError] = useState("");
  const [expandedVehicle, setExpandedVehicle] = useState<string | null>(null);
  const requestId = useRef(0);
  const addaRequestId = useRef(0);
  const vehicleRequestId = useRef(0);
  const print = useModuleTransportPrint("reports", reportAddaId, language === "ur" ? "ur" : "en");

  useEffect(() => { tRef.current = t; }, [t]);

  useEffect(() => {
    let active = true;
    const request = ++addaRequestId.current;
    async function loadAddaOptions() {
      setLoadingAddas(true);
      try {
        if (role === "adda_admin") {
          if (!profileAddaId) throw new Error("The active Adda Admin profile has no Adda assignment.");
          const result = await supabase.from("addas").select("id,name").eq("id", profileAddaId).maybeSingle();
          if (result.error) throw result.error;
          if (!result.data) throw new Error("The assigned Adda could not be verified.");
          if (!active || request !== addaRequestId.current) return;
          setAddas([{ id: String(result.data.id), name: String(result.data.name ?? "") }]);
          setSelectedAddaId(String(result.data.id));
        } else {
          const rows: AddaOption[] = [];
          for (let start = 0; ; start += PAGE_SIZE) {
            const result = await supabase.from("addas").select("id,name").order("name").range(start, start + PAGE_SIZE - 1);
            if (result.error) throw result.error;
            const page = (result.data ?? []).map((item) => ({ id: String(item.id), name: String(item.name ?? "") }));
            rows.push(...page);
            if (page.length < PAGE_SIZE) break;
          }
          if (!active || request !== addaRequestId.current) return;
          setAddas(rows);
          setSelectedAddaId((current) => rows.some((item) => item.id === current) ? current : "");
        }
        setError("");
      } catch (caught) {
        if (!active || request !== addaRequestId.current) return;
        console.error("Vehicle & Owner Summary Adda options failed", caught);
        setAddas([]);
        setSelectedAddaId("");
        setError(tRef.current(`${root}.loadError`));
      } finally {
        if (active && request === addaRequestId.current) setLoadingAddas(false);
      }
    }
    void loadAddaOptions();
    return () => { active = false; addaRequestId.current += 1; requestId.current += 1; };
  }, [profileAddaId, role]);

  useEffect(() => {
    let active = true;
    const request = ++vehicleRequestId.current;
    requestId.current += 1;
    if (!selectedAddaId || !addas.some((item) => item.id === selectedAddaId)) {
      return () => { active = false; };
    }
    void (async () => {
      await Promise.resolve();
      if (!active || request !== vehicleRequestId.current) return;
      setLoadingVehicles(true);
      try {
        const rows = await loadAllVehicles(selectedAddaId);
        if (!active || request !== vehicleRequestId.current) return;
        setVehicles(rows);
        setError("");
      } catch (caught) {
        if (!active || request !== vehicleRequestId.current) return;
        console.error("Vehicle & Owner Summary vehicle load failed", caught);
        setVehicles([]);
        setError(tRef.current(`${root}.loadError`));
      } finally {
        if (active && request === vehicleRequestId.current) setLoadingVehicles(false);
      }
    })();
    return () => { active = false; };
  }, [addas, selectedAddaId]);

  const ownerOptions = useMemo(() => Array.from(new Set(vehicles.map((vehicle) => vehicle.owner_name?.trim()).filter((name): name is string => Boolean(name)))).sort((a, b) => a.localeCompare(b)), [vehicles]);
  const availableVehicles = useMemo(() => vehicles.filter((vehicle) => !draftOwner || vehicle.owner_name?.trim() === draftOwner), [draftOwner, vehicles]);
  const currentAddaName = addas.find((item) => item.id === selectedAddaId)?.name ?? "";
  const activeReport = reportAddaId === selectedAddaId ? report : null;
  const vehicleTotals = useMemo(() => activeReport ? aggregateVehicleTotals(activeReport) : null, [activeReport]);
  const ownerTotals = useMemo(() => activeReport ? aggregateOwnerTotals(activeReport) : null, [activeReport]);
  const ownerGroups = useMemo(() => activeReport ? groupOwnersByCurrentName(activeReport) : [], [activeReport]);
  const reconciliation = useMemo(() => activeReport ? calculateEarningsReconciliation(activeReport) : null, [activeReport]);
  const modulePrint = print;

  const runReport = useCallback(async () => {
    if (!selectedAddaId || !addas.some((item) => item.id === selectedAddaId) || !canLoadVehicleOwnerSummary(role, profileAddaId, selectedAddaId)) {
      setError(t(`${root}.noAdda`));
      return;
    }
    let period: PeriodSelection;
    try {
      period = draftPeriod.mode === "month"
        ? { mode: "month", month: draftPeriod.month }
        : { mode: "custom", from: draftPeriod.from, to: draftPeriod.to };
      buildReportPeriodArgs(period);
    } catch {
      setReport(null);
      setReportAddaId(null);
      setError(t(`${root}.invalidPeriod`));
      return;
    }
    const request = ++requestId.current;
    const targetAddaId = selectedAddaId;
    const selectedVehicles = vehicles.filter((vehicle) =>
      (!draftOwner || vehicle.owner_name?.trim() === draftOwner) &&
      (!draftVehicle || vehicle.id === draftVehicle)
    );
    setLoadingReport(true);
    setReport(null);
    setReportAddaId(null);
    setReportPeriod(null);
    setReportFilters(null);
    setExpandedVehicle(null);
    setError("");
    try {
      const args = buildReportPeriodArgs(period);
      const bundles = await mapWithLimit(selectedVehicles, 4, async (vehicle) => {
        const [monthly, closing, statement] = await Promise.all([
          supabase.rpc("get_vehicle_monthly_hisab_v3", {
            p_vehicle_id: vehicle.id,
            p_month: args.month,
            p_date_from: args.from,
            p_date_to: args.to,
          }),
          supabase.rpc("get_owner_gari_closing_v2", {
            p_adda_id: targetAddaId,
            p_vehicle_id: vehicle.id,
            p_month: args.month,
            p_date_from: args.from,
            p_date_to: args.to,
            p_transaction_type: null,
            p_search: null,
          }),
          supabase.rpc("get_owner_gari_account_statement_v5", {
            p_vehicle_id: vehicle.id,
            p_month: args.month,
            p_date_from: args.from,
            p_date_to: args.to,
            p_transaction_type: null,
            p_movement_group_id: null,
            p_search: null,
          }),
        ]);
        if (monthly.error) throw monthly.error;
        if (closing.error) throw closing.error;
        if (statement.error) throw statement.error;
        return validateVehicleBundle(vehicle, targetAddaId, monthly.data, closing.data, statement.data);
      });
      assertUniqueVehicleBundles(bundles);
      if (request !== requestId.current || targetAddaId !== selectedAddaId) return;
      setReport(bundles);
      setReportAddaId(targetAddaId);
      setReportPeriod(period);
      setReportFilters({ owner: draftOwner, vehicleId: draftVehicle });
    } catch (caught) {
      if (request !== requestId.current) return;
      console.error("Vehicle & Owner Summary read failed", caught);
      setReport(null);
      setReportAddaId(null);
      setError(t(`${root}.loadError`));
    } finally {
      if (request === requestId.current) setLoadingReport(false);
    }
  }, [addas, draftOwner, draftPeriod, draftVehicle, profileAddaId, role, selectedAddaId, t, vehicles]);

  const resetFilters = () => {
    setDraftPeriod({ mode: "month", month: currentMonth(), from: "", to: "" });
    setDraftOwner("");
    setDraftVehicle("");
    setReport(null);
    setReportAddaId(null);
    setReportPeriod(null);
    setReportFilters(null);
    setError("");
    requestId.current += 1;
  };

  const printPresentation = useMemo<ModulePrintPresentation | null>(() => {
    if (!activeReport || !vehicleTotals || !ownerTotals || !reportPeriod || !selectedAddaId) return null;
    const periodLabel = reportPeriod.mode === "month" ? reportPeriod.month : `${reportPeriod.from} — ${reportPeriod.to}`;
    const bilingualLabel = (key: string) => bilingual(summaryEnglishTranslation(key), summaryUrTranslation(key));
    const ownerName = (bundle: VehicleReportBundle) => bundle.vehicle.owner_name?.trim() || bilingual(summaryEnglishTranslation("notRecorded"), summaryUrTranslation("notRecorded"));
    const ownerVehicleNumbers = (group: (typeof ownerGroups)[number]) => {
      const vehicleNumbers = group.vehicleIds
        .map((vehicleId) => activeReport.find((bundle) => bundle.vehicle.id === vehicleId)?.vehicle.vehicle_no?.trim())
        .filter((vehicleNo): vehicleNo is string => Boolean(vehicleNo));
      return vehicleNumbers.length ? text(vehicleNumbers.join(", ")) : "—";
    };
    const sourceIssueLabel = (issue: SourceLinkIssue | null) => bilingualLabel(issue === "missing_source_id"
      ? "print.sourceIdMissing"
      : issue === "duplicate_source_id" ? "print.duplicateSourceId" : "print.noLinkIssues");
    const sourceStatus = (chakkarIssue: SourceLinkIssue | null, voucherIssue: SourceLinkIssue | null, showCleanStatus = false): PrintCell => {
      const issues = [
        chakkarIssue ? [bilingualLabel("print.chakkarLink"), sourceIssueLabel(chakkarIssue)] as const : null,
        voucherIssue ? [bilingualLabel("print.voucherAdjustmentLink"), sourceIssueLabel(voucherIssue)] as const : null,
      ].filter((entry): entry is readonly [BilingualText, BilingualText] => entry !== null);
      if (!issues.length) return showCleanStatus ? bilingualLabel("print.noLinkIssues") : "—";
      return bilingual(
        issues.map(([label, status]) => `${label.en}: ${status.en}`).join("; "),
        issues.map(([label, status]) => `${label.ur}: ${status.ur}`).join("؛ "),
      );
    };
    const chakkarRows: PrintCell[][] = [];
    const transactionRows: PrintCell[][] = [];
    const expenseRows: PrintCell[][] = [];
    const expenseTotalRows: PrintCell[][] = [];
    const unavailable = bilingual(summaryEnglishTranslation("table.unavailable"), summaryUrTranslation("table.unavailable"));
    const ownerMovementRows: PrintCell[][] = [];
    const ownerClosingRows: PrintCell[][] = [];
    const sourceVerificationRows: PrintCell[][] = [];
    for (const bundle of activeReport) {
      for (const chakkar of bundle.monthly.chakkars) {
        const values = savedChakkarValues(chakkar);
        const breakdown = reconcileExpenseBreakdown(chakkar, values.expenses);
        chakkarRows.push([
          text(chakkar.chakkar_date), ownerName(bundle), text(bundle.vehicle.vehicle_no),
          chakkar.source_type === "manual" ? bilingualLabel("source.manual") : bilingualLabel("source.bilty"),
          text(chakkar.voucher_no ?? chakkar.movement_group_id), amountValue(values.freight), amountValue(values.expenses), amountValue(values.net),
        ]);
        const reference = text(chakkar.voucher_no ?? chakkar.movement_group_id);
        if (breakdown.status === "unavailable") {
          expenseRows.push([
            ownerName(bundle), text(bundle.vehicle.vehicle_no), text(chakkar.chakkar_date), reference,
            bilingualLabel("breakdown.unavailable"), unavailable, bilingualLabel("breakdown.unavailable"),
          ]);
        } else if (breakdown.status === "complete" && expenseCategoriesForPrint(breakdown).length === 0 && breakdown.unallocated === 0) {
          expenseRows.push([
            ownerName(bundle), text(bundle.vehicle.vehicle_no), text(chakkar.chakkar_date), reference,
            bilingualLabel("print.allZeroBreakdown"), amount(0), bilingualLabel("breakdown.complete"),
          ]);
        } else {
          for (const { category, amount: categoryAmount } of expenseCategoriesForPrint(breakdown)) {
            expenseRows.push([
              ownerName(bundle), text(bundle.vehicle.vehicle_no), text(chakkar.chakkar_date), reference,
              bilingualLabel(`table.${category}`), amount(categoryAmount), bilingualLabel(`breakdown.${breakdown.status}`),
            ]);
          }
          if (breakdown.unallocated !== 0) {
            expenseRows.push([
              ownerName(bundle), text(bundle.vehicle.vehicle_no), text(chakkar.chakkar_date), reference,
              bilingualLabel("table.unallocated"), printableOptionalAmount(breakdown.unallocated, unavailable), bilingualLabel(`breakdown.${breakdown.status}`),
            ]);
          }
        }
        expenseTotalRows.push([
          ownerName(bundle), text(bundle.vehicle.vehicle_no), text(chakkar.chakkar_date), reference,
          amountValue(values.expenses), printableOptionalAmount(breakdown.unallocated, unavailable), bilingualLabel(`breakdown.${breakdown.status}`),
        ]);
      }
      for (const transaction of bundle.statement.transactions) {
        const type = String(transaction.transaction_type ?? "");
        transactionRows.push([
          ownerName(bundle), text(bundle.vehicle.vehicle_no), text(transaction.transaction_date), bilingualOwnerTransactionLabel(type),
          text(transaction.reference_no ?? transaction.description), amountValue(transaction.signed_amount),
        ]);
      }
    }
    for (const group of ownerGroups) {
      const owner = group.ownerName ?? bilingual("Owner not recorded", "مالک درج نہیں");
      const vehiclesInGroup = text(ownerVehicleNumbers(group));
      const movementDetails: Array<[string, PrintCell]> = [
        ["cards.commissionNet", amount(group.commissionNet)],
        ["cards.otherAdjustmentNet", amount(group.otherAdjustmentNet)],
        ["cards.withdrawals", amount(group.actualWithdrawals)],
        ["table.withdrawalMovement", amount(group.withdrawalMovement)],
        ["table.openingSeedMovement", amount(group.openingSeedMovement)],
        ["table.unclassifiedMovement", printableOptionalAmount(group.unclassifiedMovement, unavailable)],
      ];
      for (const [label, value] of movementDetails) ownerMovementRows.push([owner, vehiclesInGroup, bilingualLabel(label), value]);
      ownerClosingRows.push([
        owner, vehiclesInGroup, amount(group.opening), amount(group.periodMovement), amount(group.closing), amount(group.payable), amount(group.receivable),
      ]);
      sourceVerificationRows.push([
        owner, vehiclesInGroup, amount(group.recordedChakkarCredits), printableOptionalAmount(group.verifiedLinkedChakkarCredits, unavailable),
        amount(group.recordedVoucherAdjustmentNet), printableOptionalAmount(group.verifiedLinkedVoucherAdjustmentNet, unavailable),
        sourceStatus(group.chakkarSourceLinkIssue, group.voucherAdjustmentSourceLinkIssue),
      ]);
    }
    sourceVerificationRows.push([
      bilingualLabel("print.reportTotal"), bilingualLabel("print.allFilteredVehicles"),
      amount(ownerTotals.recordedChakkarCredits), printableOptionalAmount(ownerTotals.verifiedLinkedChakkarCredits, unavailable),
      amount(ownerTotals.recordedVoucherAdjustmentNet), printableOptionalAmount(ownerTotals.verifiedLinkedVoucherAdjustmentNet, unavailable),
      sourceStatus(ownerTotals.chakkarSourceLinkIssue, ownerTotals.voucherAdjustmentSourceLinkIssue, true),
    ]);
    const reconciliationRows: PrintCell[][] = [
      [bilingualLabel("reconciliation.differenceBeforeAdjustments"), printableOptionalAmount(reconciliation?.differenceBeforeVoucherAdjustments ?? null, unavailable)],
      [bilingualLabel("reconciliation.remainingDifference"), printableOptionalAmount(reconciliation?.remainingDifference ?? null, unavailable)],
    ];
    return {
      documentType: "reports",
      layoutVariant: "vehicle_owner_summary",
      title: bilingualLabel("print.title"),
      documentDate: periodLabel,
      subtitle: bilingual(`${currentAddaName} · ${periodLabel}`, `${currentAddaName} · ${periodLabel}`),
      fields: [
        { label: bilingualLabel("adda"), value: currentAddaName },
        { label: bilingualLabel("period"), value: periodLabel },
        { label: bilingualLabel("currentOwner"), value: reportFilters?.owner || bilingual(summaryEnglishTranslation("allOwners"), summaryUrTranslation("allOwners")) },
        { label: bilingualLabel("vehicle"), value: reportFilters?.vehicleId ? text(vehicles.find((item) => item.id === reportFilters.vehicleId)?.vehicle_no) : bilingual(summaryEnglishTranslation("allVehicles"), summaryUrTranslation("allVehicles")) },
      ],
      tables: [
        {
          title: bilingualLabel("print.vehicleRows"),
          columns: ["table.owner", "table.vehicle", "table.chakkars", "table.freight", "table.expenses", "table.earnings"].map(bilingualLabel),
          rows: activeReport.map((bundle) => [ownerName(bundle), text(bundle.vehicle.vehicle_no), text(bundle.monthly.summary.total_chakkar), amountValue(bundle.monthly.summary.total_vehicle_freight), amountValue(bundle.monthly.summary.total_expenses), amountValue(bundle.monthly.summary.vehicle_monthly_profit)]),
        },
        {
          title: bilingualLabel("print.ownerRows"),
          columns: ["table.owner", "table.vehicles", "table.type", "table.signedAmount"].map(bilingualLabel),
          rows: ownerMovementRows,
        },
        {
          title: bilingualLabel("print.ownerTransactions"),
          columns: ["table.owner", "table.vehicle", "table.date", "table.type", "table.reference", "table.signedAmount"].map(bilingualLabel),
          rows: transactionRows,
        },
        {
          title: bilingualLabel("print.ownerClosing"),
          columns: ["table.owner", "table.vehicles", "table.opening", "table.movement", "table.closing", "table.payable", "table.receivable"].map(bilingualLabel),
          rows: ownerClosingRows,
        },
        {
          title: bilingualLabel("print.sourceVerification"),
          columns: ["table.owner", "table.vehicles", "table.recordedChakkarCredits", "table.verifiedLinkedChakkarCredits", "table.recordedVoucherAdjustments", "table.verifiedLinkedVoucherAdjustments", "print.sourceStatus"].map(bilingualLabel),
          rows: sourceVerificationRows,
        },
        {
          title: bilingualLabel("print.reconciliation"),
          columns: ["print.reconciliationMeasure", "print.value"].map(bilingualLabel),
          rows: reconciliationRows,
        },
        {
          title: bilingualLabel("print.chakkars"),
          columns: ["table.date", "table.owner", "table.vehicle", "table.source", "table.reference", "table.freight", "table.expenses", "table.net"].map(bilingualLabel),
          rows: chakkarRows,
        },
        {
          title: bilingualLabel("print.expenseCategories"),
          columns: ["table.owner", "table.vehicle", "table.date", "table.reference", "print.category", "print.value", "table.breakdownStatus"].map(bilingualLabel),
          rows: expenseRows,
        },
        {
          title: bilingualLabel("print.expenseTotals"),
          columns: ["table.owner", "table.vehicle", "table.date", "table.reference", "table.total", "table.unallocated", "table.breakdownStatus"].map(bilingualLabel),
          rows: expenseTotalRows,
        },
      ],
      totals: [
        { label: bilingualLabel("cards.chakkars"), value: String(vehicleTotals.chakkars) },
        { label: bilingualLabel("cards.freight"), value: amount(vehicleTotals.freight) },
        { label: bilingualLabel("cards.expenses"), value: amount(vehicleTotals.expenses) },
        { label: bilingualLabel("cards.earnings"), value: amount(vehicleTotals.netEarnings) },
        { label: bilingualLabel("cards.opening"), value: amount(ownerTotals.opening) },
        { label: bilingualLabel("cards.movement"), value: amount(ownerTotals.periodMovement) },
        { label: bilingualLabel("cards.closing"), value: amount(ownerTotals.closing) },
        { label: bilingualLabel("cards.payable"), value: amount(ownerTotals.payable) },
        { label: bilingualLabel("cards.receivable"), value: amount(ownerTotals.receivable) },
      ],
      remarks: bilingual(
        "Earnings use settlement dates; owner balances use transaction dates. Net earnings are not a payout, and differences are not posted twice.",
        "آمدن تصفیہ کی تاریخ، مالک کا بقایا لین دین کی تاریخ کے مطابق ہے۔ خالص آمدن ادائیگی نہیں، اور فرق دوبارہ درج نہیں ہوتا۔",
      ),
    };
  }, [activeReport, currentAddaName, ownerGroups, ownerTotals, reconciliation, reportFilters, reportPeriod, selectedAddaId, vehicleTotals, vehicles]);

  const openPrint = () => {
    if (printPresentation && reportAddaId) modulePrint.openPresentation(printPresentation, () => window.print(), reportAddaId);
  };

  const pageTitle = t(`${root}.title`);
  const pageDescription = t(`${root}.description`);
  return <div dir={dir} className="ut-module-page mx-auto max-w-[1500px] space-y-5">
    <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <ModulePageHeading icon="reports" accent="purple" title={pageTitle} description={pageDescription} />
    </header>

    <section className="grid gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-4">
      {role === "super_admin" ? <label className="grid gap-1 text-sm font-bold sm:col-span-2"><span>{t(`${root}.adda`)}</span><select className="min-h-11 rounded-lg border border-slate-300 bg-white px-3" value={selectedAddaId} onChange={(event) => { setSelectedAddaId(event.target.value); setDraftOwner(""); setDraftVehicle(""); setVehicles([]); setLoadingVehicles(Boolean(event.target.value)); setReport(null); setReportAddaId(null); setReportPeriod(null); setReportFilters(null); setExpandedVehicle(null); setLoadingReport(false); setError(""); requestId.current += 1; }} disabled={loadingAddas}><option value="">{t(`${root}.selectAdda`)}</option>{addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}</select></label> : <div className="grid gap-1 text-sm"><span className="font-bold">{t(`${root}.adda`)}</span><strong className="min-h-11 content-center rounded-lg border border-slate-200 bg-slate-50 px-3">{currentAddaName || "—"}</strong></div>}
      <label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.period`)}</span><select className="min-h-11 rounded-lg border border-slate-300 bg-white px-3" value={draftPeriod.mode} onChange={(event) => setDraftPeriod((current) => ({ ...current, mode: event.target.value as DraftPeriod["mode"] }))}><option value="month">{t(`${root}.month`)}</option><option value="custom">{t(`${root}.customRange`)}</option></select></label>
      {draftPeriod.mode === "month" ? <label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.month`)}</span><input aria-label={t(`${root}.month`)} className="min-h-11 rounded-lg border border-slate-300 px-3" type="month" value={draftPeriod.month} onChange={(event) => setDraftPeriod((current) => ({ ...current, month: event.target.value }))} /></label> : <><label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.fromDate`)}</span><input aria-label={t(`${root}.fromDate`)} className="min-h-11 rounded-lg border border-slate-300 px-3" type="date" value={draftPeriod.from} onChange={(event) => setDraftPeriod((current) => ({ ...current, from: event.target.value }))} /></label><label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.toDate`)}</span><input aria-label={t(`${root}.toDate`)} className="min-h-11 rounded-lg border border-slate-300 px-3" type="date" value={draftPeriod.to} onChange={(event) => setDraftPeriod((current) => ({ ...current, to: event.target.value }))} /></label></>}
      <label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.currentOwner`)}</span><select className="min-h-11 rounded-lg border border-slate-300 bg-white px-3" value={draftOwner} onChange={(event) => { setDraftOwner(event.target.value); setDraftVehicle(""); }} disabled={loadingVehicles}><option value="">{t(`${root}.allOwners`)}</option>{ownerOptions.map((owner) => <option key={owner} value={owner}>{owner}</option>)}</select></label>
      <label className="grid gap-1 text-sm font-bold"><span>{t(`${root}.vehicle`)}</span><select className="min-h-11 rounded-lg border border-slate-300 bg-white px-3" value={draftVehicle} onChange={(event) => setDraftVehicle(event.target.value)} disabled={loadingVehicles}><option value="">{t(`${root}.allVehicles`)}</option>{availableVehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicle_no || "—"}</option>)}</select></label>
      <div className="flex flex-wrap items-end gap-2 sm:col-span-2 lg:col-span-4"><button type="button" className="min-h-11 rounded-lg bg-slate-900 px-5 font-bold text-white disabled:opacity-50" disabled={loadingAddas || loadingVehicles || loadingReport || !selectedAddaId} onClick={() => void runReport()}>{loadingReport ? t(`${root}.loading`) : t(`${root}.loadReport`)}</button><button type="button" className="min-h-11 rounded-lg border border-slate-300 px-5 font-bold" onClick={resetFilters}>{t(`${root}.reset`)}</button><button type="button" className="min-h-11 rounded-lg border border-blue-800 px-5 font-bold text-blue-900 disabled:opacity-50" disabled={!printPresentation || loadingReport} onClick={openPrint}>{t("common.actions.print")}</button></div>
      {error ? <p role="alert" className="sm:col-span-2 lg:col-span-4 rounded-lg border border-red-200 bg-red-50 p-3 font-bold text-red-800">{error}</p> : null}
    </section>
    <p className="text-sm font-semibold text-slate-600">{t(`${root}.currentOwnerNote`)} {t(`${root}.sameNameNote`)}</p>
    {loadingReport ? <div role="status" className="rounded-xl border bg-white p-8 text-center font-bold text-slate-700">{t(`${root}.loading`)}</div> : null}
    {!loadingReport && !activeReport && !error ? <div className="rounded-xl border bg-white p-6 text-center font-semibold text-slate-600">{t(`${root}.runToView`)}</div> : null}
    {!loadingReport && activeReport && activeReport.length === 0 ? <div className="rounded-xl border bg-white p-6 text-center font-semibold text-slate-600">{t(`${root}.noVehicles`)}</div> : null}
    {!loadingReport && activeReport && activeReport.length > 0 && vehicleTotals && ownerTotals ? <>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard label={t(`${root}.cards.chakkars`)} value={vehicleTotals.chakkars.toLocaleString("en-PK")} />
        <SummaryCard label={t(`${root}.cards.freight`)} value={amount(vehicleTotals.freight)} />
        <SummaryCard label={t(`${root}.cards.expenses`)} value={amount(vehicleTotals.expenses)} />
        <SummaryCard label={t(`${root}.cards.earnings`)} value={amount(vehicleTotals.netEarnings)} />
      </div>
      <section className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="text-lg font-extrabold text-slate-900">{t(`${root}.sections.ownerTotals`)}</h2>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <SummaryCard label={t(`${root}.cards.opening`)} value={amount(ownerTotals.opening)} />
          <SummaryCard label={t(`${root}.cards.movement`)} value={amount(ownerTotals.periodMovement)} />
          <SummaryCard label={t(`${root}.cards.recordedChakkarCredits`)} value={amount(ownerTotals.recordedChakkarCredits)} />
          <SummaryCard label={t(`${root}.cards.verifiedLinkedChakkarCredits`)} value={ownerTotals.verifiedLinkedChakkarCredits === null ? t(`${root}.table.unavailable`) : amount(ownerTotals.verifiedLinkedChakkarCredits)} />
          <SummaryCard label={t(`${root}.cards.commissionNet`)} value={amount(ownerTotals.commissionNet)} />
          <SummaryCard label={t(`${root}.cards.recordedVoucherAdjustments`)} value={amount(ownerTotals.recordedVoucherAdjustmentNet)} />
          <SummaryCard label={t(`${root}.cards.verifiedLinkedVoucherAdjustments`)} value={ownerTotals.verifiedLinkedVoucherAdjustmentNet === null ? t(`${root}.table.unavailable`) : amount(ownerTotals.verifiedLinkedVoucherAdjustmentNet)} />
          <SummaryCard label={t(`${root}.cards.otherAdjustmentNet`)} value={amount(ownerTotals.otherAdjustmentNet)} />
          <SummaryCard label={t(`${root}.cards.withdrawals`)} value={amount(ownerTotals.actualWithdrawals)} />
          <SummaryCard label={t(`${root}.cards.closing`)} value={amount(ownerTotals.closing)} />
          <SummaryCard label={t(`${root}.cards.payable`)} value={amount(ownerTotals.payable)} />
          <SummaryCard label={t(`${root}.cards.receivable`)} value={amount(ownerTotals.receivable)} />
          <SummaryCard label={t(`${root}.cards.unclassifiedMovement`)} value={ownerTotals.unclassifiedMovement === null ? t(`${root}.table.unavailable`) : amount(ownerTotals.unclassifiedMovement)} />
          <SummaryCard label={t(`${root}.cards.ownerReceipts`)} value={t(`${root}.table.unavailable`)} />
        </div>
        <p className="text-sm font-semibold text-slate-600">{t(`${root}.receiptsUnavailable`)} {t(`${root}.unlinkedActivityUnavailable`)} {t(`${root}.balanceConvention`)}</p>
      </section>
      <section className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="text-lg font-extrabold text-slate-900">{t(`${root}.sections.reconciliation`)}</h2>
        <p className="text-sm font-semibold text-slate-600">{t(`${root}.dateAxisNote`)} {t(`${root}.noDoubleCountNote`)} {t(`${root}.reconciliation.remainingDifferenceNote`)}</p>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <SummaryCard label={t(`${root}.reconciliation.earnings`)} value={amount(reconciliation?.settlementEarnings ?? vehicleTotals.netEarnings)} />
          <SummaryCard label={t(`${root}.reconciliation.recordedChakkarCredits`)} value={reconciliation ? amount(reconciliation.recordedChakkarCredits) : t(`${root}.table.unavailable`)} />
          <SummaryCard label={t(`${root}.reconciliation.verifiedLinkedChakkarCredits`)} value={reconciliation?.verifiedLinkedChakkarCredits === null || !reconciliation ? t(`${root}.table.unavailable`) : amount(reconciliation.verifiedLinkedChakkarCredits)} />
          <SummaryCard label={t(`${root}.reconciliation.differenceBeforeAdjustments`)} value={reconciliation?.differenceBeforeVoucherAdjustments === null || !reconciliation ? t(`${root}.table.unavailable`) : amount(reconciliation.differenceBeforeVoucherAdjustments)} />
          <SummaryCard label={t(`${root}.reconciliation.recordedVoucherAdjustments`)} value={reconciliation ? amount(reconciliation.recordedVoucherAdjustmentNet) : t(`${root}.table.unavailable`)} />
          <SummaryCard label={t(`${root}.reconciliation.verifiedLinkedVoucherAdjustments`)} value={reconciliation?.verifiedLinkedVoucherAdjustmentNet === null || !reconciliation ? t(`${root}.table.unavailable`) : amount(reconciliation.verifiedLinkedVoucherAdjustmentNet)} />
          <SummaryCard label={t(`${root}.reconciliation.remainingDifference`)} value={reconciliation?.remainingDifference === null || !reconciliation ? t(`${root}.table.unavailable`) : amount(reconciliation.remainingDifference)} />
        </div>
        {reconciliation?.chakkarSourceLinkIssue ? <p className="text-sm font-semibold text-amber-900">{t(sourceLinkIssueKey("chakkars", reconciliation.chakkarSourceLinkIssue))}</p> : null}
        {reconciliation?.voucherAdjustmentSourceLinkIssue ? <p className="text-sm font-semibold text-amber-900">{t(sourceLinkIssueKey("voucherAdjustments", reconciliation.voucherAdjustmentSourceLinkIssue))}</p> : null}
      </section>
      <section className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="text-lg font-extrabold text-slate-900">{t(`${root}.sections.owners`)}</h2>
        <div className="overflow-x-auto"><table className="min-w-[1900px] w-full text-sm"><thead><tr className="border-b bg-slate-50 text-start">{["owner", "vehicles", "opening", "movement", "recordedChakkarCredits", "verifiedLinkedChakkarCredits", "commissionNet", "recordedVoucherAdjustments", "verifiedLinkedVoucherAdjustments", "otherAdjustments", "withdrawals", "unclassifiedMovement", "closing", "payable", "receivable"].map((key) => <th key={key} className="p-3 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{ownerGroups.map((group) => <tr key={group.key} className="border-b"><td className="p-3 font-bold">{group.ownerName ?? t(`${root}.notRecorded`)}{group.ownerName ? null : <small className="block font-normal text-slate-500">{t(`${root}.table.vehicle`)} {group.vehicleIds.length === 1 ? vehicles.find((item) => item.id === group.vehicleIds[0])?.vehicle_no ?? "—" : ""}</small>}</td><td className="p-3">{group.vehicleCount}</td><td className="p-3">{amount(group.opening)}</td><td className="p-3">{amount(group.periodMovement)}</td><td className="p-3">{amount(group.recordedChakkarCredits)}</td><td className="p-3">{linkedAmountText(group.verifiedLinkedChakkarCredits, group.chakkarSourceLinkIssue, "chakkars", t)}</td><td className="p-3">{amount(group.commissionNet)}</td><td className="p-3">{amount(group.recordedVoucherAdjustmentNet)}</td><td className="p-3">{linkedAmountText(group.verifiedLinkedVoucherAdjustmentNet, group.voucherAdjustmentSourceLinkIssue, "voucherAdjustments", t)}</td><td className="p-3">{amount(group.otherAdjustmentNet)}</td><td className="p-3">{amount(group.actualWithdrawals)}</td><td className="p-3">{group.unclassifiedMovement === null ? t(`${root}.table.unavailable`) : amount(group.unclassifiedMovement)}</td><td className="p-3 font-bold">{amount(group.closing)}</td><td className="p-3 font-bold">{amount(group.payable)}</td><td className="p-3 font-bold">{amount(group.receivable)}</td></tr>)}</tbody></table></div>
      </section>
      <section className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="text-lg font-extrabold text-slate-900">{t(`${root}.sections.vehicles`)}</h2>
        <p className="text-sm font-semibold text-slate-600">{t(`${root}.settlementNetIsNotPayout`)}</p>
        {activeReport.length === 0 ? <p className="p-4 text-slate-600">{t(`${root}.noVehicles`)}</p> : <div className="overflow-x-auto"><table className="min-w-[2000px] w-full text-sm"><thead><tr className="border-b bg-slate-50">{["owner", "vehicle", "chakkars", "freight", "expenses", "earnings", "recordedChakkarCredits", "verifiedLinkedChakkarCredits", "commissionNet", "recordedVoucherAdjustments", "verifiedLinkedVoucherAdjustments", "otherAdjustments", "withdrawals", "unclassifiedMovement", "closing", "actions"].map((key) => <th key={key} className="p-3 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{activeReport.map((bundle) => { const close = Number(bundle.closing.summary.closing_balance); const movement = calculateOwnerMovementBreakdown(bundle); return <tr key={bundle.vehicle.id} className="border-b"><td className="p-3">{bundle.vehicle.owner_name?.trim() || t(`${root}.notRecorded`)}</td><td className="p-3 font-bold">{bundle.vehicle.vehicle_no || "—"}</td><td className="p-3">{text(bundle.monthly.summary.total_chakkar)}</td><td className="p-3">{amount(Number(bundle.monthly.summary.total_vehicle_freight))}</td><td className="p-3">{amount(Number(bundle.monthly.summary.total_expenses))}</td><td className="p-3 font-bold">{amount(Number(bundle.monthly.summary.vehicle_monthly_profit))}</td><td className="p-3">{amount(movement.recordedChakkarCredits)}</td><td className="p-3">{linkedAmountText(movement.verifiedLinkedChakkarCredits, movement.chakkarSourceLinkIssue, "chakkars", t)}</td><td className="p-3">{amount(movement.commissionNet)}</td><td className="p-3">{amount(movement.recordedVoucherAdjustmentNet)}</td><td className="p-3">{linkedAmountText(movement.verifiedLinkedVoucherAdjustmentNet, movement.voucherAdjustmentSourceLinkIssue, "voucherAdjustments", t)}</td><td className="p-3">{amount(movement.otherAdjustmentNet)}</td><td className="p-3">{amount(movement.actualWithdrawals)}</td><td className="p-3">{movement.unclassifiedMovement === null ? t(`${root}.table.unavailable`) : amount(movement.unclassifiedMovement)}</td><td className="p-3">{close > 0 ? <><strong>{amount(close)}</strong><span className="block text-xs">{t(`${root}.cards.payableLabel`)}</span></> : close < 0 ? <><strong>{amount(-close)}</strong><span className="block text-xs">{t(`${root}.cards.receivableLabel`)}</span></> : amount(0)}</td><td className="p-3"><button type="button" className="rounded border border-slate-300 px-3 py-2 font-bold" aria-expanded={expandedVehicle === bundle.vehicle.id} onClick={() => setExpandedVehicle((current) => current === bundle.vehicle.id ? null : bundle.vehicle.id)}>{expandedVehicle === bundle.vehicle.id ? t(`${root}.table.hideDetail`) : t(`${root}.table.viewDetail`)}</button></td></tr>; })}</tbody></table></div>}
      </section>
      {expandedVehicle ? activeReport.filter((bundle) => bundle.vehicle.id === expandedVehicle).map((bundle) => <VehicleDetail key={bundle.vehicle.id} bundle={bundle} t={t} language={language} />) : null}
      <p className="text-xs font-semibold text-slate-500">{t(`${root}.dateAxisNote`)}</p>
      {print.dialog}
    </> : null}
  </div>;

}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return <div className="min-w-0 rounded-xl border border-slate-200 bg-white p-4 shadow-sm"><p className="text-sm font-bold text-slate-600">{label}</p><p className="mt-1 break-words text-xl font-black text-slate-950">{value}</p></div>;
}

function VehicleDetail({ bundle, t, language }: { bundle: VehicleReportBundle; t: (key: string) => string; language: string }) {
  const root = "reports.vehicleOwnerSummary";
  const rows = bundle.monthly.chakkars;
  const transactions = bundle.statement.transactions;
  const breakdownFields = ["diesel", "workshop", "tyre", "oil", "driver", "other"] as const;
  const movement = calculateOwnerMovementBreakdown(bundle);
  const unavailable = t(`${root}.table.unavailable`);
  // The existing monthly RPC's original Chakkar rows are Bilty records and
  // may omit source_type; only the appended Manual Voucher rows set "manual".
  const labelSource = (value: unknown) => value === "manual" ? t(`${root}.source.manual`) : t(`${root}.source.bilty`);
  const transactionType = (value: unknown) => {
    const type = String(value ?? "");
    const result = t(`ownerGariAccount.transactionTypes.${type}`);
    return result === `ownerGariAccount.transactionTypes.${type}` ? type || "—" : result;
  };
  const movementRows: Array<[string, ReactNode]> = [
    ["recordedChakkarCredits", amount(movement.recordedChakkarCredits)],
    ["verifiedLinkedChakkarCredits", linkedAmountText(movement.verifiedLinkedChakkarCredits, movement.chakkarSourceLinkIssue, "chakkars", t)],
    ["recordedVoucherAdjustments", amount(movement.recordedVoucherAdjustmentNet)],
    ["verifiedLinkedVoucherAdjustments", linkedAmountText(movement.verifiedLinkedVoucherAdjustmentNet, movement.voucherAdjustmentSourceLinkIssue, "voucherAdjustments", t)],
    ["commissionNet", amount(movement.commissionNet)],
    ["withdrawalMovement", amount(movement.withdrawalMovement)],
    ["withdrawals", amount(movement.actualWithdrawals)],
    ["otherAdjustments", amount(movement.otherAdjustmentNet)],
    ["openingSeedMovement", amount(movement.openingSeedMovement)],
    ["unclassifiedMovement", movement.unclassifiedMovement === null ? unavailable : amount(movement.unclassifiedMovement)],
    ["movement", amount(movement.periodMovement)],
  ];
  return <section className="space-y-4 rounded-2xl border border-blue-200 bg-blue-50/50 p-4 shadow-sm" dir={language === "ur" ? "rtl" : "ltr"}>
    <h2 className="text-lg font-extrabold">{bundle.vehicle.vehicle_no || "—"} · {bundle.vehicle.owner_name?.trim() || "—"}</h2>
    <div className="space-y-2 rounded-xl bg-white p-3"><h3 className="font-extrabold">{t(`${root}.sections.movementBreakdown`)}</h3><div className="overflow-x-auto"><table className="min-w-[950px] w-full text-sm"><thead><tr className="border-b bg-slate-50">{["type", "signedAmount"].map((key) => <th key={key} className="p-2 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{movementRows.map(([key, value]) => <tr key={key} className="border-b"><td className="p-2">{t(`${root}.table.${key}`)}</td><td className="p-2 font-bold">{value}</td></tr>)}</tbody></table></div><p className="text-sm text-slate-600">{t(`${root}.movementBreakdownNote`)}</p></div>
    <div className="space-y-2 rounded-xl bg-white p-3"><h3 className="font-extrabold">{t(`${root}.sections.chakkars`)}</h3>{rows.length ? <div className="overflow-x-auto"><table className="min-w-[850px] w-full text-sm"><thead><tr className="border-b bg-slate-50">{["date", "source", "reference", "freight", "expenses", "net"].map((key) => <th key={key} className="p-2 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{rows.map((row, index) => { const values = savedChakkarValues(row); return <tr key={`${String(row.source_type)}:${String(row.settlement_id)}:${index}`} className="border-b"><td className="p-2">{text(row.chakkar_date)}</td><td className="p-2">{labelSource(row.source_type)}</td><td className="p-2">{text(row.voucher_no ?? row.movement_group_id)}</td><td className="p-2">{amountValue(values.freight)}</td><td className="p-2">{amountValue(values.expenses)}</td><td className="p-2 font-bold">{amountValue(values.net)}</td></tr>; })}</tbody></table></div> : <p className="text-sm">{t(`${root}.table.noDetails`)}</p>}</div>
    <div className="space-y-2 rounded-xl bg-white p-3"><h3 className="font-extrabold">{t(`${root}.sections.transactions`)}</h3>{transactions.length ? <div className="overflow-x-auto"><table className="min-w-[750px] w-full text-sm"><thead><tr className="border-b bg-slate-50">{["date", "type", "reference", "description", "signedAmount"].map((key) => <th key={key} className="p-2 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{transactions.map((row, index) => <tr key={`${text(row.transaction_id)}:${index}`} className="border-b"><td className="p-2">{text(row.transaction_date)}</td><td className="p-2">{transactionType(row.transaction_type)}</td><td className="p-2">{text(row.reference_no)}</td><td className="p-2">{text(row.description)}</td><td className="p-2 font-bold">{amountValue(row.signed_amount)}</td></tr>)}</tbody></table></div> : <p className="text-sm">{t(`${root}.table.noTransactions`)}</p>}</div>
    <div className="space-y-2 rounded-xl bg-white p-3"><h3 className="font-extrabold">{t(`${root}.sections.expenses`)}</h3><p className="text-sm text-slate-600">{t(`${root}.expenseBreakdownNote`)}</p>{rows.length ? <div className="overflow-x-auto"><table className="min-w-[1150px] w-full text-sm"><thead><tr className="border-b bg-slate-50">{["date", "reference", ...breakdownFields, "unallocated", "breakdownStatus", "total"].map((key) => <th key={key} className="p-2 text-start">{t(`${root}.table.${key}`)}</th>)}</tr></thead><tbody>{rows.map((row, index) => { const values = savedChakkarValues(row); const breakdown = reconcileExpenseBreakdown(row, values.expenses); return <tr key={`${String(row.settlement_id)}:expense:${index}`} className="border-b"><td className="p-2">{text(row.chakkar_date)}</td><td className="p-2">{text(row.voucher_no ?? row.movement_group_id)}</td>{breakdownFields.map((field) => <td key={field} className="p-2">{breakdown.categories ? amount(breakdown.categories[field]) : unavailable}</td>)}<td className="p-2">{breakdown.unallocated === null ? unavailable : amount(breakdown.unallocated)}</td><td className="p-2">{t(`${root}.breakdown.${breakdown.status}`)}</td><td className="p-2 font-bold">{amountValue(values.expenses)}</td></tr>; })}</tbody></table></div> : <p className="text-sm">{t(`${root}.table.noDetails`)}</p>}</div>
  </section>;
}
