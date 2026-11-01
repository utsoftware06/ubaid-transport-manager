"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { ArrowDownLeft, ArrowUpRight, Banknote, BriefcaseBusiness, ChevronLeft, ChevronRight, CircleDollarSign, Clock3, ExternalLink, Eye, HandCoins, Pencil, Printer, RefreshCw, RotateCcw, Search, UsersRound, WalletCards } from "lucide-react";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { isUserRole, USER_ROLES, type UserRole } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import {
  ensureAddaFinanceCategories,
  getAddaAccountEntryMetadata,
  getAddaEmployeeLoanReceivable,
  getAddaFinanceSummary,
  listAddaAccountEntries,
  listAddaEmployees,
  listAddaFinanceSettlements,
  listManualExpenseCategories,
  mapAddaFinanceError,
  postAddaExpense,
  postAddaOtherIncome,
  reverseAddaFinanceEntry,
  reverseAddaFinanceSettlement,
  settleAddaAccountEntry,
  updateAddaAccountEntryMetadata,
} from "./api";
import { openAddaAccountPrintWindow, renderAddaAccountPrintWindow, type PrintLabels } from "./AddaAccountPrint";
import LedgerStatementPrintButton, { translateLedgerPrint } from "@/components/print/LedgerStatementPrint";
import { addaAccountPrintPresentation, addaAccountStatementPrintPresentation } from "./addaAccountPrintPresentation";
import {
  AddaAccountEntryMetadataDialog,
  AddaFinanceActiveSettlementsDialog,
  AddaFinanceHistoryDialog,
  AddaFinanceReversalDialog,
  AddaFinanceSettlementDialog,
  AddaFinanceSourceDialog,
  type MetadataFormValue,
  type SourceFormValue,
} from "./AddaAccountDialogs";
import type {
  AddaAccountCategory,
  AddaAccountEmployee,
  AddaAccountEntry,
  AddaFinanceSettlement,
  AddaFinanceSummary,
} from "./types";
import VehicleCommissionSection from "./VehicleCommissionSection";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type AddaOption = { id: string; name: string };
type Profile = { role: UserRole; adda_id: string | null; is_active: boolean };
type Period = "today" | "thisWeek" | "thisMonth" | "custom";
type SourceModal = "expense" | "income" | null;
type ReversalTarget =
  | { kind: "entry"; addaId: string; accountEntryId: string; entry: AddaAccountEntry }
  | { kind: "settlement"; addaId: string; accountEntryId: string; settlementId: string; entry: AddaAccountEntry; settlement: AddaFinanceSettlement };
const pageSize = 25;
const control = "h-10 w-full min-w-0 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const outlineButton = "inline-flex h-10 items-center justify-center gap-2 rounded-lg border border-blue-200 bg-white px-3 text-sm font-bold text-blue-800 shadow-sm transition hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-50";
type PreparedPrint = { entry: AddaAccountEntry; history: AddaFinanceSettlement[]; statusLabel: string; labels: PrintLabels; requestId: number; scope: string };

function localIsoDate(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function currentMonthStart() {
  const now = new Date();
  return localIsoDate(new Date(now.getFullYear(), now.getMonth(), 1));
}

function today() {
  return localIsoDate(new Date());
}

function datesForPeriod(period: Exclude<Period, "custom">) {
  const now = new Date();
  const end = localIsoDate(now);
  if (period === "today") return { from: end, to: end };
  if (period === "thisMonth") return { from: localIsoDate(new Date(now.getFullYear(), now.getMonth(), 1)), to: end };
  const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const day = weekStart.getDay();
  weekStart.setDate(weekStart.getDate() - ((day + 6) % 7));
  return { from: localIsoDate(weekStart), to: end };
}

function money(value: number) {
  return `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function statusTranslation(entry: AddaAccountEntry) {
  if (entry.is_reversed) return "reversed";
  if (entry.is_reversal) return "reversal";
  if (entry.source_type === "issued_parchi_financing_commission") return "earned";
  if (entry.source_type === "bilty_margin") {
    if (entry.realization_status === "realized") return "realized";
    if (entry.realization_status === "partial") return "partial";
    if (entry.realization_status === "pending") return "marginPending";
    return "earned";
  }
  if (entry.source_type === "bilty_loss") return "recognizedLoss";
  if (entry.source_type === "employee_salary_generated") return "employeeManaged";
  if (entry.entry_status === "settled") return "paid";
  if (entry.entry_status === "partial") return "partial";
  return "unpaid";
}

function statusStyle(status: string) {
  if (status === "paid") return "border-emerald-200 bg-emerald-50 text-emerald-800";
  if (status === "partial") return "border-amber-200 bg-amber-50 text-amber-800";
  if (status === "marginPending") return "border-amber-200 bg-amber-50 text-amber-800";
  if (status === "realized") return "border-emerald-200 bg-emerald-50 text-emerald-800";
  if (status === "earned") return "border-emerald-200 bg-emerald-50 text-emerald-800";
  if (status === "recognizedLoss") return "border-rose-200 bg-rose-50 text-rose-800";
  if (status === "employeeManaged") return "border-blue-200 bg-blue-50 text-blue-800";
  if (status === "reversed" || status === "reversal") return "border-slate-200 bg-slate-100 text-slate-700";
  return "border-rose-200 bg-rose-50 text-rose-800";
}

function getBackendErrorDetails(error: unknown) {
  const value = error && typeof error === "object" ? error as Record<string, unknown> : {};
  return {
    message: typeof value.message === "string" ? value.message : error instanceof Error ? error.message : String(error ?? ""),
    details: value.details ?? null,
    hint: value.hint ?? null,
    code: value.code ?? null,
  };
}

export default function AddaAccount() {
  const { t, dir, language } = useLanguage();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [contextLoading, setContextLoading] = useState(true);
  const [contextError, setContextError] = useState("");
  const [categories, setCategories] = useState<AddaAccountCategory[]>([]);
  const [employees, setEmployees] = useState<AddaAccountEmployee[]>([]);
  const [summary, setSummary] = useState<AddaFinanceSummary | null>(null);
  const [employeeLoanReceivable, setEmployeeLoanReceivable] = useState<number | null>(null);
  const [entries, setEntries] = useState<AddaAccountEntry[]>([]);
  const [loadingReference, setLoadingReference] = useState(true);
  const [loadingEntries, setLoadingEntries] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [notice, setNotice] = useState("");
  const [period, setPeriod] = useState<Period>("thisMonth");
  const [fromDate, setFromDate] = useState(currentMonthStart);
  const [toDate, setToDate] = useState(today);
  const [kindFilter, setKindFilter] = useState<"all" | "income" | "expense">("all");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [employeeFilter, setEmployeeFilter] = useState("");
  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [page, setPage] = useState(0);
  const [hasNext, setHasNext] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [sourceModal, setSourceModal] = useState<SourceModal>(null);
  const [isPreparing, setIsPreparing] = useState(false);
  const [activeEntry, setActiveEntry] = useState<AddaAccountEntry | null>(null);
  const [settlements, setSettlements] = useState<AddaFinanceSettlement[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [settlementModal, setSettlementModal] = useState(false);
  const [reversalTarget, setReversalTarget] = useState<ReversalTarget | null>(null);
  const [activeSettlementsEntry, setActiveSettlementsEntry] = useState<AddaAccountEntry | null>(null);
  const [metadataTarget, setMetadataTarget] = useState<AddaAccountEntry | null>(null);
  const [printingEntryId, setPrintingEntryId] = useState<string | null>(null);
  const [printingEntryScope, setPrintingEntryScope] = useState("");
  const [preparedPrint, setPreparedPrint] = useState<PreparedPrint | null>(null);
  const [preparedStatementPrint, setPreparedStatementPrint] = useState<{ addaId: string; rows: AddaAccountEntry[]; summary: AddaFinanceSummary; employeeLoanReceivable: number | null; from: string | null; to: string | null; requestId: number; scopeKey: string } | null>(null);
  const printRequestId = useRef(0);
  const contextRequest = useRef(0);
  const referenceRequest = useRef(0);
  const dataRequest = useRef(0);
  const historyRequest = useRef(0);

  const isSuperAdmin = profile?.role === USER_ROLES.superAdmin;
  const canManage = profile?.role === USER_ROLES.superAdmin || profile?.role === USER_ROLES.addaAdmin;
  const scope = isSuperAdmin ? selectedAddaId : profileAddaId ?? "";
  const printScopeRef = useRef(scope);
  const statementScopeKey = [scope, fromDate, toDate, kindFilter, categoryFilter, employeeFilter, debouncedSearch].join("|");
  const statementScopeRef = useRef(statementScopeKey);
  const statementPrintRequest = useRef(0);
  const displayEntry = activeEntry ? entries.find((entry) => entry.id === activeEntry.id) ?? activeEntry : null;

  useLayoutEffect(() => {
    printScopeRef.current = scope;
    printRequestId.current += 1;
  }, [scope]);

  useLayoutEffect(() => {
    statementScopeRef.current = statementScopeKey;
    statementPrintRequest.current += 1;
  }, [statementScopeKey]);

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedSearch(search.trim()), 250);
    return () => window.clearTimeout(timer);
  }, [search]);

  const loadContext = useCallback(async () => {
    const request = ++contextRequest.current;
    setContextLoading(true); setContextError(""); setProfile(null); setProfileAddaId(null); setSelectedAddaId(""); setAddas([]);
    try {
      const auth = await supabase.auth.getUser();
      if (auth.error) throw auth.error;
      if (!auth.data.user) throw new Error("AUTHENTICATION_REQUIRED");
      const profileResponse = await supabase.from("profiles").select("role, adda_id, is_active").eq("id", auth.data.user.id).maybeSingle();
      if (profileResponse.error) throw profileResponse.error;
      const row = profileResponse.data as { role: string | null; adda_id: string | null; is_active: boolean | null } | null;
      if (!row || row.is_active !== true || !isUserRole(row.role)) throw new Error("An active supported profile is required.");
      let options: AddaOption[] = [];
      if (row.role === USER_ROLES.superAdmin) {
        const addaResponse = await supabase.from("addas").select("id, name").order("name");
        if (addaResponse.error) throw addaResponse.error;
        options = (addaResponse.data ?? []).map((item) => ({ id: String(item.id), name: String(item.name) }));
      } else if (!row.adda_id) {
        throw new Error("The profile has no assigned Adda.");
      }
      if (request !== contextRequest.current) return;
      setLoadingReference(true);
      setLoadingEntries(true);
      setProfile({ role: row.role, adda_id: row.adda_id, is_active: row.is_active });
      setProfileAddaId(row.role === USER_ROLES.superAdmin ? null : row.adda_id);
      printScopeRef.current = row.role === USER_ROLES.superAdmin ? "" : row.adda_id ?? "";
      setAddas(options);
    } catch (error) {
      if (request !== contextRequest.current) return;
      console.error("Adda Account access check failed", error);
      setContextError(mapAddaFinanceError(error, "Adda access could not be verified."));
    } finally {
      if (request === contextRequest.current) setContextLoading(false);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => { void loadContext(); }, 0);
    return () => { window.clearTimeout(timer); contextRequest.current += 1; };
  }, [loadContext]);

  useEffect(() => {
    const request = ++referenceRequest.current;
    if (!scope) {
      return;
    }
    let mounted = true;
    void Promise.all([listManualExpenseCategories(scope), listAddaEmployees(scope)])
      .then(([loadedCategories, loadedEmployees]) => {
        if (!mounted || request !== referenceRequest.current) return;
        setCategories(loadedCategories); setEmployees(loadedEmployees);
      })
      .catch((error: unknown) => {
        if (!mounted || request !== referenceRequest.current) return;
        console.error("Adda Account reference data load failed", error);
        setLoadError(mapAddaFinanceError(error, t("addaAccount.loadError")));
      })
      .finally(() => { if (mounted && request === referenceRequest.current) setLoadingReference(false); });
    return () => { mounted = false; };
  }, [scope, refreshKey, t]);

  useEffect(() => {
    const request = ++dataRequest.current;
    if (!scope) {
      return;
    }
    let mounted = true;
    void Promise.all([
      getAddaFinanceSummary(scope, fromDate || null, toDate || null),
      getAddaEmployeeLoanReceivable(scope),
      listAddaAccountEntries(scope, {
        from: fromDate || null,
        to: toDate || null,
        kind: kindFilter === "all" ? null : kindFilter,
        categoryId: categoryFilter || null,
        employeeId: employeeFilter || null,
        search: debouncedSearch || null,
        limit: pageSize + 1,
        offset: page * pageSize,
      }),
    ]).then(([loadedSummary, loadedLoanReceivable, loadedEntries]) => {
      if (!mounted || request !== dataRequest.current) return;
      setSummary(loadedSummary);
      setEmployeeLoanReceivable(loadedLoanReceivable);
      setHasNext(loadedEntries.length > pageSize);
      setEntries(loadedEntries.slice(0, pageSize));
    }).catch((error: unknown) => {
      if (!mounted || request !== dataRequest.current) return;
      console.error("Adda Account data load failed", error);
      setLoadError(mapAddaFinanceError(error, t("addaAccount.loadError")));
      setSummary(null); setEmployeeLoanReceivable(null); setEntries([]); setHasNext(false);
    }).finally(() => { if (mounted && request === dataRequest.current) setLoadingEntries(false); });
    return () => { mounted = false; };
  }, [scope, fromDate, toDate, kindFilter, categoryFilter, employeeFilter, debouncedSearch, page, refreshKey, t]);

  const activeEntryId = displayEntry?.id;
  useEffect(() => {
    const request = ++historyRequest.current;
    if (!scope || !activeEntryId) return;
    if (["bilty_margin", "bilty_loss", "employee_salary_generated", "issued_parchi_financing_commission"].includes(activeEntry?.source_type ?? "")) return;
    let mounted = true;
    void listAddaFinanceSettlements(scope, activeEntryId)
      .then((rows) => { if (mounted && request === historyRequest.current) setSettlements(rows); })
      .catch((error: unknown) => {
        if (!mounted || request !== historyRequest.current) return;
        console.error("Adda settlement history load failed", error);
        setActionError(mapAddaFinanceError(error, t("addaAccount.loadError")));
        setSettlements([]);
      })
      .finally(() => { if (mounted && request === historyRequest.current) setHistoryLoading(false); });
    return () => { mounted = false; };
  }, [scope, activeEntryId, activeEntry?.source_type, refreshKey, t]);

  const setPreset = (next: Period) => {
    setLoadingEntries(true); setLoadError("");
    setPeriod(next);
    setPage(0);
    if (next !== "custom") {
      const dates = datesForPeriod(next);
      setFromDate(dates.from); setToDate(dates.to);
    }
  };

  const clearFilters = () => {
    setLoadingEntries(true); setLoadError("");
    setPeriod("thisMonth");
    const dates = datesForPeriod("thisMonth");
    setFromDate(dates.from); setToDate(dates.to);
    setKindFilter("all"); setCategoryFilter(""); setEmployeeFilter(""); setSearch(""); setDebouncedSearch(""); setPage(0);
  };

  const refreshAll = () => {
    setLoadingEntries(true); setLoadingReference(true); setLoadError("");
    setRefreshKey((key) => key + 1);
  };

  async function prepareExpenseCategories() {
    if (!scope || !canManage || isPreparing) return;
    setIsPreparing(true); setActionError(""); setNotice("");
    try {
      await ensureAddaFinanceCategories(scope);
      const values = await listManualExpenseCategories(scope);
      setCategories(values);
      if (values.length) {
        setNotice(t("addaAccount.categoryReady"));
        setSourceModal("expense");
      } else {
        setActionError(t("addaAccount.messages.categoriesFailed"));
      }
    } catch (error) {
      console.error("Adda Finance category setup failed", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.messages.categoriesFailed")));
    } finally { setIsPreparing(false); }
  }

  async function submitSource(value: SourceFormValue) {
    if (!scope) return false;
    setActionError("");
    try {
      if (sourceModal === "expense") {
        await postAddaExpense({ addaId: scope, expenseDate: value.date, categoryId: value.categoryId,
          amount: value.amount, paidAmount: value.paidAmount, paymentMethod: value.paymentMethod,
          employeeId: value.employeeId, referenceNo: value.referenceNo, description: value.description,
          remarks: value.remarks, requestId: value.requestId });
      } else {
        await postAddaOtherIncome({ addaId: scope, incomeDate: value.date, amount: value.amount,
          receivedAmount: value.receivedAmount, paymentMethod: value.paymentMethod,
          referenceNo: value.referenceNo, description: value.description, remarks: value.remarks,
          requestId: value.requestId });
      }
      setSourceModal(null); setNotice(t("addaAccount.messages.saved")); setPage(0); setLoadingEntries(true); setLoadingReference(true); setRefreshKey((key) => key + 1);
      return true;
    } catch (error) {
      console.error("Adda Finance source posting failed", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.messages.requestFailed")));
      return false;
    }
  }

  async function submitSettlement(value: { date: string; amount: number; method: string; referenceNo: string | null; remarks: string | null; requestId: string }) {
    if (!scope || !displayEntry) return false;
    setActionError("");
    try {
      await settleAddaAccountEntry({ addaId: scope, accountEntryId: displayEntry.id,
        paymentDate: value.date, amount: value.amount, paymentMethod: value.method,
        requestId: value.requestId, referenceNo: value.referenceNo, remarks: value.remarks });
      setSettlementModal(false); setNotice(t("addaAccount.messages.settled")); setHistoryLoading(true); setLoadingEntries(true); setLoadingReference(true); setRefreshKey((key) => key + 1);
      return true;
    } catch (error) {
      console.error("Adda Finance settlement failed", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.messages.requestFailed")));
      return false;
    }
  }

  async function submitReversal(value: { date: string; reason: string; requestId: string }) {
    if (!scope || !reversalTarget) return false;
    setActionError("");
    try {
      if (reversalTarget.kind === "settlement") {
        if (reversalTarget.addaId !== scope
          || reversalTarget.settlement.id !== reversalTarget.settlementId
          || reversalTarget.settlement.account_entry_id !== reversalTarget.accountEntryId
          || reversalTarget.settlement.event_type !== "settlement"
          || reversalTarget.settlement.reverses_settlement_id !== null) {
          throw new Error("ADDA_FINANCE_SETTLEMENT_REVERSAL_TARGET_INVALID");
        }
        await reverseAddaFinanceSettlement({ addaId: reversalTarget.addaId, settlementId: reversalTarget.settlementId,
          reversalDate: value.date, reason: value.reason, requestId: value.requestId });
      } else {
        if (reversalTarget.addaId !== scope || reversalTarget.entry.net_settled_amount !== 0) {
          throw new Error(reversalTarget.entry.net_settled_amount > 0
            ? "ADDA_FINANCE_ACTIVE_SETTLEMENTS_MUST_BE_REVERSED_FIRST"
            : "ADDA_FINANCE_SETTLEMENT_EVIDENCE_INCONSISTENT");
        }
        await reverseAddaFinanceEntry({ addaId: reversalTarget.addaId, accountEntryId: reversalTarget.accountEntryId,
          reversalDate: value.date, reason: value.reason, requestId: value.requestId });
      }
      setReversalTarget(null); setNotice(t("addaAccount.messages.reversed")); setHistoryLoading(true); setLoadingEntries(true); setLoadingReference(true); setRefreshKey((key) => key + 1);
      return true;
    } catch (error) {
      const backendError = getBackendErrorDetails(error);
      console.error(reversalTarget.kind === "settlement" ? "Adda settlement reversal RPC failed" : "Adda entry reversal RPC failed", backendError);
      setActionError(mapAddaFinanceError(error, t("addaAccount.messages.requestFailed")));
      return false;
    }
  }

  async function submitMetadata(value: MetadataFormValue) {
    if (!scope || !metadataTarget) return false;
    setActionError("");
    try {
      await updateAddaAccountEntryMetadata({
        addaId: scope,
        accountEntryId: metadataTarget.id,
        referenceNo: value.referenceNo,
        description: value.description,
        remarks: value.remarks,
        requestId: value.requestId,
      });
      setMetadataTarget(null);
      setNotice(t("addaAccount.metadata.updated"));
      setLoadingEntries(true);
      setRefreshKey((key) => key + 1);
      return true;
    } catch (error) {
      console.error("Adda Finance metadata update failed", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.messages.requestFailed")));
      return false;
    }
  }

  async function printEntry(entry: AddaAccountEntry, statusLabel: string) {
    if (!scope || (printingEntryId && printingEntryScope === scope)) return;
    if (entry.adda_id !== scope) { setActionError(t("addaAccount.messages.tenantMismatch")); return; }
    const requestScope = scope;
    const requestId = ++printRequestId.current;
    setPrintingEntryId(entry.id);
    setPrintingEntryScope(requestScope);
    setActionError("");
    try {
      const [history, metadataRows] = await Promise.all([
        ["bilty_margin", "bilty_loss", "employee_salary_generated", "issued_parchi_financing_commission"].includes(entry.source_type)
          ? Promise.resolve([])
          : listAddaFinanceSettlements(scope, entry.id),
        getAddaAccountEntryMetadata(scope, [entry.id]),
      ]);
      if (requestId !== printRequestId.current || printScopeRef.current !== requestScope) return;
      const metadata = metadataRows[0];
      const printableEntry = metadata ? { ...entry, ...metadata } : entry;
      if (printableEntry.source_type === "issued_parchi_financing_commission") {
        printableEntry.description = t("addaAccount.ledger.issuedFinance");
      }
      if (printableEntry.adda_id !== requestScope) throw new Error("The selected entry changed Adda context.");
      const labels: PrintLabels = {
          expenseTitle: t("addaAccount.print.expenseTitle"),
          incomeTitle: t("addaAccount.print.incomeTitle"),
          entryType: t("addaAccount.print.entryType"),
          date: t("addaAccount.print.date"),
          category: t("addaAccount.print.category"),
          referenceNo: t("addaAccount.print.referenceNo"),
          description: t("addaAccount.print.description"),
          remarks: t("addaAccount.print.remarks"),
          totalAmount: t("addaAccount.print.totalAmount"),
          settledAmount: t("addaAccount.print.settledAmount"),
          pendingAmount: t("addaAccount.print.pendingAmount"),
          status: t("addaAccount.print.status"),
          paymentHistory: t("addaAccount.print.paymentHistory"),
          paymentDate: t("addaAccount.print.paymentDate"),
          event: t("addaAccount.print.event"),
          paymentMethod: t("addaAccount.print.paymentMethod"),
          cashbookDirection: t("addaAccount.print.cashbookDirection"),
          amount: t("addaAccount.print.amount"),
          settlement: t("addaAccount.settlement.settlement"),
          reversal: t("addaAccount.settlement.reversal"),
          createdAt: t("addaAccount.print.createdAt"),
          printedAt: t("addaAccount.print.printedAt"),
          generatedBy: t("addaAccount.print.generatedBy"),
          noPayments: t("addaAccount.print.noPayments"),
          earnedAmount: t("addaAccount.print.earnedAmount"),
          realizedAmount: t("addaAccount.print.realizedAmount"),
          marginPendingAmount: t("addaAccount.print.marginPendingAmount"),
          receivedBasisAmount: t("addaAccount.print.receivedBasisAmount"),
          marginReceiptNote: t("addaAccount.print.marginReceiptNote"),
          sourceManagedNote: t("addaAccount.print.sourceManagedNote"),
          issuedFinanceNoCash: t("addaAccount.ledger.issuedFinanceNoCash"),
      };
      setPreparedPrint({ entry: printableEntry, history, statusLabel, labels, requestId, scope: requestScope });
    } catch (error) {
      if (requestId !== printRequestId.current || printScopeRef.current !== requestScope) return;
      console.error("Adda Finance voucher could not be prepared", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.loadError")));
    } finally {
      if (requestId === printRequestId.current) {
        setPrintingEntryId(null);
        setPrintingEntryScope("");
      }
    }
  }

  async function prepareFullStatementPrint() {
    if (!scope || !summary || loadingEntries) return;
    const requestScope = scope;
    const requestKey = statementScopeKey;
    const requestId = ++statementPrintRequest.current;
    const allRows: AddaAccountEntry[] = [];
    const chunkSize = 100;
    setPreparedStatementPrint(null);
    setActionError("");
    try {
      for (let offset = 0; offset < 100000; offset += chunkSize) {
        if (statementScopeRef.current !== requestKey || printScopeRef.current !== requestScope || requestId !== statementPrintRequest.current) return;
        const pageRows = await listAddaAccountEntries(requestScope, {
          from: fromDate || null,
          to: toDate || null,
          kind: kindFilter === "all" ? null : kindFilter,
          categoryId: categoryFilter || null,
          employeeId: employeeFilter || null,
          search: debouncedSearch || null,
          limit: chunkSize,
          offset,
        });
        if (pageRows.some((row) => row.adda_id !== requestScope)) throw new Error("ADDA_AUTHORIZATION_MISMATCH");
        allRows.push(...pageRows);
        if (pageRows.length < chunkSize) break;
        if (offset + chunkSize >= 100000) throw new Error("STATEMENT_ROW_LIMIT_REACHED");
      }
      if (statementScopeRef.current !== requestKey || printScopeRef.current !== requestScope || requestId !== statementPrintRequest.current) return;
      setPreparedStatementPrint({ addaId: requestScope, rows: allRows, summary, employeeLoanReceivable, from: fromDate || null, to: toDate || null, requestId, scopeKey: requestKey });
    } catch (error) {
      if (statementScopeRef.current !== requestKey || requestId !== statementPrintRequest.current) return;
      console.error("Adda Account full statement could not be prepared", error);
      setActionError(mapAddaFinanceError(error, t("addaAccount.loadError")));
    }
  }

  function openHistory(entry: AddaAccountEntry) {
    setActiveSettlementsEntry(null);
    setReversalTarget(null);
    setActiveEntry(entry); setActionError(""); setSettlements([]);
    setHistoryLoading(!["bilty_margin", "bilty_loss", "employee_salary_generated", "issued_parchi_financing_commission"].includes(entry.source_type));
  }

  function requestEntryReversal(entry: AddaAccountEntry) {
    if (!canManage || entry.is_reversal || entry.is_reversed
      || !["manual_adda_expense", "manual_other_income"].includes(entry.source_type)) return;
    setActionError("");
    setActiveSettlementsEntry(null);
    if (entry.net_settled_amount > 0) {
      setActiveSettlementsEntry(entry);
      return;
    }
    if (!scope) return;
    setReversalTarget({ kind: "entry", addaId: scope, accountEntryId: entry.id, entry });
  }

  function requestSettlementReversal(entry: AddaAccountEntry, settlement: AddaFinanceSettlement) {
    if (!canManage || !scope || settlement.event_type !== "settlement"
      || settlement.reverses_settlement_id !== null || settlement.account_entry_id !== entry.id) {
      setActionError(t("addaAccount.messages.invalidSettlementTarget"));
      return;
    }
    setActionError("");
    setActiveSettlementsEntry(null);
    setReversalTarget({
      kind: "settlement",
      addaId: scope,
      accountEntryId: entry.id,
      settlementId: settlement.id,
      entry,
      settlement,
    });
  }

  return <main dir={dir} className="ut-module-page mx-auto max-w-[1600px] space-y-4 px-3 pb-8 text-slate-950 sm:px-5 lg:space-y-5">
    <header className="flex flex-col justify-between gap-4 rounded-2xl border border-blue-100 bg-white p-4 shadow-sm sm:p-5 lg:flex-row lg:items-center">
      <ModulePageHeading icon="cashbook" accent="green" title={t("addaAccount.title")} description={t("addaAccount.description")} />
      <div className="flex flex-wrap gap-2">
        {canManage && scope && <>
          <button type="button" disabled={isPreparing || loadingReference} onClick={() => void prepareExpenseCategories()} className={outlineButton}>
            {isPreparing ? t("addaAccount.preparingCategories") : categories.length ? t("addaAccount.addExpense") : t("addaAccount.prepareCategories")}
          </button>
          <button type="button" disabled={!summary || loadingEntries} onClick={() => setSourceModal("income")} className="inline-flex h-10 items-center justify-center gap-2 rounded-lg bg-emerald-600 px-3 text-sm font-bold text-white shadow-sm hover:bg-emerald-700 disabled:opacity-50"><CircleDollarSign size={17} />{t("addaAccount.addIncome")}</button>
        </>}
        {scope && <button type="button" disabled={loadingEntries || loadingReference} onClick={refreshAll} className={outlineButton}><RefreshCw size={16} />{t("addaAccount.refresh")}</button>}
      </div>
    </header>

    {contextLoading && <p role="status" className="rounded-xl border border-blue-100 bg-white p-5 font-semibold text-slate-700">{t("addaAccount.accessLoading")}</p>}
    {contextError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 font-semibold text-rose-800">{contextError}<button type="button" onClick={() => void loadContext()} className="ms-3 rounded-lg border border-rose-300 bg-white px-3 py-1.5 text-sm">{t("addaAccount.retry")}</button></div>}
    {isSuperAdmin && <section className="rounded-2xl border border-blue-100 bg-white p-4 shadow-sm sm:p-5"><label className="block max-w-xl text-sm font-bold text-slate-700" htmlFor="adda-finance-scope">{t("addaAccount.selectAdda")}<select id="adda-finance-scope" className={`${control} mt-2`} value={selectedAddaId} onChange={(event) => { printScopeRef.current = event.target.value; printRequestId.current += 1; setPreparedPrint(null); setPrintingEntryId(null); setPrintingEntryScope(""); setSelectedAddaId(event.target.value); setPage(0); setCategories([]); setEmployees([]); setSummary(null); setEmployeeLoanReceivable(null); setEntries([]); setHasNext(false); setActiveEntry(null); setActiveSettlementsEntry(null); setSettlements([]); setSourceModal(null); setMetadataTarget(null); setReversalTarget(null); setSettlementModal(false); setActionError(""); setNotice(""); setLoadingReference(true); setLoadingEntries(true); setHistoryLoading(false); setLoadError(""); }}><option value="">{t("addaAccount.selectAdda")}</option>{addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}</select></label>{!addas.length && !contextLoading && <p className="mt-2 text-sm text-slate-500">{t("addaAccount.noAddas")}</p>}</section>}
    {profile && !scope && <p role="status" className="rounded-xl border border-blue-200 bg-blue-50 p-5 font-semibold text-blue-900">{t("addaAccount.noAddaSelected")}</p>}
    {scope && <>
      {!canManage && <p role="status" className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm font-semibold text-slate-700">{t("addaAccount.readOnly")}</p>}
      {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-900">{notice}</p>}
      {actionError && <p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">{actionError}<button type="button" className="ms-3 underline" onClick={() => setActionError("")}>{t("common.actions.close")}</button></p>}
      {loadError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 font-semibold text-rose-800">{loadError}<button type="button" className="ms-3 underline" onClick={refreshAll}>{t("addaAccount.retry")}</button></div>}

      <section aria-label="Adda Finance summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
        {[
          { key: "totalIncome", value: summary?.total_income, icon: ArrowDownLeft, tone: "border-emerald-200 bg-emerald-50/70", tile: "bg-emerald-600" },
          { key: "biltyMarginIncome", value: summary?.bilty_margin_income, icon: BriefcaseBusiness, tone: "border-violet-200 bg-violet-50/70", tile: "bg-violet-600" },
          { key: "vehicleCommission", value: summary?.vehicle_commission_effective, icon: CircleDollarSign, tone: "border-indigo-200 bg-indigo-50/70", tile: "bg-indigo-600" },
          { key: "issuedFreightFinanceCommission", value: summary?.issued_freight_financing_commission_income, icon: CircleDollarSign, tone: "border-fuchsia-200 bg-fuchsia-50/70", tile: "bg-fuchsia-600" },
          { key: "biltyMarginRealized", value: summary?.bilty_margin_realized, icon: CircleDollarSign, tone: "border-emerald-200 bg-emerald-50/70", tile: "bg-emerald-600" },
          { key: "biltyMarginPending", value: summary?.bilty_margin_pending, icon: Clock3, tone: "border-amber-200 bg-amber-50/70", tile: "bg-amber-600" },
          { key: "otherIncome", value: summary?.other_income, icon: BriefcaseBusiness, tone: "border-violet-200 bg-violet-50/70", tile: "bg-violet-600" },
          { key: "totalExpense", value: summary?.total_expense, icon: ArrowUpRight, tone: "border-rose-200 bg-rose-50/70", tile: "bg-rose-600" },
          { key: "biltyLossExpense", value: summary?.bilty_loss_expense, icon: ArrowUpRight, tone: "border-orange-200 bg-orange-50/70", tile: "bg-orange-600" },
          { key: "employeeExpense", value: summary?.employee_expense, icon: UsersRound, tone: "border-cyan-200 bg-cyan-50/70", tile: "bg-cyan-600" },
          { key: "employeeLoanReceivable", value: employeeLoanReceivable ?? undefined, icon: HandCoins, tone: "border-amber-200 bg-amber-50/70", tile: "bg-amber-600" },
          { key: "netProfit", value: summary?.net_profit, icon: WalletCards, tone: "border-blue-200 bg-blue-50/70", tile: "bg-blue-600" },
          { key: "pendingIncome", value: summary?.pending_income, icon: Banknote, tone: "border-amber-200 bg-amber-50/70", tile: "bg-amber-600" },
          { key: "pendingExpense", value: summary?.pending_expense, icon: HandCoins, tone: "border-orange-200 bg-orange-50/70", tile: "bg-orange-600" },
        ].map((card) => { const Icon = card.icon; return <article key={card.key} className={`relative overflow-hidden rounded-2xl border p-4 shadow-sm ${card.tone}`}>
          <span className={`flex h-10 w-10 items-center justify-center rounded-xl text-white shadow-sm ${card.tile}`}><Icon size={20} /></span>
          <p className="mt-3 text-xs font-bold uppercase tracking-wide text-slate-600">{t(`addaAccount.summary.${card.key}`)}</p>
          <p className="mt-1 truncate text-2xl font-extrabold text-slate-900" dir="ltr">{summary ? money(card.value ?? 0) : "—"}</p>
          {loadingEntries && <span className="absolute right-3 top-3 h-2 w-2 animate-pulse rounded-full bg-blue-500" aria-label={t("common.loading")} />}
        </article>; })}
      </section>

      <VehicleCommissionSection
        addaId={scope}
        canManage={canManage}
        reloadKey={refreshKey}
        onUpdated={refreshAll}
        t={t}
      />

      <section className="rounded-2xl border border-blue-100 bg-white p-4 shadow-sm sm:p-5">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2"><h2 className="text-lg font-extrabold text-slate-900">{t("addaAccount.filters.title")}</h2><button type="button" onClick={clearFilters} className="text-sm font-bold text-blue-700 hover:underline">{t("addaAccount.filters.reset")}</button></div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-7">
          <label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.period")}<select className={`${control} mt-1 text-sm`} value={period} onChange={(event) => setPreset(event.target.value as Period)}><option value="today">{t("addaAccount.filters.today")}</option><option value="thisWeek">{t("addaAccount.filters.thisWeek")}</option><option value="thisMonth">{t("addaAccount.filters.thisMonth")}</option><option value="custom">{t("addaAccount.filters.custom")}</option></select></label>

          <VoiceTypingField fieldLabel={t("addaAccount.filters.from")} mode="date"><label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.from")}<input className={`${control} mt-1`} type="date" value={fromDate} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setFromDate(event.target.value); setPeriod("custom"); setPage(0); }} /></label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("addaAccount.filters.to")} mode="date"><label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.to")}<input className={`${control} mt-1`} type="date" value={toDate} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setToDate(event.target.value); setPeriod("custom"); setPage(0); }} /></label></VoiceTypingField>

          <label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.kind")}<select className={`${control} mt-1`} value={kindFilter} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setKindFilter(event.target.value as "all" | "income" | "expense"); setPage(0); }}><option value="all">{t("addaAccount.filters.allKinds")}</option><option value="income">{t("addaAccount.filters.income")}</option><option value="expense">{t("addaAccount.filters.expense")}</option></select></label>
          <label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.category")}<select className={`${control} mt-1`} value={categoryFilter} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setCategoryFilter(event.target.value); setPage(0); }}><option value="">{t("addaAccount.filters.allCategories")}</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
          <label className="text-xs font-bold text-slate-600">{t("addaAccount.filters.employee")}<select className={`${control} mt-1`} value={employeeFilter} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setEmployeeFilter(event.target.value); setPage(0); }}><option value="">{t("addaAccount.filters.allEmployees")}</option>{employees.map((employee) => <option key={employee.id} value={employee.id}>{employee.employee_name}</option>)}</select></label>

          <VoiceTypingField fieldLabel={t("addaAccount.filters.searchPlaceholder")} mode="text"><label className="text-xs font-bold text-slate-600 lg:col-span-2 2xl:col-span-1">{t("addaAccount.filters.search")}<div className="relative mt-1"><input className={`${control} pe-9`} type="search" value={search} placeholder={t("addaAccount.filters.searchPlaceholder")} onChange={(event) => { setLoadingEntries(true); setLoadError(""); setSearch(event.target.value); setPage(0); }} /><Search className="pointer-events-none absolute end-3 top-2.5 text-slate-400" size={16} /></div></label></VoiceTypingField>

        </div>
      </section>

      <section className="overflow-hidden rounded-2xl border border-blue-100 bg-white shadow-sm">
        <header className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 px-4 py-4 sm:px-5"><div><h2 className="text-lg font-extrabold text-slate-900">{t("addaAccount.ledger.title")}</h2><p className="mt-0.5 text-xs text-slate-500">{t("addaAccount.ownAdda")}: {isSuperAdmin ? addas.find((adda) => adda.id === scope)?.name ?? "—" : profile?.adda_id ?? "—"}</p></div><div className="flex gap-2"><button type="button" disabled={loadingEntries || !summary || !scope} onClick={() => void prepareFullStatementPrint()} className={outlineButton}><Printer size={15} />{t("common.actions.print")}</button><button type="button" disabled={loadingEntries} onClick={refreshAll} className={outlineButton}><RefreshCw size={15} />{t("addaAccount.refresh")}</button></div></header>
        {loadingEntries && <div role="status" className="border-b border-slate-100 px-5 py-2 text-xs font-semibold text-blue-700">{t("common.loading")}</div>}
        <div className="overflow-x-auto"><table className="w-full min-w-[1100px] border-separate border-spacing-0 text-sm">
          <thead className="bg-slate-100 text-xs uppercase tracking-wide text-slate-600"><tr>{["date", "type", "category", "reference", "description", "income", "expense", "settled", "pending", "status", "action"].map((key) => <th key={key} className="whitespace-nowrap border-b border-slate-200 px-3 py-3 text-start">{t(`addaAccount.ledger.${key}`)}</th>)}</tr></thead>
          <tbody>
            {!loadingEntries && !loadError && entries.length === 0 && <tr><td colSpan={11} className="px-4 py-12 text-center"><p className="font-bold text-slate-700">{t("addaAccount.ledger.empty")}</p></td></tr>}
            {entries.map((entry) => {
              const status = statusTranslation(entry);
              const label = entry.is_reversal ? t("addaAccount.status.reversal") : entry.entry_kind === "income" ? t("addaAccount.filters.income") : t("addaAccount.filters.expense");
              const isBiltyMarginEntry = entry.source_type === "bilty_margin" || entry.source_type === "bilty_loss";
              const isIssuedFinanceCommission = entry.source_type === "issued_parchi_financing_commission";
              const loadingDetails = entry.loading_details;
              const tripRoute = [loadingDetails?.from_city, loadingDetails?.to_city].filter(Boolean).join(" → ") || loadingDetails?.route;
              const sourceReference = isIssuedFinanceCommission
                ? entry.reference_no ?? entry.source_id.slice(0, 8)
                : isBiltyMarginEntry
                ? loadingDetails?.booking_no || loadingDetails?.loading_no || (entry.loading_id ? `#${entry.loading_id}` : entry.source_id)
                : entry.reference_no ?? entry.source_id.slice(0, 8);
              return <tr key={entry.id} className="border-b border-slate-100 hover:bg-blue-50/40">
                <td className="whitespace-nowrap border-b border-slate-100 px-3 py-3 text-slate-600">{entry.entry_date}</td>
                <td className="border-b border-slate-100 px-3 py-3"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${entry.entry_kind === "income" ? "bg-emerald-50 text-emerald-800" : "bg-rose-50 text-rose-800"}`}>{label}</span></td>
                <td className="border-b border-slate-100 px-3 py-3">{entry.category_name ?? "—"}</td>
                <td className="border-b border-slate-100 px-3 py-3">{sourceReference}</td>
                <td className="max-w-[300px] border-b border-slate-100 px-3 py-3"><span className="block truncate" title={entry.description ?? undefined}>{isIssuedFinanceCommission ? t("addaAccount.ledger.issuedFinance") : entry.description || entry.source_type}</span>{isIssuedFinanceCommission && <span className="block text-xs text-slate-500">{t("addaAccount.ledger.issuedFinanceNoCash")}</span>}{entry.employee_id && <span className="block text-xs text-slate-500">{employees.find((employee) => employee.id === entry.employee_id)?.employee_name ?? t("addaAccount.ledger.employee")}</span>}{isBiltyMarginEntry && <span className="block truncate text-xs text-slate-500" title={[loadingDetails?.vehicle_no, tripRoute].filter(Boolean).join(" · ")}>{t("addaAccount.ledger.loading")}: {loadingDetails?.loading_no ?? `#${entry.loading_id ?? entry.source_id}`} · {t("addaAccount.ledger.vehicle")}: {loadingDetails?.vehicle_no ?? "—"}{tripRoute ? ` · ${tripRoute}` : ""}</span>}</td>
                <td className="whitespace-nowrap border-b border-slate-100 px-3 py-3 text-end font-bold text-emerald-700">{entry.entry_kind === "income" ? money(entry.amount) : "—"}</td>
                <td className="whitespace-nowrap border-b border-slate-100 px-3 py-3 text-end font-bold text-rose-700">{entry.entry_kind === "expense" ? money(entry.amount) : "—"}</td>
                <td className="whitespace-nowrap border-b border-slate-100 px-3 py-3 text-end">{entry.source_type === "employee_salary_generated" || isIssuedFinanceCommission ? "—" : entry.source_type === "bilty_margin" ? <><span className="font-semibold text-emerald-700">{entry.realized_amount === null ? "—" : money(entry.realized_amount)}</span><span className="ms-1 text-[10px] text-slate-500">{t("addaAccount.ledger.realized")}</span></> : entry.source_type === "bilty_loss" ? "—" : money(entry.net_settled_amount)}</td>
                <td className="whitespace-nowrap border-b border-slate-100 px-3 py-3 text-end">{entry.source_type === "employee_salary_generated" || isIssuedFinanceCommission ? "—" : entry.source_type === "bilty_margin" ? <><span className="font-semibold text-amber-700">{entry.margin_pending_amount === null ? "—" : money(entry.margin_pending_amount)}</span><span className="ms-1 text-[10px] text-slate-500">{t("addaAccount.ledger.pending")}</span></> : entry.source_type === "bilty_loss" ? "—" : money(entry.pending_amount)}</td>
                <td className="border-b border-slate-100 px-3 py-3"><span className={`whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-bold ${statusStyle(status)}`}>{t(`addaAccount.status.${status}`)}</span></td>
                <td className="border-b border-slate-100 px-3 py-3"><div className="flex items-center gap-1">
                  {!isIssuedFinanceCommission && <button type="button" onClick={() => openHistory(entry)} title={t("addaAccount.ledger.details")} aria-label={t("addaAccount.ledger.details")} className="rounded-lg border border-slate-200 p-1.5 text-slate-600 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"><Eye size={16} /></button>}
                  {isBiltyMarginEntry && entry.loading_id !== null && <a href={`/loading-details/${entry.loading_id}`} title={t("addaAccount.ledger.openLoading")} aria-label={t("addaAccount.ledger.openLoading")} className="rounded-lg border border-blue-200 p-1.5 text-blue-700 hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"><ExternalLink size={16} /></a>}
                  {canManage && <>
                    <button type="button" disabled={entry.is_reversal || entry.is_reversed || !["manual_adda_expense", "manual_other_income"].includes(entry.source_type)} onClick={() => setMetadataTarget(entry)} title={t("addaAccount.ledger.editMetadata")} aria-label={t("addaAccount.ledger.editMetadata")} className="rounded-lg border border-blue-200 p-1.5 text-blue-700 hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-35"><Pencil size={16} /></button>
                    <button type="button" disabled={printingEntryScope === scope && printingEntryId === entry.id} onClick={() => void printEntry(entry, t(`addaAccount.status.${status}`))} title={t("addaAccount.ledger.print")} aria-label={t("addaAccount.ledger.print")} className="rounded-lg border border-slate-200 p-1.5 text-slate-600 hover:border-indigo-200 hover:bg-indigo-50 hover:text-indigo-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-wait disabled:opacity-50"><Printer size={16} /></button>
                    <button type="button" disabled={entry.is_reversal || entry.is_reversed || !["manual_adda_expense", "manual_other_income"].includes(entry.source_type)} onClick={() => requestEntryReversal(entry)} title={t("addaAccount.ledger.cancelReverse")} aria-label={t("addaAccount.ledger.cancelReverse")} className="rounded-lg border border-rose-200 p-1.5 text-rose-700 hover:bg-rose-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-500 disabled:cursor-not-allowed disabled:opacity-35"><RotateCcw size={16} /></button>
                  </>}
                  {!canManage && <button type="button" disabled={printingEntryScope === scope && printingEntryId === entry.id} onClick={() => void printEntry(entry, t(`addaAccount.status.${status}`))} title={t("addaAccount.ledger.print")} aria-label={t("addaAccount.ledger.print")} className="rounded-lg border border-slate-200 p-1.5 text-slate-600 hover:border-indigo-200 hover:bg-indigo-50 hover:text-indigo-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-wait disabled:opacity-50"><Printer size={16} /></button>}
                  {preparedPrint?.scope === scope && preparedPrint.entry.id === entry.id && <LedgerStatementPrintButton addaId={preparedPrint.entry.adda_id} documentType="adda_account" initialLanguage={language} autoOpenKey={preparedPrint.requestId} onDialogClose={() => setPreparedPrint(null)} makePresentation={(printLanguage) => addaAccountPrintPresentation(preparedPrint.entry, preparedPrint.history, printLanguage)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={() => {
                    const printWindow = openAddaAccountPrintWindow();
                    if (!printWindow) { setActionError(t("addaAccount.print.popupBlocked")); return; }
                    renderAddaAccountPrintWindow(printWindow, preparedPrint.entry, preparedPrint.history, preparedPrint.statusLabel, preparedPrint.labels, dir);
                  }}><span className="sr-only"><button type="button">{translateLedgerPrint(language, "common.actions.print")}</button></span></LedgerStatementPrintButton>}
                  {canManage && !entry.is_reversal && !entry.is_reversed && ["manual_adda_expense", "manual_other_income"].includes(entry.source_type) && entry.pending_amount > 0 && <button type="button" onClick={() => { setActiveEntry(entry); setHistoryLoading(true); setSettlementModal(true); }} title={t("addaAccount.ledger.settle")} aria-label={t("addaAccount.ledger.settle")} className="rounded-lg border border-emerald-200 p-2 text-emerald-700 hover:bg-emerald-50"><CircleDollarSign size={16} /></button>}
                </div></td>
              </tr>;
            })}
          </tbody>
        </table></div>
        <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 px-4 py-3">
          <p className="text-sm text-slate-600">{t("addaAccount.pagination.page")} {page + 1}</p>
          <div className="flex gap-2"><button type="button" disabled={page===0 || loadingEntries} onClick={() => { setLoadingEntries(true); setPage((value) => Math.max(0,value-1)); }} className={outlineButton}><ChevronLeft size={16} />{t("addaAccount.pagination.previous")}</button><button type="button" disabled={!hasNext || loadingEntries} onClick={() => { setLoadingEntries(true); setPage((value) => value+1); }} className={outlineButton}>{t("addaAccount.pagination.next")}<ChevronRight size={16} /></button></div>
        </footer>
      </section>
    </>}

    {preparedStatementPrint?.scopeKey === statementScopeKey && preparedStatementPrint.addaId === scope && <LedgerStatementPrintButton addaId={preparedStatementPrint.addaId} documentType="adda_account" initialLanguage={language} autoOpenKey={preparedStatementPrint.requestId} onDialogClose={() => setPreparedStatementPrint(null)} showLegacyFallback={false} fallbackLabel="" onLegacyPrint={() => undefined} makePresentation={(printLanguage) => addaAccountStatementPrintPresentation(preparedStatementPrint.rows, preparedStatementPrint.summary, preparedStatementPrint.employeeLoanReceivable, { from: preparedStatementPrint.from, to: preparedStatementPrint.to }, printLanguage)}><span className="sr-only">{translateLedgerPrint(language, "common.actions.print")}</span></LedgerStatementPrintButton>}

    {sourceModal && canManage && <AddaFinanceSourceDialog key={sourceModal} kind={sourceModal} categories={categories} employees={employees} onClose={() => setSourceModal(null)} onSubmit={submitSource} />}
    {metadataTarget && canManage && <AddaAccountEntryMetadataDialog key={metadataTarget.id} entry={metadataTarget} onClose={() => setMetadataTarget(null)} onSubmit={submitMetadata} />}
    {displayEntry && <>
      <AddaFinanceHistoryDialog entry={displayEntry} settlements={settlements} loading={historyLoading} canManage={canManage} onClose={() => setActiveEntry(null)} onSettle={() => setSettlementModal(true)} onReverseSettlement={(settlement) => requestSettlementReversal(displayEntry, settlement)} onReverseEntry={() => requestEntryReversal(displayEntry)} />
      {settlementModal && canManage && <AddaFinanceSettlementDialog key={displayEntry.id} entry={displayEntry} onClose={() => setSettlementModal(false)} onSubmit={submitSettlement} />}
    </>}
    {activeSettlementsEntry && canManage && <AddaFinanceActiveSettlementsDialog
      key={activeSettlementsEntry.id}
      entry={activeSettlementsEntry}
      onClose={() => setActiveSettlementsEntry(null)}
      onOpenHistory={() => openHistory(activeSettlementsEntry)}
    />}
    {reversalTarget && canManage && <AddaFinanceReversalDialog
      key={`${reversalTarget.kind}:${reversalTarget.kind === "entry" ? reversalTarget.accountEntryId : reversalTarget.settlementId}`}
      target={reversalTarget}
      submitError={actionError}
      onClose={() => setReversalTarget(null)}
      onSubmit={submitReversal}
    />}
  </main>;
}
