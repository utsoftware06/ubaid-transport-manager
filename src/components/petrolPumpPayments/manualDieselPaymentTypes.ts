export type ManualDieselLinkedPaymentView = {
  requestId: string;
  paymentId: number;
  addaId: string;
  voucherId: number;
  voucherNumber: string;
  manualVoucherId: string;
  voucherStatus: "draft" | "finalized";
  dieselEntryId: number;
  vehicleNo: string;
  correctionStatus: "active" | "voided";
  paymentDate: string;
  paidAmount: number;
  paymentMethod: string;
  referenceNo: string | null;
  paymentRemarks: string | null;
  dieselTotal: number;
  dieselPaid: number;
  dieselRemaining: number;
  dieselStatus: string;
};

export type ManualDieselCorrectionHistoryView = {
  id: number;
  originalPaymentId: number;
  replacementPaymentId: number | null;
  addaId: string;
  voucherNumber: string;
  dieselEntryId: number;
  action: "void" | "replace";
  reason: string;
  createdAt: string;
  originalSnapshot: Record<string, unknown>;
  replacementSnapshot: Record<string, unknown> | null;
};
