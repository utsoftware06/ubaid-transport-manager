"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { formatAmount, type WorkshopOption } from "./Workshop";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  workshops: WorkshopOption[];
  profileAddaId: string;
  onChanged: () => Promise<void>;
};

type FormState = {
  workshopName: string;
  ownerName: string;
  phone: string;
  address: string;
  openingBalance: string;
};

const emptyForm: FormState = {
  workshopName: "",
  ownerName: "",
  phone: "",
  address: "",
  openingBalance: "0",
};

export default function WorkshopMaster({ workshops, profileAddaId, onChanged }: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("workshop", profileAddaId, language === "ur" ? "ur" : "en");
  const [form, setForm] = useState<FormState>(emptyForm);
  const [editingId, setEditingId] = useState("");
  const [search, setSearch] = useState("");
  const [viewing, setViewing] = useState<WorkshopOption | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState("");
  const saveLock = useRef(false);
  const deleteLock = useRef(false);
  const previousFocus = useRef<HTMLElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (!viewing) return;
    previousFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setViewing(null);
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocus.current?.focus();
    };
  }, [viewing]);

  const filtered = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return workshops;
    return workshops.filter((workshop) =>
      [workshop.workshopName, workshop.ownerName, workshop.phone, workshop.address]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [search, workshops]);

  function setField(field: keyof FormState, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  function reset() {
    setForm(emptyForm);
    setEditingId("");
  }

  async function save() {
    if (saveLock.current) return;
    const openingBalance = Number(form.openingBalance || 0);
    if (!form.workshopName.trim()) {
      alert(t("workshop.master.validation.nameRequired"));
      return;
    }
    if (!Number.isFinite(openingBalance)) {
      alert(t("workshop.master.validation.balanceInvalid"));
      return;
    }
    if (!profileAddaId) {
      alert(t("workshop.master.messages.addaRequired"));
      return;
    }

    saveLock.current = true;
    setIsSaving(true);
    try {
      const payload = {
        workshop_name: form.workshopName.trim(),
        owner_name: form.ownerName.trim() || null,
        phone: form.phone.trim() || null,
        address: form.address.trim() || null,
        opening_balance: openingBalance,
      };
      const result = editingId
        ? await supabase.from("workshops").update(payload).eq("id", editingId)
        : await supabase.from("workshops").insert({ ...payload, adda_id: profileAddaId });
      if (result.error) {
        console.error("Failed to save Workshop Master:", result.error);
        alert(t("workshop.master.messages.saveFailed"));
        return;
      }
      alert(t(editingId ? "workshop.master.messages.updated" : "workshop.master.messages.saved"));
      reset();
      await onChanged();
    } finally {
      saveLock.current = false;
      setIsSaving(false);
    }
  }

  function edit(workshop: WorkshopOption) {
    setEditingId(workshop.id);
    setForm({
      workshopName: workshop.workshopName,
      ownerName: workshop.ownerName,
      phone: workshop.phone,
      address: workshop.address,
      openingBalance: String(workshop.openingBalance),
    });
  }

  async function remove(workshop: WorkshopOption) {
    if (deleteLock.current) return;
    if (!window.confirm(t("workshop.master.messages.deleteConfirm") + " " + workshop.workshopName + "?")) return;
    deleteLock.current = true;
    setDeletingId(workshop.id);
    try {
      const { error } = await supabase.from("workshops").delete().eq("id", workshop.id);
      if (error) {
        console.error("Failed to delete Workshop Master:", error);
        alert(t(error.code === "23503" ? "workshop.master.messages.linkedDelete" : "workshop.master.messages.deleteFailed"));
        return;
      }
      if (editingId === workshop.id) reset();
      alert(t("workshop.master.messages.deleted"));
      await onChanged();
    } finally {
      deleteLock.current = false;
      setDeletingId("");
    }
  }

  function printList() {
    const printWindow = window.open("", "_blank", "width=1100,height=800");
    if (!printWindow) {
      alert(t("workshop.messages.allowPopups"));
      return;
    }
    const rows = filtered.map((workshop) =>
      "<tr><td>" + escapeHtml(workshop.workshopName) + "</td><td>" +
      escapeHtml(workshop.ownerName || "-") + "</td><td dir='ltr'>" +
      escapeHtml(workshop.phone || "-") + "</td><td>" +
      escapeHtml(workshop.address || "-") + "</td><td dir='ltr'>" +
      escapeHtml(formatAmount(workshop.openingBalance)) + "</td></tr>"
    ).join("");
    const ownerIds = Array.from(new Set(filtered.map((workshop) => workshop.addaId)));
    const ownerAddaId = filtered.length > 0 && ownerIds.length === 1 ? ownerIds[0] : null;
    const html = "<!doctype html><html lang='" + escapeHtml(language) + "' dir='" +
      escapeHtml(dir) + "'><head><title>" + escapeHtml(t("workshop.master.title")) +
      "</title><style>@page{size:A4;margin:12mm}body{font-family:Arial;color:#111827}h1{border-bottom:2px solid #111827;padding-bottom:10px}table{width:100%;border-collapse:collapse}th,td{border:1px solid #cbd5e1;padding:8px;text-align:start}th{background:#2563eb;color:white}</style></head><body><h1>" +
      PRINT_ADDA_NAME_TOKEN + "</h1><h2>" + escapeHtml(t("workshop.master.title")) + "</h2><table><thead><tr><th>" +
      escapeHtml(t("workshop.master.fields.name")) + "</th><th>" +
      escapeHtml(t("workshop.master.fields.owner")) + "</th><th>" +
      escapeHtml(t("workshop.master.fields.phone")) + "</th><th>" +
      escapeHtml(t("workshop.master.fields.address")) + "</th><th>" +
      escapeHtml(t("workshop.master.fields.openingBalance")) +
      "</th></tr></thead><tbody>" + rows +
      "</tbody></table><script>window.onload=function(){window.focus();window.print();}</script></body></html>";
    void writeAddaBrandedPrintDocument(printWindow, html, ownerAddaId, language === "ur" ? "ur" : "en");
  }

  function openPrintList() {
    const ownerAddaId = singleResolvedAddaId(filtered.map((workshop) => workshop.addaId));
    const presentation: ModulePrintPresentation = {
      documentType: "workshop",
      title: printLabel("workshop.master.title"),
      subtitle: printLabel("workshop.master.description"),
      fields: [],
      tables: [{
        columns: ["workshop.master.fields.name", "workshop.master.fields.owner", "workshop.master.fields.phone", "workshop.master.fields.address", "workshop.master.fields.openingBalance"].map(printLabel),
        rows: filtered.map((workshop) => [printValue(workshop.workshopName), printValue(workshop.ownerName), printValue(workshop.phone), printValue(workshop.address), printValue(formatAmount(workshop.openingBalance))]),
      }],
    };
    modulePrint.openPresentation(presentation, printList, ownerAddaId);
  }

  return (
    <section dir={dir} className="space-y-6">
      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-2xl font-black text-gray-900">{t("workshop.master.title")}</h2>
            <p className="mt-1 font-semibold text-gray-700">{t("workshop.master.description")}</p>
          </div>
          <button type="button" onClick={openPrintList} className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white hover:bg-blue-700">
            {t("workshop.master.actions.print")}
          </button>
        </div>
        <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
          <label className="text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.master.fields.name")}</span><VoiceTypingField fieldLabel={t("workshop.master.fields.name")} value={form.workshopName} onValueChange={(value) => setField("workshopName", value)} contextKey={editingId || "new"}><input value={form.workshopName} onChange={(event) => setField("workshopName", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></VoiceTypingField></label>
          <label className="text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.master.fields.owner")}</span><VoiceTypingField fieldLabel={t("workshop.master.fields.owner")} value={form.ownerName} onValueChange={(value) => setField("ownerName", value)} contextKey={editingId || "new"}><input value={form.ownerName} onChange={(event) => setField("ownerName", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></VoiceTypingField></label>

          <VoiceTypingField fieldLabel={t("workshop.master.fields.phone")} mode="phone"><label className="text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.master.fields.phone")}</span><input dir="ltr" value={form.phone} onChange={(event) => setField("phone", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>

          <label className="text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.master.fields.address")}</span><VoiceTypingField fieldLabel={t("workshop.master.fields.address")} value={form.address} onValueChange={(value) => setField("address", value)} contextKey={editingId || "new"}><input value={form.address} onChange={(event) => setField("address", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></VoiceTypingField></label>

          <VoiceTypingField fieldLabel={t("workshop.master.fields.openingBalance")} mode="amount"><label className="text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.master.fields.openingBalance")}</span><input type="number" dir="ltr" value={form.openingBalance} onChange={(event) => setField("openingBalance", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>

        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <button type="button" onClick={() => void save()} disabled={isSaving} className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white disabled:cursor-not-allowed">{isSaving ? t("common.states.saving") : t(editingId ? "common.actions.update" : "common.actions.save")}</button>
          {editingId && <button type="button" onClick={reset} className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-bold text-gray-900">{t("common.cancelEdit")}</button>}
        </div>
      </div>


      <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
        <VoiceTypingField fieldLabel={t("workshop.master.search")} mode="text"><input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t("workshop.master.search")} className="mb-4 w-full rounded-lg border border-gray-300 bg-white px-4 py-3 font-semibold text-gray-900 placeholder:text-gray-600" /></VoiceTypingField>
        <div className="overflow-x-auto"><table className="min-w-full text-sm">
          <thead className="bg-blue-600 text-white"><tr><th className="p-3 text-start">{t("workshop.master.fields.name")}</th><th className="p-3 text-start">{t("workshop.master.fields.owner")}</th><th className="p-3 text-start">{t("workshop.master.fields.phone")}</th><th className="p-3 text-start">{t("workshop.master.fields.openingBalance")}</th><th className="p-3 text-start">{t("common.actions.title")}</th></tr></thead>
          <tbody>{filtered.map((workshop) => <tr key={workshop.id} className="border-b border-gray-200">
            <td className="p-3 font-bold">{workshop.workshopName}</td><td className="p-3">{workshop.ownerName || "-"}</td><td dir="ltr" className="p-3">{workshop.phone || "-"}</td><td dir="ltr" className="p-3">{formatAmount(workshop.openingBalance)}</td>
            <td className="p-3"><div className="flex flex-wrap gap-2"><button type="button" onClick={() => setViewing(workshop)} className="rounded bg-slate-700 px-3 py-2 font-bold text-white">{t("common.actions.view")}</button><button type="button" onClick={() => edit(workshop)} className="rounded bg-blue-600 px-3 py-2 font-bold text-white">{t("common.actions.edit")}</button><button type="button" disabled={deletingId === workshop.id} onClick={() => void remove(workshop)} className="rounded bg-red-600 px-3 py-2 font-bold text-white disabled:cursor-not-allowed">{t("common.actions.delete")}</button></div></td>
          </tr>)}</tbody>
        </table></div>
      </div>


      {viewing && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setViewing(null); }}>
        <section role="dialog" aria-modal="true" aria-labelledby="workshop-master-details-title" className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 shadow-xl sm:p-6">
          <div className="flex justify-between gap-3"><h2 id="workshop-master-details-title" className="text-xl font-black text-gray-900">{viewing.workshopName}</h2><button ref={closeButtonRef} type="button" onClick={() => setViewing(null)} aria-label={t("common.actions.close")} className="rounded border border-gray-300 px-3 py-2 font-bold">×</button></div>
          <dl className="mt-5 grid grid-cols-1 gap-4 sm:grid-cols-2"><div><dt className="font-bold text-gray-700">{t("workshop.master.fields.owner")}</dt><dd>{viewing.ownerName || "-"}</dd></div><div><dt className="font-bold text-gray-700">{t("workshop.master.fields.phone")}</dt><dd dir="ltr">{viewing.phone || "-"}</dd></div><div className="sm:col-span-2"><dt className="font-bold text-gray-700">{t("workshop.master.fields.address")}</dt><dd>{viewing.address || "-"}</dd></div><div><dt className="font-bold text-gray-700">{t("workshop.master.fields.openingBalance")}</dt><dd dir="ltr">{formatAmount(viewing.openingBalance)}</dd></div></dl>
        </section>
      </div>}
      {modulePrint.dialog}
    </section>
  );
}
