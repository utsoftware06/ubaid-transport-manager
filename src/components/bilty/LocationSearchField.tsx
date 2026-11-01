"use client";

import { useEffect, useId, useRef, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import type { LocationOption } from "./types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  label: string;
  placeholder: string;
  noResults: string;
  searchFailed: string;
  clearLabel: string;
  value: string;
  selectedId: string;
  required?: boolean;
  onChange: (search: string, selectedId: string) => void;
};

type SearchState = "idle" | "loading" | "success" | "error";

function isLocationOption(value: unknown): value is LocationOption {
  if (!value || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  return typeof row.id === "string"
    && (row.parent_id === null || typeof row.parent_id === "string")
    && typeof row.location_type === "string"
    && typeof row.name === "string"
    && typeof row.hierarchy_label === "string";
}

export default function LocationSearchField({ label, placeholder, noResults, searchFailed, clearLabel, value, selectedId, required, onChange }: Props) {
  const id = useId();
  const listId = `${id}-results`;
  const [results, setResults] = useState<LocationOption[]>([]);
  const [open, setOpen] = useState(false);
  const [searchState, setSearchState] = useState<SearchState>("idle");
  const latestRequestRef = useRef(0);

  useEffect(() => {
    const query = value.trim();
    if (selectedId || query.length < 2) {
      latestRequestRef.current += 1;
      return;
    }
    const requestId = latestRequestRef.current + 1;
    latestRequestRef.current = requestId;
    const timer = window.setTimeout(async () => {
      setSearchState("loading");
      const { data, error } = await supabase.rpc("search_pakistan_locations", { p_query: query, p_limit: 30 });
      if (latestRequestRef.current !== requestId) return;

      if (error) {
        if (process.env.NODE_ENV === "development") {
          console.error("Unable to search Pakistan locations:", { code: error.code, message: error.message });
        }
        setResults([]);
        setSearchState("error");
      } else {
        const rows = Array.isArray(data) ? data.filter(isLocationOption) : [];
        if (process.env.NODE_ENV === "development" && data !== null && !Array.isArray(data)) {
          console.error("Unexpected Pakistan location RPC response shape.");
        }
        setResults(rows);
        setSearchState("success");
      }
      setOpen(true);
    }, 220);
    return () => window.clearTimeout(timer);
  }, [selectedId, value]);

  return <div className="relative">
    <label htmlFor={id} className="mb-1.5 block text-xs font-extrabold uppercase tracking-wide text-slate-600">{label}</label>

    <div className="relative">
    <VoiceTypingField fieldLabel={placeholder} mode="text"><input id={id} type="text" role="combobox" aria-autocomplete="list" aria-controls={listId} aria-expanded={open && !selectedId}
      required={required} autoComplete="off" value={value}
      onChange={(event) => { setResults([]); setSearchState("idle"); onChange(event.target.value, ""); }}
      onFocus={() => setOpen(true)} placeholder={placeholder}
      className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 pe-10 font-medium text-slate-900 shadow-sm outline-none transition placeholder:text-slate-500 focus:border-blue-500 focus:ring-4 focus:ring-blue-100" /></VoiceTypingField>
    {(value || selectedId) && <button type="button" aria-label={clearLabel} title={clearLabel}
      onClick={() => { latestRequestRef.current += 1; setResults([]); setSearchState("idle"); setOpen(false); onChange("", ""); }}
      className="absolute end-2 top-1/2 -translate-y-1/2 rounded-lg px-2 py-1 text-lg font-bold text-slate-600 transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500">×</button>}
    </div>

    {open && !selectedId && value.trim().length >= 2 && <div id={listId} className="absolute z-30 mt-1 max-h-64 w-full overflow-y-auto rounded-2xl border border-slate-200 bg-white p-1.5 shadow-xl">
      {searchState === "loading" ? <p className="px-3 py-2 text-sm text-slate-600">…</p> : searchState === "error" ?
        <p className="px-3 py-2 text-sm font-medium text-red-700">{searchFailed}</p> : results.length ? results.map((location) =>
        <button key={location.id} type="button" onMouseDown={(event) => event.preventDefault()}
          onClick={() => { latestRequestRef.current += 1; onChange(location.name, location.id); setOpen(false); }}
          className="block w-full rounded-xl px-3 py-2.5 text-start text-sm font-medium text-slate-800 transition hover:bg-blue-50 focus:bg-blue-50 focus:outline-none">
          {location.hierarchy_label}
        </button>) : <p className="px-3 py-2 text-sm font-medium text-slate-600">{noResults}</p>}
    </div>}
  </div>;
}
