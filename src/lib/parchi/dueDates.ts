export type ParchiDueBucket = "due_today" | "upcoming" | "overdue" | "inactive" | "not_recorded" | "unverified";
export type DueSummaryBucket = "due_today" | "overdue";

export type ParchiDueRow = {
  parchi_id: string;
  direction: "received" | "issued";
  funding_status: string;
  document_amount: number | string;
  funding_due_date: string | null;
  settlement_due_date: string | null;
  net_funded: number | string;
  funded_outstanding: number | string;
};

export type ParchiDeadline = {
  date: string | null;
  amount: number | null;
  bucket: ParchiDueBucket;
  daysOverdue: number | null;
};

export type ParchiDeadlineAnalysis = {
  funding: ParchiDeadline;
  settlement: ParchiDeadline;
};

export type ParchiDueSummary = {
  count: number;
  fundingDocumentCount: number;
  settlementDocumentCount: number;
  receivedFundingDue: number;
  issuedFundingDue: number;
  receivedPayable: number;
  issuedReceivable: number;
};

const DAY_MS = 86_400_000;

/** Returns the current date in the application's business timezone, independent of device timezone. */
export function getAsiaKarachiToday(now: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Karachi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const fields = new Map(parts.map((part) => [part.type, part.value]));
  return `${fields.get("year")}-${fields.get("month")}-${fields.get("day")}`;
}

/** Date-only ordinal: UTC is used only as a calendar arithmetic frame, never as a local date conversion. */
export function dateOnlyOrdinal(value: string | null | undefined): number | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const calendarDate = new Date(0);
  calendarDate.setUTCHours(0, 0, 0, 0);
  calendarDate.setUTCFullYear(year, month - 1, day);
  if (calendarDate.getUTCFullYear() !== year
    || calendarDate.getUTCMonth() !== month - 1
    || calendarDate.getUTCDate() !== day) return null;
  return Math.floor(calendarDate.getTime() / DAY_MS);
}

function parseNonNegativeMoney(value: number | string | null | undefined): number | null {
  if (value == null || value === "") return null;
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
}

function analyzeDeadline(
  dateValue: string | null,
  amount: number | null,
  today: string,
): ParchiDeadline {
  const date = dateOnlyOrdinal(dateValue) === null ? null : dateValue;
  if (!date) return { date: null, amount, bucket: "not_recorded", daysOverdue: null };
  if (amount === null || dateOnlyOrdinal(today) === null) {
    return { date, amount, bucket: "unverified", daysOverdue: null };
  }
  if (amount <= 0) return { date, amount, bucket: "inactive", daysOverdue: null };

  const dayDifference = dateOnlyOrdinal(date)! - dateOnlyOrdinal(today)!;
  if (dayDifference === 0) return { date, amount, bucket: "due_today", daysOverdue: null };
  if (dayDifference > 0) return { date, amount, bucket: "upcoming", daysOverdue: null };
  return { date, amount, bucket: "overdue", daysOverdue: -dayDifference };
}

export function analyzeParchiDeadlines(row: ParchiDueRow, today: string): ParchiDeadlineAnalysis {
  const cancelled = row.funding_status === "Cancelled";
  const documentAmount = parseNonNegativeMoney(row.document_amount);
  const netFunded = parseNonNegativeMoney(row.net_funded);
  const fundedOutstanding = parseNonNegativeMoney(row.funded_outstanding);
  const unfundedAmount = cancelled
    ? 0
    : documentAmount === null || netFunded === null
      ? null
      : Math.max(documentAmount - netFunded, 0);
  const settlementAmount = cancelled ? 0 : fundedOutstanding;

  return {
    funding: analyzeDeadline(row.funding_due_date, unfundedAmount, today),
    settlement: analyzeDeadline(row.settlement_due_date, settlementAmount, today),
  };
}

function centsAdd(total: number, value: number | null): number {
  return total + (value === null ? 0 : Math.round(value * 100));
}

export function summarizeParchiDeadlines(
  rows: ParchiDueRow[],
  today: string,
  bucket: DueSummaryBucket,
): ParchiDueSummary {
  const documents = new Set<string>();
  let fundingDocumentCount = 0;
  let settlementDocumentCount = 0;
  let receivedFundingDue = 0;
  let issuedFundingDue = 0;
  let receivedPayable = 0;
  let issuedReceivable = 0;

  for (const row of rows) {
    const analysis = analyzeParchiDeadlines(row, today);
    let hasMatchingDeadline = false;
    if (analysis.funding.bucket === bucket) {
      hasMatchingDeadline = true;
      fundingDocumentCount += 1;
      if (row.direction === "received") receivedFundingDue = centsAdd(receivedFundingDue, analysis.funding.amount);
      else issuedFundingDue = centsAdd(issuedFundingDue, analysis.funding.amount);
    }
    if (analysis.settlement.bucket === bucket) {
      hasMatchingDeadline = true;
      settlementDocumentCount += 1;
      if (row.direction === "received") receivedPayable = centsAdd(receivedPayable, analysis.settlement.amount);
      else issuedReceivable = centsAdd(issuedReceivable, analysis.settlement.amount);
    }
    if (hasMatchingDeadline) documents.add(row.parchi_id);
  }

  return {
    count: documents.size,
    fundingDocumentCount,
    settlementDocumentCount,
    receivedFundingDue: receivedFundingDue / 100,
    issuedFundingDue: issuedFundingDue / 100,
    receivedPayable: receivedPayable / 100,
    issuedReceivable: issuedReceivable / 100,
  };
}
