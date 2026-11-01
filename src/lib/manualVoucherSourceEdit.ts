export type ManualVoucherSourceModule = "workshop" | "oil";

export type ManualVoucherSourceEditContext = {
  voucherId: number;
  sourceEntryId: string;
  returnTo: string;
};

export function buildManualVoucherSourceEditPath(
  module: ManualVoucherSourceModule,
  voucherId: number,
  sourceEntryId: string | number
) {
  const returnTo = `/expenses?resumeManualVoucherId=${voucherId}`;
  const query = new URLSearchParams({
    manualVoucherId: String(voucherId),
    manualSourceEntryId: String(sourceEntryId),
    returnTo,
  });

  return `/${module}?${query.toString()}`;
}

export function readManualVoucherSourceEditContext(
  module: ManualVoucherSourceModule
): ManualVoucherSourceEditContext | null {
  if (typeof window === "undefined") return null;

  const query = new URLSearchParams(window.location.search);
  const voucherId = Number(query.get("manualVoucherId"));
  const sourceEntryId = query.get("manualSourceEntryId")?.trim() ?? "";
  const returnTo = query.get("returnTo") ?? "";

  if (
    !Number.isSafeInteger(voucherId) ||
    voucherId <= 0 ||
    !sourceEntryId ||
    !new RegExp(module === "workshop" ? "^\\d+$" : "^[0-9a-f-]{36}$", "i").test(sourceEntryId) ||
    returnTo !== `/expenses?resumeManualVoucherId=${voucherId}`
  ) {
    return null;
  }

  return { voucherId, sourceEntryId, returnTo };
}

export function returnToManualVoucherAfterSourceEdit(
  context: ManualVoucherSourceEditContext
) {
  window.location.assign(context.returnTo);
}
