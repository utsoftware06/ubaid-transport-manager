"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Plus } from "lucide-react";

import PartiesTable from "@/components/parties/PartiesTable";
import PartyFormModal from "@/components/parties/PartyFormModal";
import PartySummaryCards from "@/components/parties/PartySummaryCards";
import { USER_ROLES, type UserRole } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { supabase } from "@/lib/supabase/client";
import type {
  PartyAddaOption,
  PartyFormValues,
  PartyRecord,
} from "@/types/parties";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

const PAGE_SIZE = 10;

type ProfileContext = {
  role: UserRole;
  addaId: string | null;
};

type ProfileRow = {
  role: string | null;
  adda_id: string | null;
};

type StatusFilter = "all" | "active" | "inactive";

function isLinkedRecordError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "23503"
  );
}

export default function PartiesManager() {
  const { t, dir } = useLanguage();
  const [parties, setParties] = useState<PartyRecord[]>([]);
  const [addas, setAddas] = useState<PartyAddaOption[]>([]);
  const [profile, setProfile] = useState<ProfileContext | null>(null);
  const [search, setSearch] = useState("");
  const [cityFilter, setCityFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingParty, setEditingParty] = useState<PartyRecord | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [pendingPartyId, setPendingPartyId] = useState<string | null>(null);
  const mutationRef = useRef(false);

  const loadParties = useCallback(async () => {
    setIsLoading(true);
    setLoadError("");
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) throw authError ?? new Error("No authenticated user");

      const { data: profileData, error: profileError } = await supabase
        .from("profiles")
        .select("role, adda_id")
        .eq("id", authData.user.id)
        .single();
      if (profileError) throw profileError;

      const row = profileData as ProfileRow;
      if (
        row.role !== USER_ROLES.superAdmin &&
        row.role !== USER_ROLES.addaAdmin &&
        row.role !== USER_ROLES.operator
      ) {
        throw new Error("Unsupported profile role");
      }
      if (row.role !== USER_ROLES.superAdmin && !row.adda_id) {
        throw new Error("Assigned Adda is unavailable");
      }

      const currentProfile: ProfileContext = {
        role: row.role,
        addaId: row.adda_id,
      };
      setProfile(currentProfile);

      let partiesQuery = supabase
        .from("parties")
        .select("id, adda_id, name, phone, city, address, is_active, created_at, updated_at")
        .order("created_at", { ascending: false });

      if (currentProfile.addaId) {
        partiesQuery = partiesQuery.eq("adda_id", currentProfile.addaId);
      }

      const [partyResult, addaResult] = await Promise.all([
        partiesQuery,
        supabase.from("addas").select("id, name").order("name"),
      ]);
      if (partyResult.error) throw partyResult.error;
      if (addaResult.error) throw addaResult.error;

      setParties((partyResult.data ?? []) as PartyRecord[]);
      setAddas((addaResult.data ?? []) as PartyAddaOption[]);
    } catch (error) {
      console.error("Unable to load Party Master:", error);
      setParties([]);
      setAddas([]);
      setLoadError(t("parties.messages.loadFailed"));
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadParties(), 0);
    return () => window.clearTimeout(timer);
  }, [loadParties]);

  const cities = useMemo(
    () =>
      Array.from(
        new Set(
          parties
            .map((party) => party.city?.trim())
            .filter((city): city is string => Boolean(city))
        )
      ).sort((first, second) => first.localeCompare(second)),
    [parties]
  );

  const filteredParties = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase();
    return parties.filter((party) => {
      const matchesSearch =
        !keyword ||
        [party.name, party.phone, party.city, party.address]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase()
          .includes(keyword);
      const matchesCity = !cityFilter || party.city === cityFilter;
      const matchesStatus =
        statusFilter === "all" ||
        (statusFilter === "active" ? party.is_active : !party.is_active);
      return matchesSearch && matchesCity && matchesStatus;
    });
  }, [cityFilter, parties, search, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredParties.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visibleParties = filteredParties.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE
  );

  const summary = useMemo(
    () => ({
      total: parties.length,
      active: parties.filter((party) => party.is_active).length,
      inactive: parties.filter((party) => !party.is_active).length,
      cities: cities.length,
    }),
    [cities.length, parties]
  );

  function resetFilters() {
    setSearch("");
    setCityFilter("");
    setStatusFilter("all");
    setPage(1);
  }

  function openCreateModal() {
    setEditingParty(null);
    setIsModalOpen(true);
  }

  function openEditModal(party: PartyRecord) {
    setEditingParty(party);
    setIsModalOpen(true);
  }

  const closeModal = useCallback(() => {
    if (isSaving) return;
    setIsModalOpen(false);
    setEditingParty(null);
  }, [isSaving]);

  async function handleSave(values: PartyFormValues) {
    if (mutationRef.current || !profile) return;
    const targetAddaId = profile.addaId ?? values.addaId;
    if (!targetAddaId || !addas.some((adda) => adda.id === targetAddaId)) {
      alert(t("parties.validation.addaRequired"));
      return;
    }

    mutationRef.current = true;
    setIsSaving(true);
    try {
      const payload = {
        name: values.name,
        phone: values.phone || null,
        city: values.city || null,
        address: values.address || null,
        adda_id: targetAddaId,
        is_active: values.isActive,
      };

      let mutationResult;
      if (editingParty) {
        let updateQuery = supabase
          .from("parties")
          .update(payload)
          .eq("id", editingParty.id);
        if (profile.addaId) {
          updateQuery = updateQuery.eq("adda_id", profile.addaId);
        }
        mutationResult = await updateQuery.select("id").maybeSingle();
      } else {
        mutationResult = await supabase
          .from("parties")
          .insert(payload)
          .select("id")
          .single();
      }

      const { data, error } = mutationResult;
      if (error) throw error;
      if (!data) throw new Error("Party mutation did not affect a record");

      alert(t(editingParty ? "parties.messages.updated" : "parties.messages.created"));
      setIsModalOpen(false);
      setEditingParty(null);
      await loadParties();
    } catch (error) {
      console.error("Unable to save party:", error);
      alert(t("parties.messages.saveFailed"));
    } finally {
      mutationRef.current = false;
      setIsSaving(false);
    }
  }

  async function handleToggleStatus(party: PartyRecord) {
    if (
      mutationRef.current ||
      !window.confirm(
        t(
          party.is_active
            ? "parties.confirm.deactivate"
            : "parties.confirm.activate"
        )
      )
    ) return;

    mutationRef.current = true;
    setPendingPartyId(party.id);
    try {
      let query = supabase
        .from("parties")
        .update({ is_active: !party.is_active })
        .eq("id", party.id);
      if (profile?.addaId) query = query.eq("adda_id", profile.addaId);
      const { data, error } = await query.select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("Party status update did not affect a record");
      setParties((current) =>
        current.map((item) =>
          item.id === party.id ? { ...item, is_active: !item.is_active } : item
        )
      );
      alert(
        t(
          party.is_active
            ? "parties.messages.deactivated"
            : "parties.messages.activated"
        )
      );
    } catch (error) {
      console.error("Unable to change party status:", error);
      alert(t("parties.messages.statusFailed"));
    } finally {
      mutationRef.current = false;
      setPendingPartyId(null);
    }
  }

  async function handleDelete(party: PartyRecord) {
    if (mutationRef.current || !window.confirm(t("parties.confirm.delete"))) return;
    mutationRef.current = true;
    setPendingPartyId(party.id);
    try {
      let query = supabase.from("parties").delete().eq("id", party.id);
      if (profile?.addaId) query = query.eq("adda_id", profile.addaId);
      const { data, error } = await query.select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("Party deletion did not affect a record");
      setParties((current) => current.filter((item) => item.id !== party.id));
      alert(t("parties.messages.deleted"));
    } catch (error) {
      console.error("Unable to delete party:", error);
      alert(
        t(
          isLinkedRecordError(error)
            ? "parties.messages.linkedRecords"
            : "parties.messages.deleteFailed"
        )
      );
    } finally {
      mutationRef.current = false;
      setPendingPartyId(null);
    }
  }

  return (
    <main dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-6 text-slate-900">
      <header className="flex flex-col justify-between gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:flex-row sm:items-center sm:p-5">
        <ModulePageHeading icon="parties" accent="green" title={t("parties.title")} description={t("parties.description")} />
        <button
          type="button"
          onClick={openCreateModal}
          disabled={isLoading || addas.length === 0}
          className="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-5 py-3 font-bold text-white hover:bg-blue-700 focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:bg-blue-400"
        >
          <Plus className="h-5 w-5" aria-hidden="true" />
          {t("parties.actions.add")}
        </button>
      </header>

      <PartySummaryCards {...summary} />

      {loadError && (
        <div role="alert" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-700">
          <span>{loadError}</span>
          <button type="button" onClick={() => void loadParties()} className="rounded-lg border border-red-300 bg-white px-4 py-2 font-bold">
            {t("parties.actions.retry")}
          </button>
        </div>
      )}

      <section aria-labelledby="party-filters-title" className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <h2 id="party-filters-title" className="text-xl font-extrabold">{t("parties.filters.title")}</h2>
        <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-[1fr_220px_220px_auto]">

          <div>
            <label htmlFor="party-search" className="mb-2 block font-bold">{t("parties.filters.search")}</label>
            <VoiceTypingField fieldLabel={t("parties.placeholders.search")} mode="text"><input
              id="party-search"
              type="search"
              value={search}
              onChange={(event) => {
                setSearch(event.target.value);
                setPage(1);
              }}
              placeholder={t("parties.placeholders.search")}
              className="w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-900 placeholder:text-slate-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            /></VoiceTypingField>
          </div>

          <div>
            <label htmlFor="party-city-filter" className="mb-2 block font-bold">{t("parties.filters.city")}</label>
            <select
              id="party-city-filter"
              value={cityFilter}
              onChange={(event) => {
                setCityFilter(event.target.value);
                setPage(1);
              }}
              className="w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-900"
            >
              <option value="">{t("parties.filters.allCities")}</option>
              {cities.map((city) => <option key={city} value={city}>{city}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="party-status-filter" className="mb-2 block font-bold">{t("parties.filters.status")}</label>
            <select
              id="party-status-filter"
              value={statusFilter}
              onChange={(event) => {
                setStatusFilter(event.target.value as StatusFilter);
                setPage(1);
              }}
              className="w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-900"
            >
              <option value="all">{t("parties.filters.allStatuses")}</option>
              <option value="active">{t("parties.status.active")}</option>
              <option value="inactive">{t("parties.status.inactive")}</option>
            </select>
          </div>
          <button type="button" onClick={resetFilters} className="self-end rounded-lg border border-slate-300 bg-white px-5 py-3 font-bold text-slate-900 hover:bg-slate-50">
            {t("common.actions.reset")}
          </button>
        </div>
      </section>

      <PartiesTable
        parties={visibleParties}
        addas={addas}
        isLoading={isLoading}
        pendingPartyId={pendingPartyId}
        showAdda={profile?.role === USER_ROLES.superAdmin}
        onEdit={openEditModal}
        onToggleStatus={(party) => void handleToggleStatus(party)}
        onDelete={(party) => void handleDelete(party)}
      />

      <nav aria-label={t("parties.paginationLabel")} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 bg-white p-4">
        <span className="font-bold text-slate-800">
          {t("common.pagination.page")} <span dir="ltr">{currentPage}</span>{" "}
          {t("common.pagination.of")} <span dir="ltr">{totalPages}</span>
        </span>
        <div className="flex gap-2">
          <button type="button" disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600">
            {t("common.pagination.previous")}
          </button>
          <button type="button" disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600">
            {t("common.pagination.next")}
          </button>
        </div>
      </nav>

      {isModalOpen && (
        <PartyFormModal
          party={editingParty}
          addas={addas}
          fixedAddaId={profile?.addaId ?? null}
          isSaving={isSaving}
          onClose={closeModal}
          onSubmit={handleSave}
        />
      )}
    </main>
  );
}
