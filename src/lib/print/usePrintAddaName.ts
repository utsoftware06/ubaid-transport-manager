"use client";

import { useEffect, useState } from "react";
import { missingPrintAddaName, resolvePrintBranding } from "./resolvePrintBranding";
import type { PrintBranding, PrintLanguage } from "./types";

/** Resolves the Adda brand only for the document/report's explicit owner. */
export function usePrintBranding(addaId: string | null | undefined): PrintBranding | null {
  const [resolved, setResolved] = useState<{ addaId: string; branding: PrintBranding } | null>(null);

  useEffect(() => {
    let active = true;
    if (!addaId) return () => { active = false; };

    void resolvePrintBranding(addaId).then(({ branding }) => {
      if (active && branding.addaId === addaId) {
        setResolved({ addaId, branding });
      }
    }).catch(() => {
      if (active) setResolved(null);
    });

    return () => { active = false; };
  }, [addaId]);

  return addaId && resolved?.addaId === addaId
    ? resolved.branding
    : null;
}

/** Resolves a UI print heading only for the document's explicit owning Adda. */
export function usePrintAddaName(addaId: string | null | undefined, language: PrintLanguage): string {
  const branding = usePrintBranding(addaId);
  return branding?.addaName.trim()
    ? branding.addaName.trim()
    : missingPrintAddaName(language);
}
