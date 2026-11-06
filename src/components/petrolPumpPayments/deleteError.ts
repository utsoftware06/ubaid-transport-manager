export type DeleteRpcError = {
  code?: string;
  message?: string;
};

export function getDeleteFailureKey(error: DeleteRpcError) {
  const message = error.message?.toUpperCase() ?? "";
  if (message.includes("MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED")) {
    return "petrolPumpPayments.messages.deleteLockedByManualVoucher";
  }
  if (message === "INVALID_TENANT") {
    return "petrolPumpPayments.messages.deleteTenantUnresolved";
  }
  if (message.includes("RECORDED PETROL PUMP ALLOCATION EXCEEDS THE DIESEL PAID AMOUNT")) {
    return "petrolPumpPayments.messages.deleteAllocationMismatch";
  }
  return "petrolPumpPayments.messages.deleteFailed";
}
