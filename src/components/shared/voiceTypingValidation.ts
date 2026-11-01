export type VoiceFieldMode =
  | "text"
  | "identifier"
  | "phone"
  | "cnic"
  | "amount"
  | "number"
  | "date"
  | "email"
  | "url";

export function normalizeLocalizedDigits(value: string) {
  return value
    .replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (digit) => {
      const code = digit.charCodeAt(0);
      return String(code >= 0x06f0 ? code - 0x06f0 : code - 0x0660);
    })
    .replace(/\u066B/g, ".")
    .replace(/\u066C/g, ",");
}

export function appendRecognizedText(current: string, transcript: string) {
  const nextText = transcript.trim();
  if (!nextText) return current;
  const separator = current && !/\s$/.test(current) ? " " : "";
  return `${current}${separator}${nextText}`;
}

export function validateVoiceCandidate(
  mode: Exclude<VoiceFieldMode, "text">,
  rawValue: string,
  inputType?: string,
) {
  const candidate = normalizeLocalizedDigits(rawValue).trim();
  if (!candidate) return { value: null, message: "empty" };

  if (mode === "identifier") {
    return /^[\p{L}\p{N}][\p{L}\p{N}\s().\/_-]*$/u.test(candidate)
      ? { value: candidate, message: "" }
      : { value: null, message: "identifier" };
  }

  if (mode === "phone" || mode === "cnic") {
    return /^[+]?\d(?:[\d\s().\/-]*\d)?$/.test(candidate)
      ? { value: candidate, message: "" }
      : { value: null, message: "identifier" };
  }

  if (mode === "amount" || mode === "number") {
    const numericPattern = /^[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$/;
    if (!numericPattern.test(candidate)) return { value: null, message: "number" };
    const normalized = candidate.replace(/,/g, "");
    return Number.isFinite(Number(normalized))
      ? { value: normalized, message: "" }
      : { value: null, message: "number" };
  }

  if (mode === "date") {
    if (inputType === "month") {
      return /^\d{4}-(0[1-9]|1[0-2])$/.test(candidate)
        ? { value: candidate, message: "" }
        : { value: null, message: "date" };
    }
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(candidate);
    if (!match) return { value: null, message: "date" };
    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const check = new Date(Date.UTC(year, month - 1, day));
    return check.getUTCFullYear() === year && check.getUTCMonth() === month - 1 && check.getUTCDate() === day
      ? { value: candidate, message: "" }
      : { value: null, message: "date" };
  }

  if (mode === "email") {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate)
      ? { value: candidate, message: "" }
      : { value: null, message: "email" };
  }

  if (mode === "url") {
    try {
      const parsed = new URL(candidate);
      return parsed.protocol === "http:" || parsed.protocol === "https:"
        ? { value: candidate, message: "" }
        : { value: null, message: "url" };
    } catch {
      return { value: null, message: "url" };
    }
  }

  return { value: null, message: "unsupported" };
}
