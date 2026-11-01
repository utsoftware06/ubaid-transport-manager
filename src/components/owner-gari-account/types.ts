export const OWNER_GARI_TRANSACTION_TYPES = [
  "opening_seed",
  "chakkar_net_credit",
  "manual_chakkar_net",
  "manual_chakkar_adjustment",
  "owner_withdrawal",
  "gari_withdrawal",
  "monthly_adda_commission",
  "monthly_adda_commission_reversal",
  "monthly_adda_commission_reissue",
  "monthly_adda_commission_adjustment_increase",
  "monthly_adda_commission_adjustment_decrease",
  "monthly_adda_commission_correction_reversal_credit",
  "monthly_adda_commission_correction_reversal_debit",
  "adjustment_credit",
  "adjustment_debit",
  "voucher_adjustment_expense",
] as const;

export type OwnerGariTransactionType =
  (typeof OWNER_GARI_TRANSACTION_TYPES)[number];

export type VehicleOption = {
  id: string;
  adda_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

export type MovementGroupOption = {
  movement_group_id: string;
  transaction_date: string;
  reference_no: string | null;
};

export type OwnerGariTransaction = {
  transaction_id: string;
  transaction_date: string;
  transaction_type: OwnerGariTransactionType;
  amount: number;
  signed_amount: number;
  credit: number;
  debit: number;
  running_balance: number;
  source_settlement_id: string | null;
  source_manual_settlement_id?: string | null;
  manual_settlement_id?: string | null;
  source_manual_adjustment_id?: string | null;
  manual_adjustment_id?: string | null;
  manual_voucher_id?: string | null;
  adjustment_no?: string | null;
  adjustment_reason?: string | null;
  adjustment_net?: number | null;
  reverses_adjustment_id?: string | null;
  manual_chakkar_days?: number | null;
  manual_total_freight?: number | null;
  source_adjustment_id?: string | null;
  source_commission_event_id?: string | null;
  commission_month?: string | null;
  commission_reversal_reason?: string | null;
  commission_reversal_date?: string | null;
  commission_event_type?: string | null;
  commission_parent_event_id?: string | null;
  commission_root_event_id?: string | null;
  commission_correction_reason?: string | null;
  commission_effective_root_amount?: number | null;
  commission_status?: "active" | "reversed" | "reversal" | null;
  movement_group_id: string | null;
  voucher_id: number | null;
  return_bilty_id: string | null;
  reference_no: string | null;
  description: string;
  created_at: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

export type OwnerGariStatement = {
  account: {
    account_id: string | null;
    adda_id: string;
    adda_name: string;
    vehicle_id: string;
    vehicle_no: string | null;
    owner_name: string | null;
  };
  period: {
    month: string | null;
    date_from: string | null;
    date_to: string | null;
  };
  summary: {
    opening_balance: number;
    total_chakkar_credit: number;
    total_manual_chakkar_credit?: number;
    total_manual_chakkar_debit?: number;
    total_manual_chakkar_net?: number;
    total_manual_chakkar_adjustment_credit?: number;
    total_manual_chakkar_adjustment_debit?: number;
    total_manual_chakkar_adjustment_net?: number;
    total_owner_withdrawn: number;
    total_monthly_commission: number;
    total_adjustment_credit: number;
    total_adjustment_debit: number;
    closing_balance: number;
  };
  available_movement_groups: MovementGroupOption[];
  transactions: OwnerGariTransaction[];
};

export type OwnerGariMonthlyClosing = {
  account: OwnerGariStatement["account"];
  period: {
    period_mode: "month" | "custom";
    month: string;
    period_start: string;
    period_end: string;
    period_label: string;
  };
  summary: {
    opening_balance: number;
    total_credits: number;
    total_debits: number;
    period_net_change: number;
    closing_balance: number;
    current_balance: number;
    current_balance_as_of_date: string;
    transaction_count: number;
    chakkar_credits: number;
    chakkar_debits: number;
    owner_withdrawals: number;
    gari_withdrawals: number;
    voucher_adjustment_expenses: number;
    manual_adjustment_credits: number;
    manual_adjustment_debits: number;
    owner_gari_net_commission_charge: number;
    adda_commission_income: number;
    adda_commission_expense: number;
    adda_commission_net_effect: number;
    commission_reconciliation_difference: number;
    commission_reconciliation_status: "Matched" | "Difference";
    commission_event_count: number;
    commission_missing_event_count: number;
    commission_cross_scope_event_count: number;
    commission_missing_journal_count: number;
    commission_duplicate_journal_count: number;
    commission_cross_scope_journal_count: number;
    commission_duplicate_owner_event_row_count: number;
  };
  transactions: OwnerGariTransaction[];
};

export type OwnerGariFilters = {
  vehicleId: string;
  ownerName: string;
  month: string;
  dateFrom: string;
  dateTo: string;
  transactionType: "" | OwnerGariTransactionType;
  movementGroupId: string;
  search: string;
};

export const OWNER_GARI_WITHDRAWAL_TYPES = [
  "owner_withdrawal",
  "gari_withdrawal",
] as const;

export type OwnerGariWithdrawalType =
  (typeof OWNER_GARI_WITHDRAWAL_TYPES)[number];

export const OWNER_GARI_PAYMENT_METHODS = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
] as const;

export type OwnerGariPaymentMethod =
  (typeof OWNER_GARI_PAYMENT_METHODS)[number];

export type OwnerGariWithdrawalInput = {
  vehicleId: string;
  withdrawalDate: string;
  withdrawalType: OwnerGariWithdrawalType;
  amount: string;
  paymentMethod: OwnerGariPaymentMethod;
  referenceNo: string;
  remarks: string;
  idempotencyKey: string;
};

export type OwnerGariWithdrawalReceipt = {
  transaction_id: string;
  transaction_date: string;
  transaction_type: OwnerGariWithdrawalType;
  amount: number;
  payment_method: string;
  reference_no: string | null;
  remarks: string;
  vehicle_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
  adda_id: string;
  adda_name: string;
  prepared_by: string;
  created_at: string;
  cashbook_id: number | string;
  cashbook_reference_type: "owner_gari_withdrawal";
  cashbook_reference_id: string;
};
