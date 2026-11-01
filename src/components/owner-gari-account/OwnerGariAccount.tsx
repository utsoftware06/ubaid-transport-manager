"use client";

import { BanknoteArrowDown, Printer } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { supabase } from "@/lib/supabase/client";
import LedgerStatementPrintButton from "@/components/print/LedgerStatementPrint";
import { ownerGariMonthlyPrintPresentation, ownerGariWithdrawalPrintPresentation } from "./ownerGariPrintPresentation";

import OwnerGariAccountCards from "./OwnerGariAccountCards";
import OwnerGariAccountDetailModal from "./OwnerGariAccountDetailModal";
import OwnerGariAccountFilters from "./OwnerGariAccountFilters";
import { printOwnerGariMonthlyClosing } from "./OwnerGariAccountPrint";
import OwnerGariAccountTable from "./OwnerGariAccountTable";
import OwnerGariWithdrawalModal from "./OwnerGariWithdrawalModal";
import { printOwnerGariWithdrawalReceipt } from "./OwnerGariWithdrawalReceiptPrint";
import type {
  OwnerGariFilters,
  OwnerGariMonthlyClosing,
  OwnerGariStatement,
  OwnerGariTransaction,
  OwnerGariWithdrawalInput,
  OwnerGariWithdrawalReceipt,
  VehicleOption,
} from "./types";

function currentMonth() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
}

function initialFilters(vehicleId = ""): OwnerGariFilters {
  return {
    vehicleId,
    ownerName: "",
    month: currentMonth(),
    dateFrom: "",
    dateTo: "",
    transactionType: "",
    movementGroupId: "",
    search: "",
  };
}

export default function OwnerGariAccount() {
  const { t, dir, language } = useLanguage();
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [filters, setFilters] = useState<OwnerGariFilters>(() => initialFilters());
  const [appliedFilters, setAppliedFilters] = useState<OwnerGariFilters>(() => initialFilters());
  const [report, setReport] = useState<OwnerGariStatement | null>(null);
  const [closingMonth, setClosingMonth] = useState(currentMonth());
  const [monthlyClosing, setMonthlyClosing] = useState<OwnerGariMonthlyClosing | null>(null);
  const [selectedTransaction, setSelectedTransaction] = useState<OwnerGariTransaction | null>(null);
  const [loadingVehicles, setLoadingVehicles] = useState(true);
  const [loadingReport, setLoadingReport] = useState(false);
  const [loadingClosing, setLoadingClosing] = useState(false);
  const [closingError, setClosingError] = useState("");
  const [savingWithdrawal, setSavingWithdrawal] = useState(false);
  const [reversingTransactionId, setReversingTransactionId] = useState<string | null>(null);
  const [withdrawalRequestKey, setWithdrawalRequestKey] = useState<string | null>(null);
  const [preparedWithdrawalReceipt, setPreparedWithdrawalReceipt] = useState<{ receipt: OwnerGariWithdrawalReceipt; requestId: number } | null>(null);
  const [error, setError] = useState("");
  const reportRequestId = useRef(0);
  const closingRequestId = useRef(0);
  const receiptRequestId = useRef(0);

  useEffect(() => {
    let active = true;
    async function loadVehicles() {
      setLoadingVehicles(true);
      const result = await supabase
        .from("vehicles")
        .select("id, adda_id, vehicle_no, owner_name")
        .order("vehicle_no");

      if (!active) return;
      if (result.error) {
        console.error("Owner/Gari Account vehicle load failed", result.error);
        setError(t("ownerGariAccount.messages.vehiclesFailed"));
        setVehicles([]);
      } else {
        const rows = (result.data ?? []) as VehicleOption[];
        const firstVehicleId = rows[0]?.id ?? "";
        setVehicles(rows);
        setFilters(initialFilters(firstVehicleId));
        setAppliedFilters(initialFilters(firstVehicleId));
      }
      setLoadingVehicles(false);
    }

    void loadVehicles();
    return () => { active = false; };
  }, [t]);

  const loadReport = useCallback(async () => {
    const requestId = ++reportRequestId.current;
    if (!appliedFilters.vehicleId) {
      setReport(null);
      setLoadingReport(false);
      return;
    }

    setLoadingReport(true);
    setError("");
    const result = await supabase.rpc("get_owner_gari_account_statement_v5", {
      p_vehicle_id: appliedFilters.vehicleId,
      p_month: appliedFilters.month ? `${appliedFilters.month}-01` : null,
      p_date_from: appliedFilters.dateFrom || null,
      p_date_to: appliedFilters.dateTo || null,
      p_transaction_type: appliedFilters.transactionType || null,
      p_movement_group_id: appliedFilters.movementGroupId || null,
      p_search: appliedFilters.search.trim() || null,
    });

    if (requestId !== reportRequestId.current) return;

    if (result.error) {
      console.error("Owner/Gari Account statement RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setReport(null);
      setError(result.error.message || t("ownerGariAccount.messages.loadFailed"));
    } else {
      const nextReport = result.data as unknown as OwnerGariStatement;
      if (nextReport.account.vehicle_id !== appliedFilters.vehicleId) {
        console.error("Owner/Gari Account vehicle scope mismatch", {
          requestedVehicleId: appliedFilters.vehicleId,
          returnedVehicleId: nextReport.account.vehicle_id,
        });
        setReport(null);
        setError(t("ownerGariAccount.messages.loadFailed"));
      } else {
        setReport(nextReport);
      }
    }
    setLoadingReport(false);
  }, [appliedFilters, t]);

  const loadMonthlyClosing = useCallback(async () => {
    const requestId = ++closingRequestId.current;
    const selectedVehicle = vehicles.find((vehicle) => vehicle.id === filters.vehicleId);
    const hasDateFrom = Boolean(appliedFilters.dateFrom);
    const hasDateTo = Boolean(appliedFilters.dateTo);
    if (hasDateFrom !== hasDateTo) {
      setMonthlyClosing(null);
      setLoadingClosing(false);
      setClosingError(t("ownerGariAccount.monthlyClosing.dateRangeRequired"));
      return;
    }
    if (!selectedVehicle || (!closingMonth && !hasDateFrom)) {
      setMonthlyClosing(null);
      setLoadingClosing(false);
      setClosingError("");
      return;
    }

    setLoadingClosing(true);
    setMonthlyClosing(null);
    setClosingError("");
    const result = await supabase.rpc("get_owner_gari_closing_v2", {
      p_adda_id: selectedVehicle.adda_id,
      p_vehicle_id: selectedVehicle.id,
      p_month: closingMonth ? closingMonth + "-01" : null,
      p_date_from: hasDateFrom ? appliedFilters.dateFrom : null,
      p_date_to: hasDateTo ? appliedFilters.dateTo : null,
      p_transaction_type: null,
      p_search: null,
    });

    if (requestId !== closingRequestId.current) return;
    if (result.error) {
      console.error("Owner/Gari monthly closing RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setMonthlyClosing(null);
      setClosingError(result.error.message || t("ownerGariAccount.messages.loadFailed"));
    } else {
      const nextClosing = result.data as unknown as OwnerGariMonthlyClosing;
      if (nextClosing.account.vehicle_id !== selectedVehicle.id || nextClosing.account.adda_id !== selectedVehicle.adda_id) {
        console.error("Owner/Gari monthly closing scope mismatch", {
          requestedVehicleId: selectedVehicle.id,
          requestedAddaId: selectedVehicle.adda_id,
          returnedVehicleId: nextClosing.account.vehicle_id,
          returnedAddaId: nextClosing.account.adda_id,
        });
        setMonthlyClosing(null);
        setClosingError(t("ownerGariAccount.messages.loadFailed"));
      } else {
        setMonthlyClosing(nextClosing);
      }
    }
    setLoadingClosing(false);
  }, [appliedFilters.dateFrom, appliedFilters.dateTo, closingMonth, filters.vehicleId, t, vehicles]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadReport(), 0);
    return () => window.clearTimeout(timer);
  }, [loadReport]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadMonthlyClosing(), 0);
    return () => window.clearTimeout(timer);
  }, [loadMonthlyClosing]);

  const owners = useMemo(
    () => Array.from(new Set(
      vehicles.map((vehicle) => vehicle.owner_name?.trim()).filter((owner): owner is string => Boolean(owner))
    )).sort((first, second) => first.localeCompare(second)),
    [vehicles]
  );

  const applyFilters = () => {
    reportRequestId.current += 1;
    setAppliedFilters({ ...filters });
  };
  const changeFilters = (next: OwnerGariFilters) => {
    const vehicleChanged = next.vehicleId !== filters.vehicleId;
    const vehicleScopedFilters = vehicleChanged
      ? { ...next, movementGroupId: "" }
      : next;

    setFilters(vehicleScopedFilters);
    if (vehicleChanged) {
      reportRequestId.current += 1;
      setSelectedTransaction(null);
      setPreparedWithdrawalReceipt(null);
      setReport(null);
      setMonthlyClosing(null);
      setError("");
      setAppliedFilters({ ...vehicleScopedFilters });
    }
  };
  const resetFilters = () => {
    const next = initialFilters(vehicles[0]?.id ?? "");
    reportRequestId.current += 1;
    setPreparedWithdrawalReceipt(null);
    setClosingError("");
    setFilters(next);
    setAppliedFilters(next);
  };

  const openWithdrawal = () => {
    setError("");
    setWithdrawalRequestKey(globalThis.crypto.randomUUID());
  };

  const postWithdrawal = async (input: OwnerGariWithdrawalInput) => {
    const amount = Number(input.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError(t("ownerGariAccount.messages.invalidWithdrawalAmount"));
      return;
    }

    setSavingWithdrawal(true);
    setError("");
    const result = await supabase.rpc("post_owner_gari_withdrawal", {
      p_vehicle_id: input.vehicleId,
      p_withdrawal_date: input.withdrawalDate,
      p_amount: amount,
      p_withdrawal_type: input.withdrawalType,
      p_payment_method: input.paymentMethod,
      p_idempotency_key: input.idempotencyKey,
      p_reference_no: input.referenceNo.trim() || null,
      p_remarks: input.remarks.trim() || null,
    });

    if (result.error) {
      console.error("Owner/Gari withdrawal RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setError(result.error.message || t("ownerGariAccount.messages.withdrawalFailed"));
      setSavingWithdrawal(false);
      return;
    }

    setWithdrawalRequestKey(null);
    setSavingWithdrawal(false);
    const nextFilters = {
      ...filters,
      vehicleId: input.vehicleId,
      movementGroupId: "",
    };
    reportRequestId.current += 1;
    setReport(null);
    setFilters(nextFilters);
    setAppliedFilters(nextFilters);
    await loadMonthlyClosing();
    window.alert(t("ownerGariAccount.messages.withdrawalSaved"));
  };

  const printWithdrawalReceipt = async (transaction: OwnerGariTransaction) => {
    const expectedAddaId = report?.account.adda_id;
    const reportId = reportRequestId.current;
    if (!expectedAddaId) {
      setError(t("ownerGariAccount.messages.receiptFailed"));
      return;
    }
    const result = await supabase.rpc("get_owner_gari_withdrawal_receipt", {
      p_transaction_id: transaction.transaction_id,
    });
    if (result.error) {
      console.error("Owner/Gari withdrawal receipt RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setError(result.error.message || t("ownerGariAccount.messages.receiptFailed"));
      return;
    }
    const receipt = result.data as unknown as OwnerGariWithdrawalReceipt;
    if (reportRequestId.current !== reportId
      || receipt.transaction_id !== transaction.transaction_id || receipt.adda_id !== expectedAddaId) {
      setError(t("ownerGariAccount.messages.receiptFailed"));
      return;
    }
    setError("");
    setPreparedWithdrawalReceipt({ receipt, requestId: ++receiptRequestId.current });
  };

  const reverseWithdrawal = async (transaction: OwnerGariTransaction) => {
    if (!window.confirm(t("ownerGariAccount.messages.reverseConfirm"))) return;

    setReversingTransactionId(transaction.transaction_id);
    setError("");
    const result = await supabase.rpc("reverse_owner_gari_withdrawal", {
      p_transaction_id: transaction.transaction_id,
    });
    if (result.error) {
      console.error("Owner/Gari withdrawal reversal RPC failed", {
        code: result.error.code,
        message: result.error.message,
        details: result.error.details,
        hint: result.error.hint,
      });
      setError(result.error.message || t("ownerGariAccount.messages.reverseFailed"));
      setReversingTransactionId(null);
      return;
    }

    if (selectedTransaction?.transaction_id === transaction.transaction_id) {
      setSelectedTransaction(null);
    }
    setReversingTransactionId(null);
    window.alert(t("ownerGariAccount.messages.reversed"));
    await loadReport();
    await loadMonthlyClosing();
  };

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <ModulePageHeading icon="ledger" accent="blue" title={t("ownerGariAccount.title")} description={t("ownerGariAccount.description")} />
          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={openWithdrawal}
              disabled={vehicles.length === 0}
              className="inline-flex items-center gap-2 rounded-xl bg-red-700 px-4 py-3 font-black text-white shadow hover:bg-red-800 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <BanknoteArrowDown size={19} /> {t("ownerGariAccount.actions.addWithdrawal")}
            </button>
            {monthlyClosing ? <LedgerStatementPrintButton
              addaId={monthlyClosing.account.adda_id}
              documentType="owner_gari_account"
              initialLanguage={language}
              makePresentation={(printLanguage) => ownerGariMonthlyPrintPresentation(monthlyClosing, printLanguage)}
              fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"}
              onLegacyPrint={() => printOwnerGariMonthlyClosing({ report: monthlyClosing, language, dir, t })}
            >
              <button
                type="button"
                disabled={loadingClosing}
                className="inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-3 font-black text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <Printer size={19} /> {t("ownerGariAccount.actions.printAccount")}
              </button>
            </LedgerStatementPrintButton> : <button
              type="button"
              disabled
              className="inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-3 font-black text-white shadow-sm opacity-50"
            >
              <Printer size={19} /> {t("ownerGariAccount.actions.printAccount")}
            </button>}
          </div>
        </div>
      </section>

      <OwnerGariAccountFilters
        filters={filters}
        vehicles={vehicles}
        owners={owners}
        movementGroups={report?.available_movement_groups ?? []}
        loadingVehicles={loadingVehicles}
        onChange={changeFilters}
        onSearch={applyFilters}
        onReset={resetFilters}
        t={t}
      />

      {error && (
        <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 font-bold text-red-700">
          {error}
        </div>
      )}
      {closingError && (
        <div role="alert" className="rounded-xl border border-amber-200 bg-amber-50 p-4 font-bold text-amber-900">
          {closingError}
        </div>
      )}
      {loadingReport && (
        <div role="status" className="rounded-xl bg-white p-6 text-center font-bold text-slate-700 shadow">
          {t("common.loading")}
        </div>
      )}

      <OwnerGariAccountCards
        report={monthlyClosing}
        loading={loadingClosing}
        month={closingMonth}
        dateFrom={appliedFilters.dateFrom}
        dateTo={appliedFilters.dateTo}
        onMonthChange={setClosingMonth}
        customRangeActive={Boolean(appliedFilters.dateFrom && appliedFilters.dateTo)}
        language={language}
        t={t}
      />

      {report && !report.account.account_id && (
        <div className="rounded-xl border border-blue-200 bg-blue-50 p-4 font-bold text-blue-800">
          {t("ownerGariAccount.messages.noAccountYet")}
        </div>
      )}

      <OwnerGariAccountTable
        rows={report?.transactions ?? []}
        loading={loadingReport}
        onView={setSelectedTransaction}
        onPrintReceipt={(transaction) => void printWithdrawalReceipt(transaction)}
        onReverseWithdrawal={(transaction) => void reverseWithdrawal(transaction)}
        reversingTransactionId={reversingTransactionId}
        t={t}
      />

      {preparedWithdrawalReceipt ? <LedgerStatementPrintButton
        addaId={preparedWithdrawalReceipt.receipt.adda_id}
        documentType="owner_gari_account"
        initialLanguage={language}
        autoOpenKey={preparedWithdrawalReceipt.requestId}
        makePresentation={(printLanguage) => ownerGariWithdrawalPrintPresentation(preparedWithdrawalReceipt.receipt, printLanguage)}
        fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"}
        onLegacyPrint={() => {
          const popup = window.open("", "_blank", "width=900,height=850");
          if (!popup) {
            window.alert(t("ownerGariAccount.messages.allowPopups"));
            return;
          }
          printOwnerGariWithdrawalReceipt({ popup, receipt: preparedWithdrawalReceipt.receipt, language, dir, t });
        }}
        onDialogClose={() => setPreparedWithdrawalReceipt(null)}
      >
        <span className="sr-only">{t("ownerGariAccount.actions.printReceipt")}</span>
      </LedgerStatementPrintButton> : null}

      {selectedTransaction && (
        <OwnerGariAccountDetailModal
          transaction={selectedTransaction}
          onClose={() => setSelectedTransaction(null)}
          t={t}
        />
      )}

      {withdrawalRequestKey && (
        <OwnerGariWithdrawalModal
          vehicles={vehicles}
          initialVehicleId={filters.vehicleId || vehicles[0]?.id || ""}
          idempotencyKey={withdrawalRequestKey}
          saving={savingWithdrawal}
          onClose={() => {
            if (!savingWithdrawal) setWithdrawalRequestKey(null);
          }}
          onSubmit={postWithdrawal}
          t={t}
        />
      )}
    </div>
  );
}
