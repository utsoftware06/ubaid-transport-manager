"use client";

/* eslint-disable @next/next/no-img-element -- Adda logos are tenant-supplied URLs; Next Image remote allowlists are not part of this read-only foundation. */

import { useState } from "react";
import { getPrintDirection, getPrintPageRule, getSafeLogoUrl } from "@/lib/print/foundation";
import { missingPrintAddaName } from "@/lib/print/resolvePrintBranding";
import type { PrintBranding, PrintPreviewOverrides } from "@/lib/print/types";
import { printCopy } from "./printCopy";

type PrintFoundationSampleProps = {
  branding: PrintBranding;
  overrides: PrintPreviewOverrides;
};

const SAMPLE_DATE = "01-01-2000";

export default function PrintFoundationSample({
  branding,
  overrides,
}: PrintFoundationSampleProps) {
  const [logoFailed, setLogoFailed] = useState(false);
  const copy = (key: string) => printCopy(overrides.language, key);
  const logoUrl = getSafeLogoUrl(branding.logoUrl);
  const direction = getPrintDirection(overrides.language);
  const showLogo = overrides.showLogo && logoUrl && !logoFailed;

  return (
    <>
      <style>{getPrintPageRule(overrides.paperSize, overrides.orientation, overrides)}</style>
      <article
        id="print-template-foundation-preview"
        lang={overrides.language}
        dir={direction}
        className={`print-foundation-sheet print-foundation-sheet-${overrides.paperSize.toLowerCase()}-${overrides.orientation} mx-auto bg-white text-slate-950`}
        aria-label={copy("sampleTitle")}
      >
        <div className="print-foundation-watermark" aria-hidden="true">
          {copy("sampleNo")}
        </div>
        <header className="print-foundation-header">
          {showLogo ? (
            <img
              src={logoUrl}
              alt=""
              className="print-foundation-logo"
              onError={() => setLogoFailed(true)}
            />
          ) : null}
          <div className="print-foundation-brand">
            <h1>{branding.addaName.trim() || missingPrintAddaName(overrides.language)}</h1>
            {branding.tagline ? <p>{branding.tagline}</p> : null}
            {[overrides.showAddress ? branding.address : null, overrides.showAddress ? branding.city : null,
              overrides.showPhone ? branding.phone : null, overrides.showPhone ? branding.alternatePhone : null]
              .filter((value): value is string => Boolean(value?.trim()))
              .map((value, index) => <p key={`${index}-${value}`}>{value}</p>)}
            {overrides.showLogo && branding.logoUrl && logoFailed ? (
              <span className="print-foundation-logo-fallback">{copy("logoFailed")}</span>
            ) : null}
          </div>
          <div className="print-foundation-serial">
            <span>{copy("sampleNo")}</span>
            <strong>DEMO / 0001</strong>
          </div>
        </header>

        <div className="print-foundation-title-row">
          <h2>{copy("sampleTitle")}</h2>
          <span>{copy("sampleValue")}</span>
        </div>

        <section className="print-foundation-fields">
          <FoundationField label={copy("sampleDate")} value={SAMPLE_DATE} />
          <FoundationField label={copy("sampleRoute")} value={copy("sampleRouteValue")} />
          <FoundationField label={copy("sampleVehicle")} value={copy("sampleVehicleValue")} />
          <FoundationField label={copy("sampleGoods")} value={copy("sampleGoodsValue")} />
          <FoundationField label={copy("sampleAmount")} value={copy("sampleAmountValue")} />
          <FoundationField label={copy("sampleRemarks")} value={copy("sampleRemarksValue")} wide />
        </section>

        <p className="print-foundation-notice">{copy("sampleNo")}</p>

        <footer className="print-foundation-footer">
          {overrides.showFooter && branding.footerText ? (
            <p className="print-foundation-custom-footer">{branding.footerText}</p>
          ) : null}
          {overrides.showSignatures || overrides.showStamp ? (
            <div className="print-foundation-signatures">
              {overrides.showSignatures ? <><div>{copy("prepared")}</div><div>{copy("receiver")}</div></> : null}
              {overrides.showStamp ? <div>{copy("stamp")}</div> : null}
            </div>
          ) : null}
          <p className="print-foundation-disclaimer">Foundation-only preview. No business document or financial record is being printed.</p>
        </footer>
      </article>
    </>
  );
}

function FoundationField({
  label,
  value,
  wide = false,
}: {
  label: string;
  value: string;
  wide?: boolean;
}) {
  return (
    <div className={`print-foundation-field${wide ? " print-foundation-field-wide" : ""}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
