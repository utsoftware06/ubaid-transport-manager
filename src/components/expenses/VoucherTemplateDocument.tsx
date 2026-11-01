/* eslint-disable @next/next/no-img-element -- tenant logos and the bundled truck use guarded local/HTTPS URLs. */

import { useState, type Ref } from "react";
import { EXPENSE_TYPES_BY_CLASS, expenseTypeLabelKey } from "./expenseClassification";
import { getPrintPageRule, getPrintDirection, getSafeLogoUrl } from "@/lib/print/foundation";
import { translations, type AppLanguage } from "@/i18n/translations";
import type { PrintBranding, PrintPreviewOverrides } from "@/lib/print/types";
import { missingPrintAddaName } from "@/lib/print/resolvePrintBranding";
import type { VoucherMoney, VoucherPrintPresentation } from "@/lib/print/voucherPresentation";

const labelCopy = {
  en: {
    traditionalTitle: "TRIP EXPENSE VOUCHER", modernTitle: "STANDARD TRIP EXPENSE VOUCHER", compactTitle: "TRIP EXPENSE VOUCHER", detailedTitle: "STANDARD & MANUAL TRIP EXPENSE VOUCHER",
    standard: "Standard Voucher", manual: "Manual / Without Bilty", sample: "SAMPLE ONLY · NOT A BUSINESS RECORD",
    voucherNo: "Voucher No.", voucherDate: "Voucher Date", departureDate: "Departure Date", arrivalDate: "Arrival Date", period: "Trip Period", days: "Days", status: "Status", draft: "Draft", finalized: "Finalized",
    tripDetails: "Trip Details", tripLegs: "Trip / Loading Details", groupRef: "Chakkar / Outbound Bilty", loadingNo: "Loading No.", biltyNo: "Bilty No.", tripType: "Trip Type", route: "Route",
    vehicle: "Vehicle", owner: "Owner", driver: "Driver", loadingDate: "Loading Date", departure: "Departure", arrival: "Arrival", freight: "Freight", routeDescription: "Route / Description",
    expenseItems: "Recorded Expense Items", expenseClass: "Expense Class", category: "Category", amount: "Amount", method: "Payment Method", remarks: "Remarks / Source Reference", receipt: "Receipt", linkedSource: "Linked source",
    summary: "Voucher Summary", vehicleFreight: "Vehicle Freight", vehicleAdvance: "Vehicle Advance", vehicleLaterPaid: "Later Vehicle Payments", vehicleTotalPaid: "Actual Vehicle Cash Paid", vehicleParchiWithheld: "Noncash Parchi Withholding", vehicleEntitlementSettled: "Vehicle Entitlement Settled", vehicleBalance: "Vehicle Balance",
    regularTotal: "Regular Trip Expenses", periodicTotal: "Vehicle / Periodic Expenses", tripExpenseTotal: "Total Trip Expenses", vehicleProfitLoss: "Vehicle Profit / Loss",
    totalFreight: "Total Chakkar Freight", totalExpenses: "Total Voucher Expenses", netEarnings: "Net Vehicle Earnings", linkedReferences: "Linked Source References",
    noFreight: "No freight legs were recorded.", noExpenses: "No expense items were recorded.", noLegs: "No linked trip details are available.", note: "This printout shows saved Voucher details. Linked source references are not additional expenses.",
    regularClass: "Regular Trip", periodicClass: "Vehicle / Periodic", prepared: "Prepared By", approved: "Approved By", received: "Received By", stamp: "Stamp",
    print: "Print / Save as PDF", close: "Close", reset: "Reset Preview", fallback: "Use Existing Print", loading: "Loading saved Adda branding and Voucher defaults…",
    unavailableOwner: "The Voucher's owning Adda could not be verified from its saved relationships. New-template preview is unavailable; the existing print remains available.",
    loadFailure: "Voucher branding or print defaults could not be loaded.", summaryFailure: "Required saved Voucher summary data could not be loaded.", missing: "—",
  },
  ur: {
    traditionalTitle: "ٹرپ اخراجات واؤچر", modernTitle: "معیاری ٹرپ اخراجات واؤچر", compactTitle: "ٹرپ اخراجات واؤچر", detailedTitle: "معیاری اور دستی ٹرپ اخراجات واؤچر",
    standard: "معیاری واؤچر", manual: "دستی / بلٹی کے بغیر", sample: "صرف نمونہ · حقیقی کاروباری ریکارڈ نہیں",
    voucherNo: "واؤچر نمبر", voucherDate: "واؤچر کی تاریخ", departureDate: "روانگی کی تاریخ", arrivalDate: "آمد کی تاریخ", period: "ٹرپ کا عرصہ", days: "دن", status: "حیثیت", draft: "ڈرافٹ", finalized: "حتمی",
    tripDetails: "ٹرپ کی تفصیل", tripLegs: "ٹرپ / لوڈنگ کی تفصیل", groupRef: "چکر / روانگی بلٹی", loadingNo: "لوڈنگ نمبر", biltyNo: "بلٹی نمبر", tripType: "ٹرپ کی قسم", route: "روٹ",
    vehicle: "گاڑی", owner: "مالک", driver: "ڈرائیور", loadingDate: "لوڈنگ کی تاریخ", departure: "روانگی", arrival: "آمد", freight: "فریٹ", routeDescription: "روٹ / تفصیل",
    expenseItems: "درج شدہ اخراجات", expenseClass: "اخراجات کی قسم", category: "مد", amount: "رقم", method: "ادائیگی کا طریقہ", remarks: "ریمارکس / سورس حوالہ", receipt: "رسید", linkedSource: "منسلک حوالہ",
    summary: "واؤچر کا خلاصہ", vehicleFreight: "گاڑی کا فریٹ", vehicleAdvance: "گاڑی کی پیشگی", vehicleLaterPaid: "بعد کی گاڑی ادائیگیاں", vehicleTotalPaid: "اصل نقد گاڑی ادائیگی", vehicleParchiWithheld: "پارچی کی غیر نقد کٹوتی", vehicleEntitlementSettled: "گاڑی کے حق کی سیٹلمنٹ", vehicleBalance: "گاڑی کا بقایا",
    regularTotal: "عام ٹرپ اخراجات", periodicTotal: "گاڑی / دورانیہ وار اخراجات", tripExpenseTotal: "ٹرپ کے کل اخراجات", vehicleProfitLoss: "گاڑی کا منافع / نقصان",
    totalFreight: "چکر کا کل فریٹ", totalExpenses: "واؤچر کے کل اخراجات", netEarnings: "گاڑی کی خالص آمدنی", linkedReferences: "منسلک سورس حوالہ جات",
    noFreight: "کوئی فریٹ لیگز درج نہیں۔", noExpenses: "کوئی خرچ درج نہیں۔", noLegs: "منسلک ٹرپ کی تفصیل دستیاب نہیں۔", note: "یہ پرنٹ محفوظ واؤچر کی تفصیل دکھاتا ہے۔ منسلک سورس حوالہ اضافی خرچ نہیں ہے۔",
    regularClass: "عام ٹرپ", periodicClass: "گاڑی / دورانیہ وار", prepared: "تیار کنندہ", approved: "منظور کنندہ", received: "وصول کنندہ", stamp: "مہر",
    print: "پرنٹ / پی ڈی ایف محفوظ کریں", close: "بند کریں", reset: "پیش نظارہ بحال کریں", fallback: "موجودہ پرنٹ استعمال کریں", loading: "محفوظ اڈہ برانڈنگ اور واؤچر ڈیفالٹس لوڈ ہو رہے ہیں…",
    unavailableOwner: "محفوظ حوالوں سے واؤچر کا مالک اڈہ تصدیق نہیں ہو سکا۔ نئے ٹیمپلیٹ کا پیش نظارہ دستیاب نہیں؛ موجودہ پرنٹ دستیاب ہے۔",
    loadFailure: "واؤچر برانڈنگ یا پرنٹ ڈیفالٹس لوڈ نہیں ہو سکے۔", summaryFailure: "ضروری محفوظ واؤچر خلاصہ دستیاب نہیں۔", missing: "—",
  },
} as const;

const printCss = `
  .voucher-print-root{color:#111827;font-family:Arial,"Noto Nastaliq Urdu","Noto Naskh Arabic",sans-serif}
  .voucher-print-root[lang="ur"]{font-family:"Noto Nastaliq Urdu","Noto Naskh Arabic",Arial,sans-serif;line-height:1.6}
  .voucher-template-page{position:relative;box-sizing:border-box;width:100%;max-width:297mm;margin:0 auto;background:#fff;color:#111827;padding:8mm;direction:inherit;text-align:start;font-size:10pt;line-height:1.4;overflow-wrap:anywhere}
  .voucher-template-page *{box-sizing:border-box}
  .voucher-template-page h1,.voucher-template-page h2,.voucher-template-page h3,.voucher-template-page p{margin:0}
  .voucher-template-page h1{font-size:19pt;line-height:1.2}
  .voucher-template-page h2{font-size:14pt}
  .voucher-template-page h3{font-size:10pt}
  .voucher-template-brand{display:flex;align-items:center;gap:10px;min-width:0}
  .voucher-template-logo{width:17mm;height:17mm;object-fit:contain;flex:none}
  .voucher-template-truck{width:23mm;height:13mm;object-fit:contain;flex:none}
  .voucher-template-brand-copy{min-width:0}
  .voucher-template-brand-copy p{margin-top:2px;font-size:8.5pt}
  .voucher-template-number{min-width:35mm;border:1.5px solid #111827;padding:5px 7px;text-align:center}
  .voucher-template-number span,.voucher-template-field span{display:block;font-size:8pt;font-weight:700;color:#374151}
  .voucher-template-number strong{display:block;margin-top:2px;font-size:17pt;direction:ltr;unicode-bidi:isolate}
  .voucher-template-title{margin:5mm 0 3mm;padding:3mm 0;border-block:1.5px solid #111827;text-align:center}
  .voucher-template-title p{margin-top:2px;font-weight:700;font-size:9pt;letter-spacing:.04em}
  .voucher-template-sample{margin:2mm 0;padding:1.5mm;border:1px dashed #6b7280;text-align:center;font-size:8pt;font-weight:800;letter-spacing:.04em}
  .voucher-template-section{margin-top:4mm;break-inside:auto}
  .voucher-template-section>h2{margin-bottom:2mm;padding:2mm 2.5mm;border-inline-start:3px solid #111827;background:#f3f4f6;font-size:11pt}
  .voucher-template-fields{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:2mm 3mm}
  .voucher-template-field{min-height:12mm;border:1px solid #9ca3af;padding:2mm 2.5mm;break-inside:avoid}
  .voucher-template-field strong{display:block;margin-top:1mm;font-weight:700}
  .voucher-template-field .technical{direction:ltr;unicode-bidi:isolate}
  .voucher-template-table{width:100%;border-collapse:collapse;table-layout:auto;font-size:8.6pt}
  .voucher-template-table thead{display:table-header-group}
  .voucher-template-table tfoot{display:table-footer-group}
  .voucher-template-table tr{break-inside:avoid}
  .voucher-template-table th,.voucher-template-table td{border:1px solid #4b5563;padding:1.7mm 2mm;vertical-align:top;text-align:start}
  .voucher-template-table th{background:#e5e7eb;font-weight:800}
  .voucher-template-table .money{white-space:nowrap;text-align:end;direction:ltr;unicode-bidi:isolate}
  .voucher-template-table .detail{font-size:8pt;line-height:1.45;color:#374151;white-space:pre-line}
  .voucher-template-table .detail span{display:block}
  .voucher-template-total{font-weight:800;background:#f3f4f6}
  .voucher-template-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:2.5mm}
  .voucher-template-summary>div{min-height:14mm;border:1px solid #6b7280;padding:2.5mm;break-inside:avoid}
  .voucher-template-summary span{display:block;font-size:8pt;font-weight:700;color:#374151}
  .voucher-template-summary strong{display:block;margin-top:1.5mm;font-size:12pt;text-align:end;direction:ltr;unicode-bidi:isolate}
  .voucher-template-note{margin-top:4mm;border-top:1px solid #9ca3af;padding-top:2mm;font-size:8pt}
  .voucher-template-signatures{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8mm;margin-top:17mm;break-inside:avoid}
  .voucher-template-signatures>div{min-height:16mm;border-top:1px solid #111827;padding-top:2mm;text-align:center;font-size:8.5pt}
  .voucher-template-stamp{min-height:21mm;border:1px dashed #6b7280;padding:2mm;text-align:center}
  .voucher-template-missing{padding:12mm;text-align:center;font-weight:700}
  .voucher-template-traditional{padding:6mm;border:1.5px solid #111827}
  .voucher-template-traditional .voucher-template-header{display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;gap:3mm;padding-bottom:3mm;border-bottom:2px solid #111827}
  .voucher-template-traditional .voucher-template-title{margin:2.5mm 0;border:0;padding:2mm}
  .voucher-template-modern{padding:8mm;border:1px solid #9ca3af}
  .voucher-template-modern .voucher-template-header{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:5mm;border-bottom:2px solid #1d4ed8;padding-bottom:4mm}
  .voucher-template-modern .voucher-template-title{border:0;background:#eff6ff;color:#1e3a8a;margin:4mm 0;text-align:start;padding:3mm}
  .voucher-template-modern .voucher-template-section>h2{border-inline-start-color:#1d4ed8;background:#eff6ff;color:#1e3a8a}
  .voucher-template-compact{max-width:180mm;padding:4mm;border:1px solid #111827;font-size:8.5pt}
  .voucher-template-compact .voucher-template-header{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:2mm;align-items:center;padding-bottom:2mm;border-bottom:1.5px solid #111827}
  .voucher-template-compact .voucher-template-logo{width:12mm;height:12mm}
  .voucher-template-compact .voucher-template-truck{width:16mm;height:9mm}
  .voucher-template-compact .voucher-template-number{min-width:27mm;padding:2mm}
  .voucher-template-compact .voucher-template-number strong{font-size:12pt}
  .voucher-template-compact .voucher-template-title{margin:2mm 0;padding:1.5mm;border:0}
  .voucher-template-compact .voucher-template-title h1{font-size:14pt}
  .voucher-template-compact .voucher-template-section{margin-top:2.5mm}
  .voucher-template-compact .voucher-template-fields{gap:1mm}
  .voucher-template-compact .voucher-template-field{min-height:9mm;padding:1mm 1.5mm}
  .voucher-template-compact .voucher-template-table{font-size:7.7pt}
  .voucher-template-compact .voucher-template-table th,.voucher-template-compact .voucher-template-table td{padding:1mm 1.2mm}
  .voucher-template-compact .voucher-template-summary{gap:1mm}
  .voucher-template-compact .voucher-template-summary>div{min-height:10mm;padding:1.2mm}
  .voucher-template-compact .voucher-template-summary strong{font-size:9.5pt}
  .voucher-template-compact .voucher-template-signatures{gap:4mm;margin-top:10mm}
  .voucher-template-detailed{padding:9mm;border:1px solid #6b7280}
  .voucher-template-detailed .voucher-template-header{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:5mm;padding-bottom:4mm;border-bottom:2px solid #1d4ed8}
  .voucher-template-detailed .voucher-template-section>h2{border-inline-start-color:#1d4ed8;background:#eff6ff}
  .voucher-template-detailed .voucher-template-fields{grid-template-columns:repeat(4,minmax(0,1fr))}
  .voucher-template-detailed .voucher-template-table{font-size:9pt}
  .voucher-template-detailed .voucher-template-table th,.voucher-template-detailed .voucher-template-table td{padding:2.2mm}
  .voucher-template-rtl .voucher-template-title,.voucher-template-rtl .voucher-template-section>h2{text-align:start}
  @media print{
    body *{visibility:hidden}
    #voucher-template-print,#voucher-template-print *{visibility:visible!important}
    #voucher-template-print{position:absolute!important;inset:0 auto auto 0!important;width:100%!important;max-width:none!important;margin:0!important;padding:0!important;border:0!important;overflow:visible!important}
    .voucher-template-page{width:auto;max-width:none;margin:0;padding:0;border-radius:0;box-shadow:none}
    .voucher-template-section{break-inside:auto}
    .voucher-template-table{break-inside:auto}
    .voucher-template-page,.voucher-template-page *{print-color-adjust:exact;-webkit-print-color-adjust:exact}
    .voucher-template-table thead{display:table-header-group}
    .voucher-template-table tr{break-inside:avoid;page-break-inside:avoid}
    .voucher-template-signatures{break-inside:avoid}
  }
`;

function translation(language: AppLanguage, key: string): string {
  let value: unknown = translations[language];
  for (const segment of key.split(".").filter(Boolean)) {
    if (typeof value !== "object" || value === null || !(segment in value)) return key;
    value = (value as Record<string, unknown>)[segment];
  }
  return typeof value === "string" ? value : key;
}

function money(value: VoucherMoney, language: AppLanguage): string {
  const amount = Number(value ?? 0);
  const rendered = new Intl.NumberFormat(language === "ur" ? "en-PK" : "en-PK", { maximumFractionDigits: 2 })
    .format(Number.isFinite(amount) ? amount : 0);
  return `${language === "ur" ? "روپے" : "Rs."} ${rendered}`;
}

function tripTypeLabel(value: string | null, language: AppLanguage): string {
  if (value === "outbound" || value === "local" || value === "return") {
    return translation(language, `expenses.manual.freightTypes.${value}`);
  }
  return value ?? labelCopy[language].missing;
}

function expenseCategoryLabel(value: string, language: AppLanguage): string {
  const supportedCategories = [...EXPENSE_TYPES_BY_CLASS.regular_trip, ...EXPENSE_TYPES_BY_CLASS.vehicle_periodic];
  if (!supportedCategories.includes(value)) return value;
  const key = expenseTypeLabelKey(value);
  const translated = translation(language, key);
  return translated === key ? value : translated;
}

function paymentMethodLabel(value: string | null, language: AppLanguage): string {
  if (!value) return labelCopy[language].missing;
  const key = value.toLowerCase().replace(/[^a-z]/g, "");
  const methodKeys: Record<string, string> = {
    cash: "cash", bank: "banktransfer", banktransfer: "banktransfer", jazzcash: "jazzcash", easypaisa: "easypaisa", cheque: "cheque",
  };
  const translationKey = methodKeys[key];
  return translationKey ? translation(language, `expenses.paymentMethods.${translationKey}`) : value;
}

export function VoucherTemplateDocument({
  presentation, branding, overrides, logoFailed, onLogoError, printRef,
}: {
  presentation: VoucherPrintPresentation;
  branding: PrintBranding;
  overrides: PrintPreviewOverrides;
  logoFailed: boolean;
  onLogoError: () => void;
  printRef?: Ref<HTMLDivElement>;
}) {
  const [truckFailed, setTruckFailed] = useState(false);
  const language = overrides.language as AppLanguage;
  const copy = labelCopy[language];
  const direction = getPrintDirection(language);
  const safeLogo = overrides.showLogo ? getSafeLogoUrl(branding.logoUrl) : null;
  const showLogo = Boolean(safeLogo && !logoFailed);
  const templateClass = `voucher-template-${overrides.templateId}`;
  const pageClass = `voucher-template-page ${templateClass} ${direction === "rtl" ? "voucher-template-rtl" : ""}`;
  const header = (
    <>
      <div className="voucher-template-brand">
        {showLogo ? <img src={safeLogo ?? undefined} alt="" className="voucher-template-logo" onError={onLogoError} /> : null}
        <div className="voucher-template-brand-copy">
          <h1>{branding.addaName.trim() || missingPrintAddaName(language)}</h1>
          {branding.tagline ? <p>{branding.tagline}</p> : null}
          {overrides.showAddress && [branding.address, branding.city].filter((value) => value?.trim()).map((value, index) => <p key={`address-${index}`}>{value}</p>)}
          {overrides.showPhone && [branding.phone, branding.alternatePhone].filter((value) => value?.trim()).map((value, index) => <p key={`phone-${index}`}>{value}</p>)}
        </div>
      </div>
      {!truckFailed ? <img src="/images/print/transport-truck.svg" alt="" className="voucher-template-truck" onError={() => setTruckFailed(true)} /> : null}
      <div className="voucher-template-number"><span>{copy.voucherNo}</span><strong>{presentation.voucherNo}</strong></div>
    </>
  );
  const commonFields = [
    [copy.voucherDate, presentation.voucherDate],
    ...(presentation.kind === "standard" ? [
      [copy.period, [presentation.startDate, presentation.endDate].filter(Boolean).join(" — ") || null],
      ...(presentation.totalDays === null ? [] : [[copy.days, String(presentation.totalDays)]]),
      ...(presentation.movementGroupNo ? [[copy.groupRef, presentation.movementGroupNo]] : []),
      ...(presentation.loadingNumbers.length ? [[copy.loadingNo, presentation.loadingNumbers.join(", ")]] : []),
    ] as Array<[string, string | null]> : [
      [copy.vehicle, presentation.vehicleNo], [copy.owner, presentation.vehicleOwner], [copy.driver, presentation.driverName],
      [copy.departureDate, presentation.departureDate], [copy.arrivalDate, presentation.arrivalDate],
      ...(presentation.chakkarDays === null ? [] : [[copy.days, String(presentation.chakkarDays)]]),
      ...(presentation.status ? [[copy.status, presentation.status === "finalized" ? copy.finalized : copy.draft]] : []),
    ] as Array<[string, string | null]>),
  ] as Array<[string, string | null]>;
  const legs = presentation.legs;
  const renderTripTable = (detail = false) => <table className="voucher-template-table">
    <thead><tr>
      {detail ? <th>{copy.loadingNo}</th> : null}<th>{copy.biltyNo}</th><th>{copy.tripType}</th><th>{copy.route}</th><th>{copy.vehicle}</th><th>{copy.owner}</th><th>{copy.driver}</th>
      {detail ? <><th>{copy.loadingDate}</th><th>{copy.departure}</th><th>{copy.arrival}</th></> : null}
    </tr></thead>
    <tbody>{legs.map((leg, index) => <tr key={`${leg.loadingNo ?? "leg"}-${index}`}>
      {detail ? <td dir="auto">{leg.loadingNo ?? copy.missing}</td> : null}<td dir="auto">{leg.biltyNo ?? copy.missing}</td><td>{tripTypeLabel(leg.tripType, language)}</td><td dir="auto">{leg.route ?? copy.missing}</td>
      <td dir="auto">{leg.vehicleNo ?? copy.missing}</td><td dir="auto">{leg.vehicleOwner ?? copy.missing}</td><td dir="auto">{leg.driverName ?? copy.missing}</td>
      {detail ? <><td dir="auto">{leg.loadingDate ?? copy.missing}</td><td dir="auto">{leg.departureDate ?? copy.missing}</td><td dir="auto">{leg.arrivalDate ?? copy.missing}</td></> : null}
    </tr>)}</tbody>
  </table>;
  const expenseRows = (expenseClass: "regular_trip" | "vehicle_periodic") => presentation.expenseItems
    .filter((item) => item.expenseClass === expenseClass)
    .map((item, index) => <tr key={`${item.id}-${index}`}>
      <td>{expenseCategoryLabel(item.expenseType, language)}</td>
      {overrides.templateId === "detailed_a4" ? <td>{expenseClass === "regular_trip" ? copy.regularClass : copy.periodicClass}</td> : null}
      <td className="money">{money(item.amount, language)}</td><td dir="auto">{paymentMethodLabel(item.paymentMethod, language)}</td>
      <td className="detail" dir="auto">{item.remarks ? <span>{item.remarks}</span> : null}{item.receiptName ? <span>{copy.receipt}: {item.receiptName}</span> : null}{item.sourceDetails.map((detail, detailIndex) => <span key={`${item.id}-source-${detailIndex}`}><strong>{copy.linkedSource}: </strong>{detail}</span>)}</td>
    </tr>);
  const renderExpenses = (expenseClass: "regular_trip" | "vehicle_periodic") => {
    const items = presentation.expenseItems.filter((item) => item.expenseClass === expenseClass);
    if (!items.length) return null;
    return <section className="voucher-template-section" key={expenseClass}>
      <h2>{expenseClass === "regular_trip" ? copy.regularClass : copy.periodicClass}</h2>
      <table className="voucher-template-table"><thead><tr><th>{copy.category}</th>{overrides.templateId === "detailed_a4" ? <th>{copy.expenseClass}</th> : null}<th>{copy.amount}</th><th>{copy.method}</th><th>{copy.remarks}</th></tr></thead><tbody>{expenseRows(expenseClass)}</tbody></table>
    </section>;
  };
  const summaryRows: Array<[string, VoucherMoney]> = presentation.kind === "manual" ? [
    [copy.totalFreight, presentation.summary.manualTotalFreight],
    [copy.totalExpenses, presentation.summary.manualTotalExpenses],
    [copy.netEarnings, presentation.summary.manualNetVehicleEarnings],
  ] : [
    [copy.vehicleFreight, presentation.summary.vehicleFreight],
    [copy.vehicleAdvance, presentation.summary.vehicleAdvance],
    [copy.vehicleLaterPaid, presentation.summary.vehicleLaterPaid],
    [copy.vehicleTotalPaid, presentation.summary.vehicleTotalPaid],
    [copy.vehicleParchiWithheld, presentation.summary.vehicleParchiWithheld],
    [copy.vehicleEntitlementSettled, presentation.summary.vehicleEntitlementSettled],
    [copy.vehicleBalance, presentation.summary.vehicleBalance],
    [copy.regularTotal, presentation.summary.regularExpenseTotal],
    [copy.periodicTotal, presentation.summary.periodicExpenseTotal],
    [copy.tripExpenseTotal, presentation.summary.totalTripExpenses],
    [copy.vehicleProfitLoss, presentation.summary.vehicleProfitLoss],
  ];
  const hasSummary = summaryRows.some(([, value]) => value !== null && value !== undefined);
  const freightRows = presentation.freightItems.map((row, index) => <tr key={`${row.id}-${index}`}>
    <td>{tripTypeLabel(row.tripType, language)}</td><td className="money">{money(row.amount, language)}</td><td dir="auto">{row.description ?? copy.missing}</td>
  </tr>);
  const headerTitle = overrides.templateId === "modern_professional" ? copy.modernTitle
    : overrides.templateId === "compact_pad" ? copy.compactTitle
      : overrides.templateId === "detailed_a4" ? copy.detailedTitle : copy.traditionalTitle;

  return <div ref={printRef} id="voucher-template-print" className="voucher-print-root" lang={language} dir={direction}>
    <style dangerouslySetInnerHTML={{ __html: `${getPrintPageRule(overrides.paperSize, overrides.orientation, overrides)}${printCss}` }} />
    <article className={pageClass}>
      {presentation.isSyntheticSample ? <div className="voucher-template-sample">{copy.sample}</div> : null}
      <header className="voucher-template-header">{header}</header>
      <div className="voucher-template-title"><h1>{headerTitle}</h1><p>{presentation.kind === "manual" ? copy.manual : copy.standard}</p></div>
      <section className="voucher-template-section"><h2>{copy.tripDetails}</h2><div className="voucher-template-fields">
        {commonFields.map(([label, value], index) => value ? <div className="voucher-template-field" key={`${label}-${index}`}><span>{label}</span><strong dir="auto">{value}</strong></div> : null)}
        {presentation.kind === "manual" ? null : legs.length ? <div className="voucher-template-field"><span>{copy.tripLegs}</span><strong>{legs.length}</strong></div> : null}
        {presentation.remarks ? <div className="voucher-template-field"><span>{copy.remarks}</span><strong dir="auto">{presentation.remarks}</strong></div> : null}
      </div></section>

      {presentation.kind === "standard" ? <section className="voucher-template-section">
        <h2>{copy.tripLegs}</h2>{legs.length ? renderTripTable(overrides.templateId === "detailed_a4") : <p>{copy.noLegs}</p>}
      </section> : <section className="voucher-template-section">
        <h2>{copy.freight}</h2>
        <table className="voucher-template-table"><thead><tr><th>{copy.tripType}</th><th>{copy.amount}</th><th>{copy.routeDescription}</th></tr></thead><tbody>{freightRows.length ? freightRows : <tr><td colSpan={3}>{copy.noFreight}</td></tr>}</tbody></table>
      </section>}

      <section className="voucher-template-section"><h2>{copy.expenseItems}</h2>
        {presentation.expenseItems.length ? <>{renderExpenses("regular_trip")}{renderExpenses("vehicle_periodic")}</> : <p>{copy.noExpenses}</p>}
        {presentation.unassignedSourceReferences.length ? <><h3>{copy.linkedReferences}</h3><div className="voucher-template-fields" style={{ marginTop: "2mm" }}>{presentation.unassignedSourceReferences.map((ref, index) => <div key={`${ref.category}-${index}`} className="voucher-template-field"><span>{expenseCategoryLabel(ref.category, language)}</span><strong dir="auto">{ref.detail}</strong></div>)}</div></> : null}
      </section>

      {hasSummary ? <section className="voucher-template-section"><h2>{copy.summary}</h2><div className="voucher-template-summary">
        {summaryRows.map(([label, value], index) => value === null || value === undefined ? null : <div key={`${label}-${index}`}><span>{label}</span><strong>{money(value, language)}</strong></div>)}
      </div></section> : null}
      <p className="voucher-template-note">{copy.note}</p>
      {overrides.showSignatures || overrides.showStamp ? <section className="voucher-template-signatures">
        {overrides.showSignatures ? <><div>{copy.prepared}</div><div>{copy.approved}</div><div>{copy.received}</div></> : null}
        {overrides.showStamp ? <div className="voucher-template-stamp">{copy.stamp}</div> : null}
      </section> : null}
      {overrides.showFooter && branding.footerText ? <footer className="voucher-template-note">{branding.footerText}</footer> : null}
    </article>
  </div>;
}

export function voucherTemplateLanguageCopy(language: AppLanguage) {
  return labelCopy[language];
}

export function voucherTranslation(language: AppLanguage, key: string) {
  return translation(language, key);
}
