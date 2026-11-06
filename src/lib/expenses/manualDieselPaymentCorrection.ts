export type ManualDieselCorrectionAction = "void" | "replace";

export type ManualDieselCorrectionInput = {
  paymentId: number;
  addaId: string;
  requestId: string;
  action: ManualDieselCorrectionAction;
  reason: string;
  replacementDate?: string;
  replacementAmount?: string;
  replacementMethod?: string;
  replacementReference?: string;
  replacementRemarks?: string;
};

export type ManualDieselCorrectionRpcPayload = {
  p_payment_id: number;
  p_adda_id: string;
  p_request_id: string;
  p_action: ManualDieselCorrectionAction;
  p_reason: string;
  p_replacement_date: string | null;
  p_replacement_amount: number | null;
  p_replacement_method: string | null;
  p_replacement_reference: string | null;
  p_replacement_remarks: string | null;
};

export type AuthoritativeDieselPaymentState = {
  totalAmount: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: string;
};

export function buildManualDieselCorrectionRpcPayload(
  input: ManualDieselCorrectionInput
): ManualDieselCorrectionRpcPayload {
  const reason = input.reason.trim();
  if (!Number.isSafeInteger(input.paymentId) || input.paymentId <= 0) {
    throw new Error("payment_id_invalid");
  }
  if (!input.addaId.trim() || !input.requestId.trim()) {
    throw new Error("context_required");
  }
  if (!reason) throw new Error("reason_required");

  if (input.action === "void") {
    return {
      p_payment_id: input.paymentId,
      p_adda_id: input.addaId,
      p_request_id: input.requestId,
      p_action: "void",
      p_reason: reason,
      p_replacement_date: null,
      p_replacement_amount: null,
      p_replacement_method: null,
      p_replacement_reference: null,
      p_replacement_remarks: null,
    };
  }

  const rawAmount = input.replacementAmount?.trim() ?? "";
  const amount = Number(rawAmount);
  if (!input.replacementDate || !rawAmount || !Number.isFinite(amount) || amount <= 0) {
    throw new Error("replacement_details_required");
  }
  if (!/^\d+(?:\.\d{1,2})?$/.test(rawAmount)) {
    throw new Error("replacement_amount_invalid");
  }
  if (!input.replacementMethod?.trim()) {
    throw new Error("replacement_details_required");
  }

  return {
    p_payment_id: input.paymentId,
    p_adda_id: input.addaId,
    p_request_id: input.requestId,
    p_action: "replace",
    p_reason: reason,
    p_replacement_date: input.replacementDate,
    p_replacement_amount: amount,
    p_replacement_method: input.replacementMethod,
    p_replacement_reference: input.replacementReference?.trim() || null,
    p_replacement_remarks: input.replacementRemarks?.trim() || null,
  };
}

/** Keeps Diesel and Voucher totals sourced from the authoritative rebuild response. */
export function readAuthoritativeDieselPaymentState(
  result: Record<string, unknown>
): AuthoritativeDieselPaymentState {
  const totalAmount = Number(result.diesel_total);
  const paidAmount = Number(result.diesel_paid);
  const remainingAmount = Number(result.diesel_remaining);
  const paymentStatus = typeof result.diesel_status === "string" ? result.diesel_status : "";
  if (
    !Number.isFinite(totalAmount) ||
    !Number.isFinite(paidAmount) ||
    !Number.isFinite(remainingAmount) ||
    !paymentStatus
  ) {
    throw new Error("authoritative_rebuild_state_missing");
  }
  return { totalAmount, paidAmount, remainingAmount, paymentStatus };
}
