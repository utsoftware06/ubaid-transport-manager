export type ManualVoucherDateState = "empty" | "incomplete" | "invalid" | "reversed" | "valid";

const DAY_MS = 86_400_000;
const DATE_ONLY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

function dateOnlyUtcMillis(value: string): number | null {
  const match = DATE_ONLY_PATTERN.exec(value);
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;

  const candidate = new Date(0);
  candidate.setUTCHours(0, 0, 0, 0);
  candidate.setUTCFullYear(year, month - 1, day);
  if (
    candidate.getUTCFullYear() !== year ||
    candidate.getUTCMonth() !== month - 1 ||
    candidate.getUTCDate() !== day
  ) return null;

  const milliseconds = candidate.getTime();
  return Number.isFinite(milliseconds) ? milliseconds : null;
}

export function getManualVoucherDateState(
  departureDate: string | null | undefined,
  arrivalDate: string | null | undefined,
): ManualVoucherDateState {
  const departure = departureDate?.trim() ?? "";
  const arrival = arrivalDate?.trim() ?? "";
  if (!departure && !arrival) return "empty";
  if (!departure || !arrival) return "incomplete";

  const departureMillis = dateOnlyUtcMillis(departure);
  const arrivalMillis = dateOnlyUtcMillis(arrival);
  if (departureMillis === null || arrivalMillis === null) return "invalid";
  if (arrivalMillis < departureMillis) return "reversed";
  return "valid";
}

/** Inclusive calendar-day count using date-only UTC values (no local TZ/DST shifts). */
export function getInclusiveManualChakkarDays(
  departureDate: string | null | undefined,
  arrivalDate: string | null | undefined,
): number | null {
  if (getManualVoucherDateState(departureDate, arrivalDate) !== "valid") return null;

  const departureMillis = dateOnlyUtcMillis(departureDate!.trim());
  const arrivalMillis = dateOnlyUtcMillis(arrivalDate!.trim());
  if (departureMillis === null || arrivalMillis === null) return null;

  const days = (arrivalMillis - departureMillis) / DAY_MS + 1;
  return Number.isSafeInteger(days) && days > 0 ? days : null;
}
