"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

const PAGE_SIZE = 10;

type AddaRecord = {
  id: string;
  name: string;
  city: string | null;
  address: string | null;
  phone: string | null;
  created_at: string | null;
};

function isLinkedRecordError(error: unknown) {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "23503"
  );
}

export default function AddasPage() {
  const { t, dir } = useLanguage();
  const [addas, setAddas] = useState<AddaRecord[]>([]);
  const [addaName, setAddaName] = useState("");
  const [city, setCity] = useState("");
  const [address, setAddress] = useState("");
  const [phone, setPhone] = useState("");
  const [search, setSearch] = useState("");
  const [cityFilter, setCityFilter] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const mutationInFlightRef = useRef(false);

  const cities = useMemo(
    () =>
      Array.from(
        new Set(addas.map((adda) => adda.city?.trim()).filter(Boolean) as string[])
      ).sort((first, second) => first.localeCompare(second)),
    [addas]
  );

  const filteredAddas = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return addas.filter((adda) => {
      const matchesSearch =
        !keyword ||
        [adda.name, adda.city, adda.address, adda.phone]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(keyword);
      return matchesSearch && (!cityFilter || adda.city === cityFilter);
    });
  }, [addas, cityFilter, search]);

  const totalPages = Math.max(1, Math.ceil(filteredAddas.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visibleAddas = filteredAddas.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE
  );

  const loadAddas = useCallback(async () => {
    setIsLoading(true);
    const { data, error } = await supabase
      .from("addas")
      .select("id, name, city, address, phone, created_at")
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Unable to load addas:", error);
      alert(t("common.messages.loadFailed"));
    } else {
      setAddas((data ?? []) as AddaRecord[]);
    }
    setIsLoading(false);
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadAddas(), 0);
    return () => window.clearTimeout(timer);
  }, [loadAddas]);

  function resetForm() {
    setEditingId(null);
    setAddaName("");
    setCity("");
    setAddress("");
    setPhone("");
  }

  function startEdit(adda: AddaRecord) {
    setEditingId(adda.id);
    setAddaName(adda.name);
    setCity(adda.city ?? "");
    setAddress(adda.address ?? "");
    setPhone(adda.phone ?? "");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function handleSaveAdda() {
    if (!addaName.trim() || mutationInFlightRef.current) {
      if (!addaName.trim()) alert(t("addas.validation.nameRequired"));
      return;
    }

    mutationInFlightRef.current = true;
    setIsSaving(true);
    try {
      const values = {
        name: addaName.trim(),
        city: city.trim(),
        address: address.trim(),
        phone: phone.trim(),
      };
      const { error } = editingId
        ? await supabase.from("addas").update(values).eq("id", editingId)
        : await supabase.from("addas").insert(values);

      if (error) throw error;

      alert(t(editingId ? "addas.messages.updated" : "addas.messages.saved"));
      resetForm();
      await loadAddas();
    } catch (error) {
      console.error("Unable to save adda:", error);
      alert(t("common.messages.saveFailed"));
    } finally {
      mutationInFlightRef.current = false;
      setIsSaving(false);
    }
  }

  async function handleDelete(adda: AddaRecord) {
    if (
      mutationInFlightRef.current ||
      !window.confirm(t("addas.deleteConfirm"))
    ) return;

    mutationInFlightRef.current = true;
    setDeletingId(adda.id);
    try {
      const { error } = await supabase
        .from("addas")
        .delete()
        .eq("id", adda.id);

      if (error) throw error;

      if (editingId === adda.id) resetForm();
      setAddas((current) => current.filter((item) => item.id !== adda.id));
      alert(t("addas.messages.deleted"));
    } catch (error) {
      console.error("Unable to delete adda:", error);
      alert(
        t(
          isLinkedRecordError(error)
            ? "addas.messages.linkedRecords"
            : "common.messages.deleteFailed"
        )
      );
    } finally {
      mutationInFlightRef.current = false;
      setDeletingId(null);
    }
  }

  function resetFilters() {
    setSearch("");
    setCityFilter("");
    setPage(1);
  }

  return (
    <main dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-5 text-gray-900">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="addas" accent="cyan" title={t("addas.title")} />
      </header>
      <section className="rounded-xl bg-white p-5 shadow-md md:p-8">
        <h2 className="mb-6 text-2xl font-bold">
          {t(editingId ? "addas.edit" : "addas.create")}
        </h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {[
            [t("addas.name"), addaName, setAddaName, false],
            [t("addas.city"), city, setCity, false],
            [t("addas.phone"), phone, setPhone, true],
            [t("addas.address"), address, setAddress, false],
          ].map(([label, value, setter, isTechnical]) => (

            <label key={String(label)} className="block text-sm font-semibold text-slate-700">
              <span className="mb-1.5 block">{String(label)}</span>
              {isTechnical ? (
                <VoiceTypingField fieldLabel={String(label)} mode="text"><input
                  type="text"
                  aria-label={String(label)}
                  placeholder={String(label)}
                  value={String(value)}
                  dir="ltr"
                  onChange={(event) =>
                    (setter as React.Dispatch<React.SetStateAction<string>>)(
                      event.target.value
                    )
                  }
                  className="w-full rounded-lg border p-3 text-gray-900 placeholder:text-gray-500"
                /></VoiceTypingField>
              ) : (
                <VoiceTypingField fieldLabel={String(label)} value={String(value)} onValueChange={(next) => (setter as React.Dispatch<React.SetStateAction<string>>)(next)} contextKey={editingId ?? "new"}>
                  <input
                    type="text"
                    aria-label={String(label)}
                    placeholder={String(label)}
                    value={String(value)}
                    onChange={(event) =>
                      (setter as React.Dispatch<React.SetStateAction<string>>)(
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border p-3 text-gray-900 placeholder:text-gray-500"
                  />
                </VoiceTypingField>
              )}
            </label>

          ))}
        </div>
        <div className="mt-6 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={() => void handleSaveAdda()}
            disabled={isSaving}
            className="rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white disabled:opacity-60"
          >
            {isSaving
              ? t("common.states.saving")
              : t(editingId ? "common.actions.update" : "addas.save")}
          </button>
          {editingId && (
            <button
              type="button"
              onClick={resetForm}
              disabled={isSaving}
              className="rounded-lg border border-gray-300 px-6 py-3 font-semibold"
            >
              {t("common.actions.cancel")}
            </button>
          )}
        </div>

        <div className="mt-10">
          <h2 className="mb-4 text-2xl font-bold">{t("addas.list")}</h2>

          <div className="mb-4 grid grid-cols-1 gap-3 md:grid-cols-[1fr_240px_auto]">
            <VoiceTypingField fieldLabel={t("addas.searchPlaceholder")} mode="text"><input
              type="search"
              aria-label={t("addas.searchPlaceholder")}
              placeholder={t("addas.searchPlaceholder")}
              value={search}
              onChange={(event) => {
                setSearch(event.target.value);
                setPage(1);
              }}
              className="rounded-lg border p-3"
            /></VoiceTypingField>
            <select
              aria-label={t("addas.filters.city")}
              value={cityFilter}
              onChange={(event) => {
                setCityFilter(event.target.value);
                setPage(1);
              }}
              className="rounded-lg border bg-white p-3"
            >
              <option value="">{t("addas.filters.allCities")}</option>
              {cities.map((item) => (
                <option key={item} value={item}>{item}</option>
              ))}
            </select>
            <button type="button" onClick={resetFilters} className="rounded-lg border px-5 py-3 font-semibold">
              {t("common.actions.reset")}
            </button>
          </div>

          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full min-w-[800px] bg-white">
              <thead className="bg-blue-600 text-white">
                <tr>
                  <th className="p-3 text-start">{t("addas.name")}</th>
                  <th className="p-3 text-start">{t("addas.city")}</th>
                  <th className="p-3 text-start">{t("addas.phone")}</th>
                  <th className="p-3 text-start">{t("addas.address")}</th>
                  <th className="p-3 text-start">{t("common.actions.title")}</th>
                </tr>
              </thead>
              <tbody>
                {isLoading && <tr><td colSpan={5} className="p-8 text-center">{t("common.loading")}</td></tr>}
                {!isLoading && visibleAddas.length === 0 && <tr><td colSpan={5} className="p-8 text-center">{t("addas.empty")}</td></tr>}
                {!isLoading && visibleAddas.map((adda) => (
                  <tr key={adda.id} className="border-b hover:bg-gray-50">
                    <td className="p-3 font-medium">{adda.name}</td>
                    <td className="p-3">{adda.city || "-"}</td>
                    <td dir="ltr" className="p-3">{adda.phone || "-"}</td>
                    <td className="p-3">{adda.address || "-"}</td>
                    <td className="p-3">
                      <div className="flex flex-wrap gap-2">
                        <button type="button" aria-label={`${t("common.actions.edit")} ${adda.name}`} onClick={() => startEdit(adda)} className="rounded bg-blue-600 px-3 py-2 font-semibold text-white">{t("common.actions.edit")}</button>
                        <button type="button" aria-label={`${t("common.actions.delete")} ${adda.name}`} disabled={deletingId !== null} onClick={() => void handleDelete(adda)} className="rounded bg-red-600 px-3 py-2 font-semibold text-white disabled:opacity-60">{deletingId === adda.id ? t("common.states.deleting") : t("common.actions.delete")}</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <span>{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span>
            <div className="flex gap-2">
              <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button>
              <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
