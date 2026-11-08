"use client";

/* eslint-disable @next/next/no-img-element -- tenant-owned logo URLs are validated for print; a fixed slot is kept when absent or unavailable. */

import { useState } from "react";
import { getSafeLogoUrl } from "@/lib/print/foundation";
import type { PrintBranding } from "@/lib/print/types";

type Props = {
  branding: PrintBranding | null;
  className?: string;
  showLogo?: boolean;
};

/** A bounded, non-cropping logo slot. Missing/failed logos remain blank. */
export default function PrintAddaLogo({ branding, className = "", showLogo }: Props) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const logoUrl = getSafeLogoUrl(branding?.logoUrl);
  const shouldShow = showLogo ?? branding?.showLogoByDefault ?? false;
  const visibleUrl = shouldShow && logoUrl && failedUrl !== logoUrl ? logoUrl : null;

  return <span
    aria-hidden="true"
    className={className}
    style={{
      display: "inline-flex",
      flex: "none",
      width: "48px",
      height: "42px",
      alignItems: "center",
      justifyContent: "center",
      verticalAlign: "middle",
    }}
  >
    {visibleUrl ? <img
      src={visibleUrl}
      alt=""
      style={{ display: "block", maxWidth: "46px", maxHeight: "40px", width: "auto", height: "auto", objectFit: "contain" }}
      onError={(event) => { event.currentTarget.style.display = "none"; setFailedUrl(visibleUrl); }}
    /> : null}
  </span>;
}
