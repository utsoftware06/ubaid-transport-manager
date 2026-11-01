"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { CalendarDays, Check, CircleDollarSign, LoaderCircle, RotateCcw, Save, Settings2, Truck, X } from "lucide-react";
import {
  generateAddaVehicleCommissionMonth,
  listAddaCommissionVehicles,
  listAddaVehicleCommissionHistory,
  listAddaVehicleCommissionSettings,
  mapAddaFinanceError,
  adjustAddaVehicleCommission,
  previewAddaVehicleCommissionMonth,
  reissueAddaVehicleCommission,
  reverseAddaVehicleCommission,
  reverseAddaVehicleCommissionCorrection,
  saveAddaVehicleCommissionSetting,
  type AddaCommissionVehicle,
  type AddaVehicleCommissionHistory,
  type AddaVehicleCommissionPreview,
  type AddaVehicleCommissionSetting,
} from "./api";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  addaId: string;
  canManage: boolean;
  reloadKey: number;
  onUpdated: () => void;
  t: (key: string) => string;
};

const control = "h-10 w-full min-w-0 rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";

function currentMonth() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
}

function today() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function money(value: number) {
  return `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function makeRequestId() {
  return globalThis.crypto.randomUUID();
}

function getBackendErrorText(error: unknown) {
  const fields = error && typeof error === "object" ? error as Record<string, unknown> : {};
  return [fields.message, fields.details, fields.hint, fields.code]
    .filter((value): value is string => typeof value === "string" && value.length > 0)
    .join(" · ") || (error instanceof Error ? error.message : String(error ?? ""));
}

export default function VehicleCommissionSection({ addaId, canManage, reloadKey, onUpdated, t }: Props) {
  const [vehicles, setVehicles] = useState<AddaCommissionVehicle[]>([]);
  const [settings, setSettings] = useState<AddaVehicleCommissionSetting[]>([]);
  const [preview, setPreview] = useState<AddaVehicleCommissionPreview[]>([]);
  const [history, setHistory] = useState<AddaVehicleCommissionHistory[]>([]);
  const [month, setMonth] = useState(currentMonth);
  const [vehicleId, setVehicleId] = useState("");
  const [amount, setAmount] = useState("");
  const [effectiveMonth, setEffectiveMonth] = useState(currentMonth);
  const [isActive, setIsActive] = useState(true);
  const [loading, setLoading] = useState(true);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [reversing, setReversing] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [generateResult, setGenerateResult] = useState("");
  const [reversalTarget, setReversalTarget] = useState<AddaVehicleCommissionHistory | null>(null);
  const [reversalDate, setReversalDate] = useState(today);
  const [reversalReason, setReversalReason] = useState("");
  const [correctionTarget, setCorrectionTarget] = useState<AddaVehicleCommissionHistory | null>(null);
  const [correctionMode, setCorrectionMode] = useState<"reissue" | "adjust" | "reverse">("adjust");
  const [adjustmentDirection, setAdjustmentDirection] = useState<"increase" | "decrease">("increase");
  const [correctionAmount, setCorrectionAmount] = useState("");
  const [correctionReason, setCorrectionReason] = useState("");
  const [correctionReversalDate, setCorrectionReversalDate] = useState(today);
  const [submittingCorrection, setSubmittingCorrection] = useState(false);
  const loadRequestId = useRef(0);
  const reversalRequestId = useRef("");
  const correctionRequestId = useRef("");

  const loadData = useCallback(async () => {
    if (!addaId) return;
    const requestId = ++loadRequestId.current;
    setLoading(true);
    setError("");
    try {
      const [loadedVehicles, loadedSettings, loadedHistory] = await Promise.all([
        listAddaCommissionVehicles(addaId),
        listAddaVehicleCommissionSettings(addaId),
        listAddaVehicleCommissionHistory(addaId),
      ]);
      if (requestId !== loadRequestId.current) return;
      setVehicles(loadedVehicles);
      setSettings(loadedSettings);
      setHistory(loadedHistory);
      const loadedPreview = month
        ? await previewAddaVehicleCommissionMonth(addaId, month)
        : [];
      if (requestId !== loadRequestId.current) return;
      setPreview(loadedPreview);
    } catch (loadError) {
      if (requestId !== loadRequestId.current) return;
      console.error("Vehicle commission data load failed", loadError);
      setError(mapAddaFinanceError(loadError, t("addaAccount.vehicleCommission.loadFailed")));
    } finally {
      if (requestId === loadRequestId.current) {
        setLoading(false);
        setPreviewLoading(false);
      }
    }
  }, [addaId, month, t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadData(), 0);
    return () => {
      window.clearTimeout(timer);
      loadRequestId.current += 1;
    };
  }, [loadData, reloadKey]);

  const refreshPreview = async () => {
    if (!addaId) return;
    setPreviewLoading(true);
    setError("");
    try {
      setPreview(await previewAddaVehicleCommissionMonth(addaId, month));
    } catch (previewError) {
      console.error("Vehicle commission preview failed", previewError);
      setError(mapAddaFinanceError(previewError, t("addaAccount.vehicleCommission.previewFailed")));
    } finally {
      setPreviewLoading(false);
    }
  };

  const saveSetting = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!vehicleId) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      await saveAddaVehicleCommissionSetting({
        addaId,
        vehicleId,
        monthlyAmount: Number(amount),
        isActive,
        effectiveFrom: effectiveMonth ? `${effectiveMonth}-01` : null,
      });
      setNotice(t("addaAccount.vehicleCommission.settingSaved"));
      await loadData();
      onUpdated();
    } catch (saveError) {
      console.error("Vehicle commission setting save failed", saveError);
      setError(mapAddaFinanceError(saveError, t("addaAccount.vehicleCommission.saveFailed")));
    } finally {
      setSaving(false);
    }
  };

  const editSetting = (setting: AddaVehicleCommissionSetting) => {
    setVehicleId(setting.vehicle_id);
    setAmount(String(setting.monthly_amount));
    setIsActive(setting.is_active);
    setEffectiveMonth(setting.effective_from?.slice(0, 7) ?? "");
    setNotice("");
  };

  const generateMonth = async () => {
    if (!canManage || !addaId || !month || generating || previewLoading || loading
      || !preview.some((row) => row.generation_status === "Ready")) return;
    const requestId = makeRequestId();
    setGenerating(true);
    setError("");
    setNotice("");
    try {
      const result = await generateAddaVehicleCommissionMonth(addaId, month, requestId);
      const generated = Number(result.generated_count ?? 0);
      const already = Number(result.already_generated_count ?? 0);
      setGenerateResult(t("addaAccount.vehicleCommission.generatedResult")
        .replace("{generated}", String(generated)).replace("{existing}", String(already)));
      await loadData();
      onUpdated();
    } catch (generationError) {
      console.error("Vehicle commission generation failed", generationError);
      setError(getBackendErrorText(generationError) || mapAddaFinanceError(generationError, t("addaAccount.vehicleCommission.generateFailed")));
    } finally {
      setGenerating(false);
    }
  };

  const openReversal = (event: AddaVehicleCommissionHistory) => {
    reversalRequestId.current = makeRequestId();
    setReversalDate(today());
    setReversalReason("");
    setReversalTarget(event);
    setError("");
  };

  const submitReversal = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!reversalTarget || !reversalRequestId.current) return;
    setReversing(true);
    setError("");
    try {
      await reverseAddaVehicleCommission({
        addaId,
        originalEventId: reversalTarget.event_id,
        reversalDate,
        reason: reversalReason.trim(),
        requestId: reversalRequestId.current,
      });
      setReversalTarget(null);
      setNotice(t("addaAccount.vehicleCommission.reversed"));
      await loadData();
      onUpdated();
    } catch (reversalError) {
      console.error("Vehicle commission reversal failed", reversalError);
      setError(mapAddaFinanceError(reversalError, t("addaAccount.vehicleCommission.reverseFailed")));
    } finally {
      setReversing(false);
    }
  };

  const openCorrection = (row: AddaVehicleCommissionHistory, mode: "reissue" | "adjust" | "reverse") => {
    correctionRequestId.current = makeRequestId();
    setCorrectionTarget(row);
    setCorrectionMode(mode);
    setAdjustmentDirection("increase");
    setCorrectionAmount("");
    setCorrectionReason("");
    setCorrectionReversalDate(today());
    setError("");
  };

  const submitCorrection = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!correctionTarget || !correctionRequestId.current || !canManage) return;
    setSubmittingCorrection(true);
    setError("");
    try {
      if (correctionMode === "reissue") {
        await reissueAddaVehicleCommission({
          addaId, reversalEventId: correctionTarget.event_id,
          reason: correctionReason.trim(), requestId: correctionRequestId.current,
        });
      } else if (correctionMode === "adjust") {
        await adjustAddaVehicleCommission({
          addaId, targetEventId: correctionTarget.event_id, direction: adjustmentDirection,
          amount: Number(correctionAmount), reason: correctionReason.trim(), requestId: correctionRequestId.current,
        });
      } else {
        await reverseAddaVehicleCommissionCorrection({
          addaId, targetEventId: correctionTarget.event_id,
          reversalDate: correctionReversalDate, reason: correctionReason.trim(),
          requestId: correctionRequestId.current,
        });
      }
      setCorrectionTarget(null);
      setNotice(t(`addaAccount.vehicleCommission.${correctionMode}Success`));
      await loadData();
      onUpdated();
    } catch (correctionError) {
      console.error("Vehicle commission correction failed", correctionError);
      setError(getBackendErrorText(correctionError)
        || mapAddaFinanceError(correctionError, t("addaAccount.vehicleCommission.correctionFailed")));
    } finally {
      setSubmittingCorrection(false);
    }
  };

  const adjustmentValue = Number(correctionAmount);
  const effectiveAfterAdjustment = correctionTarget
    ? correctionTarget.effective_root_amount + (adjustmentDirection === "increase" ? adjustmentValue : -adjustmentValue)
    : 0;

  const readyCount = preview.filter((row) => row.generation_status === "Ready").length;

  return (
    <section className="overflow-hidden rounded-2xl border border-indigo-100 bg-white shadow-sm">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 px-4 py-4 sm:px-5">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-600 text-white shadow-sm"><Truck size={20} /></span>
          <div>
            <h2 className="text-lg font-extrabold text-slate-900">{t("addaAccount.vehicleCommission.title")}</h2>
            <p className="mt-0.5 text-xs text-slate-500">{t("addaAccount.vehicleCommission.description")}</p>
          </div>
        </div>
        <div className="flex flex-wrap items-end gap-2">

          <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.month")} mode="date"><label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.month")}
            <input className={`${control} mt-1 w-40`} type="month" value={month} onChange={(event) => { setMonth(event.target.value); setGenerateResult(""); }} />
          </label></VoiceTypingField>

          <button type="button" onClick={() => void refreshPreview()} disabled={previewLoading || loading || !month} className="inline-flex h-10 items-center gap-2 rounded-lg border border-indigo-200 bg-white px-3 text-sm font-bold text-indigo-800 hover:bg-indigo-50 disabled:opacity-50">
            {previewLoading ? <LoaderCircle className="animate-spin" size={16} /> : <CalendarDays size={16} />}{t("addaAccount.vehicleCommission.preview")}
          </button>
        </div>
      </header>

      {error && <div role="alert" className="mx-4 mt-4 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm font-semibold text-rose-800 sm:mx-5">{error}</div>}
      {notice && <p role="status" className="mx-4 mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm font-semibold text-emerald-800 sm:mx-5">{notice}</p>}
      {generateResult && <p role="status" className="mx-4 mt-4 rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm font-semibold text-blue-800 sm:mx-5">{generateResult}</p>}
      <p className="mx-4 mt-4 rounded-xl border border-amber-100 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900 sm:mx-5">{t("addaAccount.vehicleCommission.eligibilityNote")}</p>

      {canManage && <form onSubmit={(event) => void saveSetting(event)} className="m-4 rounded-xl border border-slate-200 bg-slate-50/70 p-4 sm:m-5">
        <div className="mb-3 flex items-center gap-2 text-sm font-extrabold text-slate-800"><Settings2 size={17} className="text-indigo-600" />{t("addaAccount.vehicleCommission.settingsTitle")}</div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.vehicle")}
            <select className={`${control} mt-1`} required value={vehicleId} onChange={(event) => {
              const nextId = event.target.value;
              setVehicleId(nextId);
              const existing = settings.find((row) => row.vehicle_id === nextId);
              if (existing) editSetting(existing);
              else { setAmount(""); setIsActive(true); setEffectiveMonth(month); }
            }}>
              <option value="">{t("addaAccount.vehicleCommission.selectVehicle")}</option>
              {vehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicle_no || vehicle.id}{vehicle.owner_name ? ` · ${vehicle.owner_name}` : ""}
              </option>)}
            </select>
          </label>

          <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.monthlyAmount")} mode="amount"><label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.monthlyAmount")}
            <input className={`${control} mt-1`} type="number" min="0" step="0.01" required value={amount} onChange={(event) => setAmount(event.target.value)} />
          </label></VoiceTypingField>


          <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.effectiveFrom")} mode="date"><label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.effectiveFrom")}
            <input className={`${control} mt-1`} type="month" value={effectiveMonth} onChange={(event) => setEffectiveMonth(event.target.value)} />
          </label></VoiceTypingField>

          <label className="flex items-center gap-2 self-end rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm font-bold text-slate-700">
            <input type="checkbox" checked={isActive} onChange={(event) => setIsActive(event.target.checked)} className="h-4 w-4 accent-blue-600" />{t("addaAccount.vehicleCommission.active")}
          </label>
          <div className="flex items-end gap-2">
            <button type="submit" disabled={saving || !vehicleId || !amount} className="inline-flex h-10 flex-1 items-center justify-center gap-2 rounded-lg bg-blue-700 px-3 text-sm font-bold text-white hover:bg-blue-800 disabled:opacity-50">
              {saving ? <LoaderCircle className="animate-spin" size={16} /> : <Save size={16} />}{saving ? t("addaAccount.vehicleCommission.saving") : t("addaAccount.vehicleCommission.saveSetting")}
            </button>
          </div>
        </div>
      </form>}

      <div className="grid gap-4 p-4 pt-0 sm:p-5 sm:pt-0 xl:grid-cols-2">
        <section className="min-w-0 overflow-hidden rounded-xl border border-slate-200">
          <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-3 py-2.5">
            <h3 className="text-sm font-extrabold text-slate-800">{t("addaAccount.vehicleCommission.previewTitle")}</h3>
            <span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-800">{readyCount} {t("addaAccount.vehicleCommission.ready")}</span>
          </div>
          <div className="max-h-72 overflow-auto">
            <table className="w-full min-w-[570px] text-xs">
              <thead className="sticky top-0 bg-slate-100 text-slate-600"><tr>
                {["vehicle", "owner", "monthlyAmount", "statusLabel"].map((key) => <th key={key} className="px-3 py-2 text-start">{t(`addaAccount.vehicleCommission.${key}`)}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-slate-100">
                {preview.map((row) => <tr key={row.vehicle_id}>
                  <td className="px-3 py-2.5 font-bold text-slate-800">{row.vehicle_no || row.vehicle_id}</td>
                  <td className="px-3 py-2.5 text-slate-600">{row.owner_name || "—"}</td>
                  <td className="px-3 py-2.5 font-bold tabular-nums">{money(row.monthly_amount)}</td>
                  <td className="px-3 py-2.5"><span title={row.eligibility_reason ?? undefined} className={`rounded-full px-2 py-1 font-bold ${row.generation_status === "Ready" ? "bg-emerald-50 text-emerald-800" : row.generation_status === "Already Generated" ? "bg-blue-50 text-blue-800" : "bg-slate-100 text-slate-600"}`}>{t(`addaAccount.vehicleCommission.status.${row.generation_status === "Already Generated" ? "alreadyGenerated" : row.generation_status === "Not Eligible" ? "notEligible" : "ready"}`)}</span></td>
                </tr>)}
                {!loading && preview.length===0 && <tr><td colSpan={4} className="px-3 py-8 text-center font-medium text-slate-500">{t("addaAccount.vehicleCommission.noSettings")}</td></tr>}
              </tbody>
            </table>
          </div>
          {canManage && <div className="flex justify-end border-t border-slate-100 bg-white p-3">
            <button type="button" onClick={() => void generateMonth()} disabled={generating || loading || previewLoading || !month || readyCount === 0} className="inline-flex h-10 items-center gap-2 rounded-lg bg-blue-700 px-4 text-sm font-bold text-white shadow-sm hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50">
              {generating ? <LoaderCircle className="animate-spin" size={16} /> : <CircleDollarSign size={16} />}{generating ? t("addaAccount.vehicleCommission.generating") : t("addaAccount.vehicleCommission.generate")}
            </button>
          </div>}
        </section>

        <section className="min-w-0 overflow-hidden rounded-xl border border-slate-200">
          <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-3 py-2.5">
            <h3 className="text-sm font-extrabold text-slate-800">{t("addaAccount.vehicleCommission.savedSettings")}</h3>
            {loading && <LoaderCircle className="animate-spin text-blue-600" size={15} />}
          </div>
          <div className="max-h-72 overflow-auto">
            <table className="w-full min-w-[580px] text-xs">
              <thead className="sticky top-0 bg-slate-100 text-slate-600"><tr>
                {["vehicle", "owner", "monthlyAmount", "effectiveFrom", "statusLabel", ...(canManage ? ["actionLabel"] : [])].map((key) => <th key={key} className="px-3 py-2 text-start">{t(`addaAccount.vehicleCommission.${key}`)}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-slate-100">
                {settings.map((row) => <tr key={row.vehicle_id}>
                  <td className="px-3 py-2.5 font-bold">{row.vehicle_no || row.vehicle_id}</td>
                  <td className="px-3 py-2.5">{row.owner_name || "—"}</td>
                  <td className="px-3 py-2.5 font-bold tabular-nums">{money(row.monthly_amount)}</td>
                  <td className="px-3 py-2.5">{row.effective_from?.slice(0, 7) || "—"}</td>
                  <td className="px-3 py-2.5"><span className={`rounded-full px-2 py-1 font-bold ${row.is_active ? "bg-emerald-50 text-emerald-800" : "bg-slate-100 text-slate-600"}`}>{row.is_active ? t("addaAccount.vehicleCommission.active") : t("addaAccount.vehicleCommission.inactive")}</span></td>
                  {canManage && <td className="px-3 py-2.5"><button type="button" onClick={() => editSetting(row)} className="rounded-lg border border-blue-200 px-2.5 py-1.5 font-bold text-blue-700 hover:bg-blue-50">{t("addaAccount.vehicleCommission.edit")}</button></td>}
                </tr>)}
                {!loading && settings.length===0 && <tr><td colSpan={canManage ? 6 : 5} className="px-3 py-8 text-center font-medium text-slate-500">{t("addaAccount.vehicleCommission.noSettings")}</td></tr>}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section className="mx-4 mb-4 overflow-hidden rounded-xl border border-slate-200 sm:mx-5 sm:mb-5">
        <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-3 py-2.5">
          <h3 className="text-sm font-extrabold text-slate-800">{t("addaAccount.vehicleCommission.history")}</h3>
          <span className="text-xs text-slate-500">{t("addaAccount.vehicleCommission.noCashbook")}</span>
        </div>
        <div className="max-h-80 overflow-auto">
          <table className="w-full min-w-[1180px] text-xs">
            <thead className="sticky top-0 bg-slate-100 text-slate-600"><tr>
                {["month", "vehicle", "owner", "eventType", "monthlyAmount", "signedEffect", "statusLabel", "reason", "actionLabel"].map((key) => <th key={key} className="px-3 py-2 text-start">{t(`addaAccount.vehicleCommission.${key}`)}</th>)}
            </tr></thead>
            <tbody className="divide-y divide-slate-100">
              {history.map((row) => <tr key={row.event_id}>
                <td className="px-3 py-2.5">{row.accounting_month.slice(0, 7)}</td>
                <td className="px-3 py-2.5 font-bold">{row.vehicle_no || row.vehicle_id}</td>
                <td className="px-3 py-2.5">{row.owner_name || "—"}</td>
                <td className="px-3 py-2.5 font-semibold">{t(`addaAccount.vehicleCommission.eventTypes.${row.event_type}`)}</td>
                <td className="px-3 py-2.5 font-bold tabular-nums">{money(row.amount)}</td>
                <td className={`px-3 py-2.5 font-extrabold tabular-nums ${row.signed_effect < 0 ? "text-rose-700" : "text-emerald-700"}`}>{row.signed_effect < 0 ? "−" : "+"}{money(Math.abs(row.signed_effect))}</td>
                <td className="px-3 py-2.5"><span className={`rounded-full px-2 py-1 font-bold ${row.status === "Active" || row.status === "Re-issued" ? "bg-emerald-50 text-emerald-800" : row.status === "Reversed" || row.status === "Reversal" ? "bg-amber-50 text-amber-800" : "bg-blue-50 text-blue-800"}`}>{t(`addaAccount.vehicleCommission.status.${row.status === "Adjustment increase" ? "adjustmentIncrease" : row.status === "Adjustment decrease" ? "adjustmentDecrease" : row.status.toLowerCase().replaceAll("-", "").replaceAll(" ", "")}`)}</span><p className="mt-1 text-[10px] font-semibold text-slate-500" title={`${t("addaAccount.vehicleCommission.rootOriginal")}: ${money(row.root_original_amount)}; ${t("addaAccount.vehicleCommission.totalReversals")}: ${money(row.total_reversals)}; ${t("addaAccount.vehicleCommission.totalReissues")}: ${money(row.total_reissues)}; +${money(row.total_adjustment_increases)} / −${money(row.total_adjustment_decreases)}`}>{t("addaAccount.vehicleCommission.effective")}: {money(row.effective_root_amount)} · {t(`addaAccount.vehicleCommission.status.${row.effective_root_status.toLowerCase()}`)}</p>{row.reversal_date && row.event_type === "reversal" && <span className="text-slate-500">{row.reversal_date}</span>}</td>
                <td className="max-w-48 truncate px-3 py-2.5 text-slate-600" title={row.correction_reason || row.reversal_reason || undefined}>{row.correction_reason || row.reversal_reason || "—"}</td>
                <td className="px-3 py-2.5"><div className="flex flex-wrap gap-1.5">
                  {canManage && row.can_reissue && <button type="button" onClick={() => openCorrection(row, "reissue")} className="inline-flex items-center gap-1 rounded-lg border border-indigo-200 px-2 py-1.5 font-bold text-indigo-700 hover:bg-indigo-50"><RotateCcw size={13} />{t("addaAccount.vehicleCommission.reissue")}</button>}
                  {canManage && row.can_adjust && <button type="button" onClick={() => openCorrection(row, "adjust")} className="inline-flex items-center gap-1 rounded-lg border border-blue-200 px-2 py-1.5 font-bold text-blue-700 hover:bg-blue-50">± {t("addaAccount.vehicleCommission.adjust")}</button>}
                  {canManage && row.can_reverse && (row.event_type === "commission"
                    ? <button type="button" onClick={() => openReversal(row)} className="inline-flex items-center gap-1 rounded-lg border border-rose-200 px-2 py-1.5 font-bold text-rose-700 hover:bg-rose-50"><RotateCcw size={13} />{t("addaAccount.vehicleCommission.reverse")}</button>
                    : <button type="button" onClick={() => openCorrection(row, "reverse")} className="inline-flex items-center gap-1 rounded-lg border border-rose-200 px-2 py-1.5 font-bold text-rose-700 hover:bg-rose-50"><RotateCcw size={13} />{t("addaAccount.vehicleCommission.reverse")}</button>)}
                  {!row.can_reissue && !row.can_adjust && !row.can_reverse && <span className="text-slate-400">—</span>}
                </div></td>
              </tr>)}
              {!loading && history.length===0 && <tr><td colSpan={9} className="px-3 py-8 text-center font-medium text-slate-500">{t("addaAccount.vehicleCommission.noHistory")}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      {reversalTarget && <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-4" role="dialog" aria-modal="true" aria-labelledby="vehicle-commission-reversal-title">
        <form onSubmit={(event) => void submitReversal(event)} className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl">
          <div className="flex items-start justify-between gap-3">
            <div><h3 id="vehicle-commission-reversal-title" className="text-lg font-extrabold text-slate-900">{t("addaAccount.vehicleCommission.reverseTitle")}</h3><p className="mt-1 text-sm text-slate-600">{reversalTarget.vehicle_no || reversalTarget.vehicle_id} · {reversalTarget.accounting_month.slice(0, 7)} · {money(reversalTarget.amount)}</p></div>
            <button type="button" onClick={() => setReversalTarget(null)} disabled={reversing} aria-label={t("common.actions.close")} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100"><X size={18} /></button>
          </div>
          <p className="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">{t("addaAccount.vehicleCommission.reverseNotice")}</p>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">

            <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.reversalDate")} mode="date"><label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.reversalDate")}<input className={`${control} mt-1`} type="date" required value={reversalDate} min={reversalTarget.accounting_month} onChange={(event) => setReversalDate(event.target.value)} /></label></VoiceTypingField>

            <label className="text-xs font-bold text-slate-600 sm:col-span-2">{t("addaAccount.vehicleCommission.reason")}<VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.reason")} value={reversalReason} onValueChange={setReversalReason} contextKey={reversalTarget.event_id}><textarea className="mt-1 min-h-20 w-full rounded-lg border border-slate-300 bg-white p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" required maxLength={500} value={reversalReason} onChange={(event) => setReversalReason(event.target.value)} /></VoiceTypingField></label>
          </div>
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" disabled={reversing} onClick={() => setReversalTarget(null)} className="inline-flex h-10 items-center rounded-lg border border-slate-300 px-4 text-sm font-bold text-slate-700 hover:bg-slate-50">{t("addaAccount.vehicleCommission.cancel")}</button>
            <button type="submit" disabled={reversing || !reversalReason.trim()} className="inline-flex h-10 items-center gap-2 rounded-lg bg-rose-700 px-4 text-sm font-bold text-white hover:bg-rose-800 disabled:opacity-50">{reversing ? <LoaderCircle className="animate-spin" size={15} /> : <Check size={15} />}{t("addaAccount.vehicleCommission.confirmReverse")}</button>
          </div>
        </form>
      </div>}

      {correctionTarget && <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-4" role="dialog" aria-modal="true" aria-labelledby="vehicle-commission-correction-title">
        <form onSubmit={(event) => void submitCorrection(event)} className="w-full max-w-xl rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h3 id="vehicle-commission-correction-title" className="text-lg font-extrabold text-slate-900">{t(`addaAccount.vehicleCommission.${correctionMode === "reverse" ? "reverseTitleCorrection" : `${correctionMode}Title`}`)}</h3>
              <p className="mt-1 text-sm text-slate-600">{correctionTarget.vehicle_no || correctionTarget.vehicle_id} · {correctionTarget.owner_name || "—"} · {correctionTarget.accounting_month.slice(0, 7)}</p>
            </div>
            <button type="button" onClick={() => setCorrectionTarget(null)} disabled={submittingCorrection} aria-label={t("common.actions.close")} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100"><X size={18} /></button>
          </div>
          {correctionMode === "reissue" && <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <div className="rounded-lg bg-slate-50 p-3"><p className="text-xs font-bold text-slate-500">{t("addaAccount.vehicleCommission.reversedCharge")}</p><p className="mt-1 font-extrabold text-slate-900">{money(correctionTarget.amount)}</p></div>
            <div className="rounded-lg bg-slate-50 p-3"><p className="text-xs font-bold text-slate-500">{t("addaAccount.vehicleCommission.reversalDate")}</p><p className="mt-1 font-extrabold text-slate-900">{correctionTarget.reversal_date || "—"}</p></div>
            <div className="rounded-lg bg-slate-50 p-3 sm:col-span-2"><p className="text-xs font-bold text-slate-500">{t("addaAccount.vehicleCommission.reissueAmount")}</p><p className="mt-1 font-extrabold text-slate-900">{money(correctionTarget.amount)}</p></div>
          </div>}
          {correctionMode === "adjust" && <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <div className="rounded-lg bg-slate-50 p-3"><p className="text-xs font-bold text-slate-500">{t("addaAccount.vehicleCommission.currentEffective")}</p><p className="mt-1 font-extrabold text-slate-900">{money(correctionTarget.effective_root_amount)}</p></div>
            <label className="text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.direction")}
              <select className={`${control} mt-1`} value={adjustmentDirection} onChange={(event) => setAdjustmentDirection(event.target.value as "increase" | "decrease")}>
                <option value="increase">{t("addaAccount.vehicleCommission.increase")}</option><option value="decrease">{t("addaAccount.vehicleCommission.decrease")}</option>
              </select>
            </label>

            <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.adjustmentAmount")} mode="amount"><label className="text-xs font-bold text-slate-600 sm:col-span-2">{t("addaAccount.vehicleCommission.adjustmentAmount")}
              <input className={`${control} mt-1`} type="number" min="0.01" step="0.01" required value={correctionAmount} onChange={(event) => setCorrectionAmount(event.target.value)} />
            </label></VoiceTypingField>

            <div className={`rounded-lg p-3 sm:col-span-2 ${effectiveAfterAdjustment < 0 ? "bg-rose-50 text-rose-800" : "bg-blue-50 text-blue-900"}`}>
              <span className="text-xs font-bold">{t("addaAccount.vehicleCommission.newEffective")}</span>
              <p className="mt-1 font-extrabold">{money(effectiveAfterAdjustment)}</p>
            </div>
          </div>}
          {correctionMode === "reverse" &&
          <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.reversalDate")} mode="date"><label className="mt-4 block text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.reversalDate")}
            <input className={`${control} mt-1`} type="date" required min={correctionTarget.accounting_month} value={correctionReversalDate} onChange={(event) => setCorrectionReversalDate(event.target.value)} />
          </label></VoiceTypingField>
          }
          <label className="mt-4 block text-xs font-bold text-slate-600">{t("addaAccount.vehicleCommission.reason")}
            <VoiceTypingField fieldLabel={t("addaAccount.vehicleCommission.reason")} value={correctionReason} onValueChange={setCorrectionReason} contextKey={`${correctionTarget.event_id}:${correctionMode}`}><textarea className="mt-1 min-h-20 w-full rounded-lg border border-slate-300 bg-white p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" required maxLength={500} value={correctionReason} onChange={(event) => setCorrectionReason(event.target.value)} /></VoiceTypingField>
          </label>
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" disabled={submittingCorrection} onClick={() => setCorrectionTarget(null)} className="inline-flex h-10 items-center rounded-lg border border-slate-300 px-4 text-sm font-bold text-slate-700 hover:bg-slate-50">{t("addaAccount.vehicleCommission.cancel")}</button>
            <button type="submit" disabled={submittingCorrection || !correctionReason.trim()
              || (correctionMode === "adjust" && (!Number.isFinite(adjustmentValue) || adjustmentValue <= 0 || effectiveAfterAdjustment < 0))}
              className="inline-flex h-10 items-center gap-2 rounded-lg bg-indigo-700 px-4 text-sm font-bold text-white hover:bg-indigo-800 disabled:opacity-50">
              {submittingCorrection ? <LoaderCircle className="animate-spin" size={15} /> : <Check size={15} />}
              {t(`addaAccount.vehicleCommission.${correctionMode === "reverse" ? "confirmReverseCorrection" : `confirm${correctionMode[0].toUpperCase()}${correctionMode.slice(1)}`}`)}
            </button>
          </div>
        </form>
      </div>}
    </section>
  );
}
