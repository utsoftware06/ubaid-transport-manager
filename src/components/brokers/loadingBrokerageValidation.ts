export function isValidLoadingBrokeragePayment(value: string, outstanding: number) {
  const normalized = value.trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return false;
  const amount = Number(normalized);
  if (!Number.isFinite(amount) || amount <= 0 || !Number.isFinite(outstanding)) return false;
  if (amount > 999_999_999_999.99) return false;
  const requestedCents = Math.round(amount * 100);
  const outstandingCents = Math.round(outstanding * 100);
  return requestedCents > 0 && requestedCents <= outstandingCents;
}
