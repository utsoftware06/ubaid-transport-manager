"use client";

import { Pencil, Power, Trash2 } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";
import type { PartyAddaOption, PartyRecord } from "@/types/parties";

type PartiesTableProps = {
  parties: PartyRecord[];
  addas: PartyAddaOption[];
  isLoading: boolean;
  pendingPartyId: string | null;
  showAdda: boolean;
  onEdit: (party: PartyRecord) => void;
  onToggleStatus: (party: PartyRecord) => void;
  onDelete: (party: PartyRecord) => void;
};

export default function PartiesTable({
  parties,
  addas,
  isLoading,
  pendingPartyId,
  showAdda,
  onEdit,
  onToggleStatus,
  onDelete,
}: PartiesTableProps) {
  const { t } = useLanguage();
  const addaNames = new Map(addas.map((adda) => [adda.id, adda.name]));
  const columnCount = showAdda ? 7 : 6;

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
      <table className="w-full min-w-[900px]">
        <thead className="bg-blue-600 text-white">
          <tr>
            <th className="p-4 text-start">{t("parties.fields.name")}</th>
            <th className="p-4 text-start">{t("parties.fields.phone")}</th>
            <th className="p-4 text-start">{t("parties.fields.city")}</th>
            <th className="p-4 text-start">{t("parties.fields.address")}</th>
            {showAdda && <th className="p-4 text-start">{t("parties.fields.adda")}</th>}
            <th className="p-4 text-start">{t("parties.fields.status")}</th>
            <th className="p-4 text-start">{t("common.actions.title")}</th>
          </tr>
        </thead>
        <tbody>
          {isLoading && (
            <tr>
              <td colSpan={columnCount} className="p-10 text-center font-semibold text-slate-700">
                {t("parties.states.loading")}
              </td>
            </tr>
          )}
          {!isLoading && parties.length === 0 && (
            <tr>
              <td colSpan={columnCount} className="p-10 text-center font-semibold text-slate-700">
                {t("parties.states.empty")}
              </td>
            </tr>
          )}
          {!isLoading &&
            parties.map((party) => {
              const isPending = pendingPartyId === party.id;
              return (
                <tr key={party.id} className="border-b border-slate-200 last:border-0 hover:bg-slate-50">
                  <td className="p-4 font-bold text-slate-900">{party.name}</td>
                  <td dir="ltr" className="p-4 text-start font-medium text-slate-800">
                    {party.phone || "-"}
                  </td>
                  <td className="p-4 font-medium text-slate-800">{party.city || "-"}</td>
                  <td className="max-w-xs p-4 font-medium text-slate-800">
                    <span className="line-clamp-2">{party.address || "-"}</span>
                  </td>
                  {showAdda && (
                    <td className="p-4 font-medium text-slate-800">
                      {addaNames.get(party.adda_id) ?? t("parties.states.unknownAdda")}
                    </td>
                  )}
                  <td className="p-4">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-sm font-bold ${
                        party.is_active
                          ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                          : "border-slate-300 bg-slate-100 text-slate-700"
                      }`}
                    >
                      {t(party.is_active ? "parties.status.active" : "parties.status.inactive")}
                    </span>
                  </td>
                  <td className="p-4">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={pendingPartyId !== null}
                        onClick={() => onEdit(party)}
                        aria-label={`${t("common.actions.edit")} ${party.name}`}
                        className="rounded-lg border border-blue-200 bg-blue-50 p-2 text-blue-700 hover:bg-blue-100 focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-wait"
                        title={t("common.actions.edit")}
                      >
                        <Pencil className="h-4 w-4" aria-hidden="true" />
                      </button>
                      <button
                        type="button"
                        disabled={pendingPartyId !== null}
                        onClick={() => onToggleStatus(party)}
                        aria-label={`${t(
                          party.is_active
                            ? "parties.actions.deactivate"
                            : "parties.actions.activate"
                        )} ${party.name}`}
                        className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-amber-800 hover:bg-amber-100 focus-visible:ring-2 focus-visible:ring-amber-500 disabled:cursor-wait"
                        title={t(
                          party.is_active
                            ? "parties.actions.deactivate"
                            : "parties.actions.activate"
                        )}
                      >
                        <Power className="h-4 w-4" aria-hidden="true" />
                      </button>
                      <button
                        type="button"
                        disabled={pendingPartyId !== null}
                        onClick={() => onDelete(party)}
                        aria-label={`${t("common.actions.delete")} ${party.name}`}
                        className="rounded-lg border border-red-200 bg-red-50 p-2 text-red-700 hover:bg-red-100 focus-visible:ring-2 focus-visible:ring-red-500 disabled:cursor-wait"
                        title={t("common.actions.delete")}
                      >
                        {isPending ? (
                          <span className="block h-4 w-4 animate-spin rounded-full border-2 border-red-700 border-t-transparent" />
                        ) : (
                          <Trash2 className="h-4 w-4" aria-hidden="true" />
                        )}
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
        </tbody>
      </table>
    </div>
  );
}
