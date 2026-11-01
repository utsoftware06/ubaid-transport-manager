"use client";

import { useEffect, useState } from "react";
import { missingPrintAddaName, resolvePrintBranding } from "./resolvePrintBranding";
import type { PrintLanguage } from "./types";

/** Resolves a UI print heading only for the document's explicit owning Adda. */
export function usePrintAddaName(addaId: string | null | undefined, language: PrintLanguage): string {
  const [resolved, setResolved] = useState<{ addaId: string; name: string } | null>(null);

  useEffect(() => {
    let active = true;
    if (!addaId) return () => { active = false; };

    void resolvePrintBranding(addaId).then(({ branding }) => {
      if (active && branding.addaId === addaId) {
        setResolved({ addaId, name: branding.addaName.trim() });
      }
    }).catch(() => {
      if (active) setResolved({ addaId, name: "" });
    });

    return () => { active = false; };
  }, [addaId]);

  return addaId && resolved?.addaId === addaId && resolved.name
    ? resolved.name
    : missingPrintAddaName(language);
}
