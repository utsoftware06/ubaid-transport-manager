"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

const PAGE_SIZE = 10;
type ProfileRow = { adda_id: string | null };
type VehicleRow = {
  id: string;
  adda_id: string;
  vehicle_no: string;
  vehicle_type: string | null;
  model: string | null;
  owner_name: string | null;
  created_at: string | null;
};

function isLinkedRecordError(error: { code?: string | null }) {
  return error.code === "23503";
}

export default function VehiclesPage() {
  const { t, dir } = useLanguage();
  const [currentAddaId, setCurrentAddaId] = useState("");
  const [vehicleNo, setVehicleNo] = useState("");
  const [vehicleType, setVehicleType] = useState("");
  const [model, setModel] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [vehicles, setVehicles] = useState<VehicleRow[]>([]);
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  const vehicleTypes = useMemo(
    () =>
      Array.from(new Set(vehicles.map((vehicle) => vehicle.vehicle_type?.trim()).filter(Boolean) as string[]))
        .sort((first, second) => first.localeCompare(second)),
    [vehicles]
  );
  const filteredVehicles = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return vehicles.filter((vehicle) => {
      const matchesSearch =
        !keyword ||
        [vehicle.vehicle_no, vehicle.vehicle_type, vehicle.model, vehicle.owner_name]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(keyword);
      return matchesSearch && (!typeFilter || vehicle.vehicle_type === typeFilter);
    });
  }, [search, typeFilter, vehicles]);
  const totalPages = Math.max(1, Math.ceil(filteredVehicles.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visibleVehicles = filteredVehicles.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);

  const loadVehicles = useCallback(async () => {
    setIsLoading(true);
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) {
      console.error("Unable to verify current user:", authError);
      alert(t("common.messages.loadFailed"));
      setIsLoading(false);
      return;
    }
    const { data: profileData, error: profileError } = await supabase
      .from("profiles").select("adda_id").eq("id", authData.user.id).maybeSingle();
    const profile = profileData as ProfileRow | null;
    if (profileError || !profile?.adda_id) {
      console.error("Unable to load vehicle tenant context:", profileError);
      alert(t("common.messages.loadFailed"));
      setIsLoading(false);
      return;
    }
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, adda_id, vehicle_no, vehicle_type, model, owner_name, created_at")
      .eq("adda_id", profile.adda_id)
      .order("created_at", { ascending: false });
    if (error) {
      console.error("Unable to load vehicles:", error);
      alert(t("common.messages.loadFailed"));
    } else {
      setCurrentAddaId(profile.adda_id);
      setVehicles((data ?? []) as VehicleRow[]);
    }
    setIsLoading(false);
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadVehicles(), 0);
    return () => window.clearTimeout(timer);
  }, [loadVehicles]);

  function resetForm() {
    setEditingId(null);
    setVehicleNo("");
    setVehicleType("");
    setModel("");
    setOwnerName("");
  }

  function startEdit(vehicle: VehicleRow) {
    setEditingId(vehicle.id);
    setVehicleNo(vehicle.vehicle_no);
    setVehicleType(vehicle.vehicle_type ?? "");
    setModel(vehicle.model ?? "");
    setOwnerName(vehicle.owner_name ?? "");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function handleSaveVehicle(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (isSaving) return;
    if (!vehicleNo.trim() || !currentAddaId) {
      alert(t("vehicles.validation.required"));
      return;
    }
    setIsSaving(true);
    const values = {
      adda_id: currentAddaId,
      vehicle_no: vehicleNo.trim(),
      vehicle_type: vehicleType.trim(),
      model: model.trim(),
      owner_name: ownerName.trim(),
    };
    const { error } = editingId
      ? await supabase.from("vehicles").update(values).eq("id", editingId).eq("adda_id", currentAddaId)
      : await supabase.from("vehicles").insert(values);
    if (error) {
      console.error("Unable to save vehicle:", error);
      alert(t("common.messages.saveFailed"));
    } else {
      alert(t(editingId ? "vehicles.messages.updatedSuccessfully" : "vehicles.messages.savedSuccessfully"));
      resetForm();
      await loadVehicles();
    }
    setIsSaving(false);
  }

  async function handleDelete(vehicle: VehicleRow) {
    if (deletingId || !window.confirm(t("vehicles.deleteConfirm"))) return;
    setDeletingId(vehicle.id);
    const { error } = await supabase.from("vehicles").delete().eq("id", vehicle.id).eq("adda_id", currentAddaId);
    if (error) {
      console.error("Unable to delete vehicle:", error);
      alert(t(isLinkedRecordError(error) ? "vehicles.messages.linkedRecords" : "common.messages.deleteFailed"));
    } else {
      if (editingId === vehicle.id) resetForm();
      setVehicles((current) => current.filter((item) => item.id !== vehicle.id));
      alert(t("vehicles.messages.deletedSuccessfully"));
    }
    setDeletingId(null);
  }

  return (
    <main dir={dir} className="ut-module-page p-0 text-gray-900">
      <div className="mx-auto max-w-7xl space-y-5">
        <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <div className="mb-6"><ModulePageHeading icon="vehicle" accent="orange" title={t(editingId ? "vehicles.edit" : "vehicles.addNew")} /></div>




          <form onSubmit={handleSaveVehicle} className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <VoiceTypingField fieldLabel={t("vehicles.vehicleNumber")} mode="identifier"><input required dir="ltr" aria-label={t("vehicles.vehicleNumber")} placeholder={t("vehicles.vehicleNumber")} value={vehicleNo} onChange={(e) => setVehicleNo(e.target.value)} className="rounded-lg border p-3" /></VoiceTypingField>
            <VoiceTypingField fieldLabel={t("vehicles.vehicleType")} mode="text"><input aria-label={t("vehicles.vehicleType")} placeholder={t("vehicles.vehicleType")} value={vehicleType} onChange={(e) => setVehicleType(e.target.value)} className="rounded-lg border p-3" /></VoiceTypingField>
            <VoiceTypingField fieldLabel={t("vehicles.model")} mode="text"><input aria-label={t("vehicles.model")} placeholder={t("vehicles.model")} value={model} onChange={(e) => setModel(e.target.value)} className="rounded-lg border p-3" /></VoiceTypingField>
            <VoiceTypingField fieldLabel={t("vehicles.ownerName")} mode="text"><input aria-label={t("vehicles.ownerName")} placeholder={t("vehicles.ownerName")} value={ownerName} onChange={(e) => setOwnerName(e.target.value)} className="rounded-lg border p-3" /></VoiceTypingField>
            <div className="flex flex-wrap gap-3 md:col-span-2">
              <button type="submit" disabled={isSaving || isLoading} className="rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white disabled:opacity-60">{isSaving ? t("common.states.saving") : t(editingId ? "common.actions.update" : "vehicles.save")}</button>
              {editingId && <button type="button" onClick={resetForm} disabled={isSaving} className="rounded-lg border px-6 py-3 font-semibold">{t("common.actions.cancel")}</button>}
            </div>
          </form>

        </section>

        <section className="rounded-xl border bg-white p-5 shadow-lg md:p-8">
          <h2 className="mb-4 text-2xl font-bold">{t("vehicles.myVehicles")}</h2>

          <div className="mb-4 grid grid-cols-1 gap-3 md:grid-cols-[1fr_240px_auto]">
            <VoiceTypingField fieldLabel={t("vehicles.searchPlaceholder")} mode="text"><input type="search" aria-label={t("vehicles.searchPlaceholder")} placeholder={t("vehicles.searchPlaceholder")} value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="rounded-lg border p-3" /></VoiceTypingField>
            <select aria-label={t("vehicles.filters.type")} value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1); }} className="rounded-lg border bg-white p-3"><option value="">{t("vehicles.filters.allTypes")}</option>{vehicleTypes.map((type) => <option key={type} value={type}>{type}</option>)}</select>
            <button type="button" onClick={() => { setSearch(""); setTypeFilter(""); setPage(1); }} className="rounded-lg border px-5 py-3 font-semibold">{t("common.actions.reset")}</button>
          </div>

          {isLoading ? <p className="p-8 text-center">{t("common.loading")}</p> : visibleVehicles.length === 0 ? <p className="p-8 text-center">{t("vehicles.empty")}</p> : (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              {visibleVehicles.map((vehicle) => <article key={vehicle.id} className="rounded-lg border p-4 shadow-sm">
                <h3 dir="ltr" className="text-xl font-semibold">{vehicle.vehicle_no}</h3>
                <p>{t("vehicles.type")}: {vehicle.vehicle_type || "-"}</p><p>{t("vehicles.model")}: {vehicle.model || "-"}</p><p>{t("vehicles.owner")}: {vehicle.owner_name || "-"}</p>
                <div className="mt-4 flex gap-2"><button type="button" aria-label={`${t("common.actions.edit")} ${vehicle.vehicle_no}`} onClick={() => startEdit(vehicle)} className="rounded bg-blue-600 px-3 py-2 font-semibold text-white">{t("common.actions.edit")}</button><button type="button" aria-label={`${t("common.actions.delete")} ${vehicle.vehicle_no}`} disabled={deletingId !== null} onClick={() => void handleDelete(vehicle)} className="rounded bg-red-600 px-3 py-2 font-semibold text-white disabled:opacity-60">{deletingId === vehicle.id ? t("common.states.deleting") : t("common.actions.delete")}</button></div>
              </article>)}
            </div>
          )}
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <span>{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span>
            <div className="flex gap-2"><button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button><button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button></div>
          </div>
        </section>
      </div>
    </main>
  );
}
