"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Archive, Building2, Check, Eye, Pencil, Plus, RefreshCw } from "lucide-react";
import { isUserRole, USER_ROLES, type UserRole } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import { listOtherAddas, mapOtherAddaError, setOtherAddaStatus } from "./api";
import OtherAddaFormModal from "./OtherAddaFormModal";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import type { OtherAdda, OtherAddaBusinessType, OtherAddaDuplicate, OtherAddaStatus } from "./types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = { onViewAccount?: (otherAddaId: string) => void };
type Profile = { role: UserRole; addaId: string | null };
type AddaOption = { id: string; name: string };
type Modal = { master: OtherAdda | null; businessType: OtherAddaBusinessType };
const control = "w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100";
const button = "rounded-lg border border-blue-200 bg-white px-3 py-2 font-bold text-blue-800 hover:bg-blue-50 focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-60";

export default function OtherAddasManager({ onViewAccount }: Props) {
  const router = useRouter();
  const { dir } = useLanguage();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [contextLoading, setContextLoading] = useState(true);
  const [contextError, setContextError] = useState("");
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [masters, setMasters] = useState<OtherAdda[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [notice, setNotice] = useState("");
  const [search, setSearch] = useState("");
  const [businessType, setBusinessType] = useState<OtherAddaBusinessType | "all">("all");
  const [status, setStatus] = useState<OtherAddaStatus | "all">("active");
  const [city, setCity] = useState("");
  const [page, setPage] = useState(1);
  const [modal, setModal] = useState<Modal | null>(null);
  const [formBusy, setFormBusy] = useState(false);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [selectedMaster, setSelectedMaster] = useState<{ id: string; name: string } | null>(null);
  const contextRequest = useRef(0);
  const listRequest = useRef(0);
  const mutationLock = useRef(false);
  const superAdmin = profile?.role === USER_ROLES.superAdmin;
  const canManage = profile?.role === USER_ROLES.addaAdmin || superAdmin;
  const scope = profile ? (superAdmin ? selectedAddaId : profile.addaId ?? "") : "";
  const busy = formBusy || pendingId !== null;

  const loadContext = useCallback(async () => {
    const request = ++contextRequest.current;
    ++listRequest.current;
    setContextLoading(true); setContextError(""); setProfile(null); setMasters(null);
    setSelectedAddaId(""); setModal(null); setSelectedMaster(null); setAddas([]);
    try {
      const auth = await supabase.auth.getUser();
      if (auth.error) throw auth.error;
      if (!auth.data.user) throw new Error("Sign in to view Other Addas.");
      const response = await supabase.from("profiles").select("role, adda_id, is_active").eq("id", auth.data.user.id).single();
      if (response.error) throw response.error;
      const row = response.data;
      if (!row || row.is_active !== true || !isUserRole(row.role)) throw new Error("An active supported profile is required.");
      if (row.role !== USER_ROLES.superAdmin && !row.adda_id) throw new Error("Your assigned Adda is unavailable.");
      let options: AddaOption[] = [];
      if (row.role === USER_ROLES.superAdmin) {
        // Same public, RLS-governed Adda list/select pattern as PartiesManager.
        const result = await supabase.from("addas").select("id, name").order("name");
        if (result.error) throw result.error;
        if (!Array.isArray(result.data)) throw new Error("Unable to read the Adda list.");
        options = result.data.map((item) => {
          if (typeof item.id !== "string" || typeof item.name !== "string") throw new Error("Invalid Adda list response.");
          return { id: item.id, name: item.name };
        });
      }
      if (request !== contextRequest.current) return;
      setAddas(options); setProfile({ role: row.role, addaId: row.adda_id });
    } catch (failure) {
      if (request !== contextRequest.current) return;
      console.error("Other Adda profile load failed", failure); setContextError(mapOtherAddaError(failure).message);
    } finally { if (request === contextRequest.current) setContextLoading(false); }
  }, []);

  const loadMasters = useCallback(async () => {
    if (!profile || !scope) return;
    const request = ++listRequest.current;
    setLoading(true); setLoadError(""); setMasters(null);
    try {
      const collected: OtherAdda[] = [];
      const seen = new Set<string>();
      // Exhaust API pages for genuine master counts; do not count only the first 50.
      for (let batchNumber = 0; ; batchNumber++) {
        if (batchNumber >= 1000) throw new Error("The list is too large to load completely. No partial totals are shown.");
        const batch = await listOtherAddas({ offset: collected.length, limit: 1000,
          ...(superAdmin ? { adda_id: scope } : {}) });
        if (request !== listRequest.current) return;
        if (!batch.length) break;
        for (const master of batch) {
          if (master.adda_id !== scope) throw new Error("Other Adda response scope mismatch.");
          if (seen.has(master.id)) throw new Error("The master list changed during loading. Retry to refresh it.");
          seen.add(master.id); collected.push(master);
        }
      }
      if (request === listRequest.current) setMasters(collected);
    } catch (failure) {
      if (request !== listRequest.current) return;
      console.error("Other Adda master load failed", failure); setLoadError(mapOtherAddaError(failure).message);
      throw mapOtherAddaError(failure);
    } finally { if (request === listRequest.current) setLoading(false); }
  }, [profile, scope, superAdmin]);

  const cancelContext = useCallback(() => { ++contextRequest.current; ++listRequest.current; }, []);
  const cancelList = useCallback(() => { ++listRequest.current; }, []);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadContext(); }, 0);
    return () => { window.clearTimeout(timer); cancelContext(); };
  }, [loadContext, cancelContext]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadMasters().catch(() => undefined); }, 0);
    return () => { window.clearTimeout(timer); cancelList(); };
  }, [loadMasters, cancelList]);

  const cities = useMemo(() => Array.from(new Set((masters ?? []).map((m) => m.city).filter((value): value is string => Boolean(value)))).sort(), [masters]);
  const filtered = useMemo(() => {
    const term = search.trim().toLocaleLowerCase();
    return (masters ?? []).filter((master) => (status === "all" || master.status === status)
      && (businessType === "all" || master.business_type === businessType) && (!city || master.city === city)
      && (!term || [master.adda_name, master.contact_person, master.mobile, master.whatsapp, master.city, master.ntn_cnic]
        .filter(Boolean).join(" ").toLocaleLowerCase().includes(term)));
  }, [masters, search, status, businessType, city]);
  const summaries = masters === null ? null : [masters.length,
    masters.filter((m) => m.status === "active").length, masters.filter((m) => m.status === "archived").length,
    masters.filter((m) => m.business_type === "regular").length, masters.filter((m) => m.business_type === "one_time").length];
  const totalPages = Math.max(1, Math.ceil(filtered.length / 10));
  const currentPage = Math.min(page, totalPages);
  const visible = filtered.slice((currentPage - 1) * 10, currentPage * 10);
  function clearFilters() { setSearch(""); setBusinessType("all"); setStatus("active"); setCity(""); setPage(1); }
  function changeScope(value: string) {
    if (busy) return;
    ++listRequest.current;
    setSelectedAddaId(value); setMasters(null); setLoading(false); setModal(null); setSelectedMaster(null);
    setLoadError(""); setActionError(""); setNotice(""); clearFilters();
  }
  function viewAccount(id: string, name: string) {
    setModal(null); setSelectedMaster({ id, name });
    if (onViewAccount) onViewAccount(id);
    else router.push(`/other-adda-account?otherAddaId=${encodeURIComponent(id)}`);
  }
  function useExisting(match: OtherAddaDuplicate) { viewAccount(match.id, match.adda_name); }
  const closeModal = useCallback(() => { if (!formBusy) setModal(null); }, [formBusy]);
  async function lifecycle(master: OtherAdda) {
    if (!canManage || mutationLock.current || busy || master.adda_id !== scope) return;
    if (master.status === "active" && !window.confirm(`Archive ${master.adda_name}? History will remain available.`)) return;
    mutationLock.current = true; setPendingId(master.id); setActionError(""); setNotice("");
    try {
      await setOtherAddaStatus({ other_adda_id: master.id, status: master.status === "active" ? "archived" : "active" });
      setNotice(master.status === "active" ? "Other Adda archived. History is preserved." : "Other Adda reactivated with the same account history.");
      try { await loadMasters(); } catch { setNotice("Status changed, but the refreshed list could not be loaded. Retry the list."); }
    } catch (failure) {
      const mapped = mapOtherAddaError(failure); console.error("Other Adda lifecycle failed", mapped);
      setActionError(mapped.reason === "gross_obligations_outstanding"
        ? "This Other Adda still has outstanding LENA/DENA entries. Review the account before archiving." : mapped.message);
    } finally { mutationLock.current = false; setPendingId(null); }
  }
  function saved(id: string) {
    setModal(null); setSelectedMaster(null); setNotice(`Other Adda saved. Account ID: ${id}`);
    void loadMasters().catch(() => setNotice("Other Adda was saved, but the refreshed list failed. Retry the list; do not create it again."));
  }

  return <main dir={dir} className="ut-module-page mx-auto max-w-[1500px] space-y-6 text-slate-950">
    <header className="flex flex-col justify-between gap-4 rounded-2xl border border-blue-100 bg-white p-4 shadow-sm sm:p-5 lg:flex-row lg:items-center">
      <ModulePageHeading icon="otherAdda" accent="purple" title="Other Adda" description="Manage Regular and One-Time Other Addas. Historical accounts are retained." />
      {canManage && <div className="flex flex-wrap gap-2">
        <button type="button" disabled={!scope || masters === null || busy} onClick={() => setModal({ master: null, businessType: "regular" })} className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-3 font-bold text-white disabled:bg-blue-400"><Plus size={18} /> Add Other Adda</button>
        <button type="button" disabled={!scope || masters === null || busy} onClick={() => setModal({ master: null, businessType: "one_time" })} className={button}><Plus size={18} className="inline" /> Quick Add One-Time</button>
      </div>}
    </header>
    {contextLoading && <p role="status" className="rounded-xl border bg-white p-6 font-bold">Loading your access…</p>}
    {contextError && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-5 font-semibold text-red-800">{contextError}<button type="button" onClick={() => void loadContext()} className={`${button} ms-3`}>Retry Access</button></div>}
    {superAdmin && <section className="rounded-xl border border-blue-200 bg-white p-5 shadow-sm"><label htmlFor="oa-adda-scope" className="block font-bold">Select Adda<select id="oa-adda-scope" value={selectedAddaId} disabled={busy} onChange={(e) => changeScope(e.target.value)} className={`${control} mt-2 max-w-xl`}><option value="">Select Adda</option>{addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}</select></label>{!addas.length && <p className="mt-3 font-semibold">No accessible Addas are available.</p>}</section>}
    {profile && !scope && <p role="status" className="rounded-xl border border-blue-200 bg-blue-50 p-6 font-bold text-blue-900">Select Adda to view Other Addas</p>}
    {scope && <>
      <section aria-label="Other Adda master counts" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">{["Total Other Addas", "Active", "Archived", "Regular", "One-Time"].map((label, index) => { const SummaryIcon = [Building2, Check, Archive, Building2, Building2][index]; const tone = ["bg-blue-600", "bg-emerald-600", "bg-slate-600", "bg-cyan-600", "bg-violet-600"][index]; return <article key={label} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5"><div className="flex items-center gap-3"><span className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${tone} text-white`}><SummaryIcon size={20} aria-hidden="true" /></span><div><p className="text-sm font-semibold text-slate-600">{label}</p><p dir="ltr" className="mt-1 text-2xl font-extrabold text-slate-900">{summaries ? summaries[index] : "—"}</p></div></div></article>; })}</section>
      {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 font-semibold text-emerald-900">{notice}</p>}
      {actionError && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{actionError}</p>}
      {selectedMaster && <section role="status" className="rounded-xl border border-blue-200 bg-blue-50 p-4"><p className="font-bold">Selected account: {selectedMaster.name}</p><p className="mt-1 break-all text-sm" dir="ltr">{selectedMaster.id}</p></section>}
      <section className="rounded-xl border border-blue-100 bg-white p-5 shadow-sm"><h2 className="text-xl font-extrabold">Search & Filters</h2><div className="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-[2fr_1fr_1fr_1fr_auto]">

        <VoiceTypingField fieldLabel="Name, contact, mobile, city or NTN/CNIC" mode="phone"><label className="font-bold" htmlFor="oa-search">Search<input id="oa-search" type="search" value={search} disabled={masters === null} placeholder="Name, contact, mobile, city or NTN/CNIC" onChange={(e) => { setSearch(e.target.value); setPage(1); }} className={`${control} mt-2`} /></label></VoiceTypingField>

        <label className="font-bold" htmlFor="oa-type">Business Type<select id="oa-type" value={businessType} onChange={(e) => { setBusinessType(e.target.value as OtherAddaBusinessType | "all"); setPage(1); }} className={`${control} mt-2`}><option value="all">All</option><option value="regular">Regular</option><option value="one_time">One-Time</option></select></label>
        <label className="font-bold" htmlFor="oa-status">Status<select id="oa-status" value={status} onChange={(e) => { setStatus(e.target.value as OtherAddaStatus | "all"); setPage(1); }} className={`${control} mt-2`}><option value="active">Active</option><option value="archived">Archived</option><option value="all">All</option></select></label>
        <label className="font-bold" htmlFor="oa-city">City<select id="oa-city" value={city} onChange={(e) => { setCity(e.target.value); setPage(1); }} className={`${control} mt-2`}><option value="">All Cities</option>{cities.map((name) => <option key={name} value={name}>{name}</option>)}</select></label>
        <button type="button" onClick={clearFilters} className={`${button} self-end`}>Reset</button>
      </div></section>
      <section className="overflow-hidden rounded-xl border border-blue-100 bg-white shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b p-4"><h2 className="text-xl font-extrabold">Other Addas</h2><button type="button" disabled={loading || busy} onClick={() => void loadMasters().catch(() => undefined)} className={button}><RefreshCw size={16} className="me-2 inline" />Refresh</button></div>
        {loadError && <div role="alert" className="m-4 rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{loadError}<button type="button" disabled={loading || busy} onClick={() => void loadMasters().catch(() => undefined)} className={`${button} ms-3`}>Retry</button></div>}
        <div className="overflow-x-auto"><table className="w-full min-w-[1000px]"><thead className="bg-blue-600 text-white"><tr>{["Adda Name", "Contact Person", "Mobile", "City", "Business Type", "Status", "Actions"].map((label) => <th key={label} className="p-4 text-start font-bold">{label}</th>)}</tr></thead><tbody>
          {loading && <tr><td colSpan={7} role="status" className="p-10 text-center font-bold">Loading Other Addas…</td></tr>}
          {!loading && !loadError && masters !== null && !visible.length && <tr><td colSpan={7} className="p-10 text-center"><p className="font-bold">{masters.length ? "No Other Addas match these filters." : "No Other Addas yet."}</p><p className="mt-2">{masters.length ? "Try changing the filters." : canManage ? "Add a Regular or One-Time Other Adda to get started." : "Ask your Adda Admin to add an Other Adda."}</p></td></tr>}
          {!loading && !loadError && visible.map((master) => <tr key={master.id} className="border-b hover:bg-blue-50/50"><td className="p-4 font-extrabold">{master.adda_name}</td><td className="p-4">{master.contact_person || "—"}</td><td className="p-4" dir="ltr">{master.mobile || "—"}</td><td className="p-4">{master.city || "—"}</td><td className="p-4"><span className="rounded-full border border-blue-200 bg-blue-50 px-3 py-1 text-sm font-bold text-blue-900">{master.business_type === "regular" ? "Regular" : "One-Time"}</span></td><td className="p-4"><span className={`rounded-full border px-3 py-1 text-sm font-bold ${master.status === "active" ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-amber-200 bg-amber-50 text-amber-900"}`}>{master.status === "active" ? "Active" : "Archived"}</span></td><td className="p-4"><div className="flex flex-wrap gap-2">
            <button type="button" disabled={busy} onClick={() => viewAccount(master.id, master.adda_name)} className={button}><Eye size={16} className="me-1 inline" />View Account</button>
            {canManage && <><button type="button" disabled={busy} onClick={() => setModal({ master, businessType: master.business_type })} className={button}><Pencil size={16} className="me-1 inline" />Edit</button><button type="button" disabled={busy} onClick={() => void lifecycle(master)} className={button}><Archive size={16} className="me-1 inline" />{pendingId === master.id ? "Working…" : master.status === "active" ? "Archive" : "Reactivate"}</button></>}
          </div></td></tr>)}
        </tbody></table></div>
      </section>
      {masters !== null && !loading && !loadError && <nav aria-label="Other Adda pagination" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-white p-4"><p className="font-bold">{filtered.length} matching · Page {currentPage} of {totalPages}</p><div className="flex gap-2"><button type="button" disabled={currentPage === 1} onClick={() => setPage(currentPage - 1)} className={button}>Previous</button><button type="button" disabled={currentPage === totalPages} onClick={() => setPage(currentPage + 1)} className={button}>Next</button></div></nav>}
    </>}
    {modal && canManage && scope && <OtherAddaFormModal key={`${scope}:${modal.master?.id ?? modal.businessType}`} master={modal.master} initialBusinessType={modal.businessType}
      targetAddaId={superAdmin ? selectedAddaId : undefined} canReactivate={canManage} onClose={closeModal} onSaved={saved}
      onUseExisting={useExisting} onBusyChange={setFormBusy} onRefresh={loadMasters} />}
  </main>;
}
