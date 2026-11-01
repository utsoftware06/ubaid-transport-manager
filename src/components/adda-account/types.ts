export type AddaAccountKind = "income" | "expense";
export type AddaAccountStatus = "pending" | "partial" | "settled" | "reversal" | "reversed" | "employeeManaged" | "realized";

export type AddaAccountCategory = {
  id: string;
  adda_id: string;
  category_code: string;
  name: string;
  source_policy: "manual";
  is_active: boolean;
};

export type AddaFinanceSummary = {
  total_income: number;
  total_expense: number;
  net_profit: number;
  bilty_margin_income: number;
  bilty_loss_expense: number;
  vehicle_monthly_commission_income: number;
  employee_expense: number;
  other_income: number;
  settled_income: number;
  pending_income: number;
  settled_expense: number;
  pending_expense: number;
  bilty_margin_earned: number;
  bilty_margin_realized: number;
  bilty_margin_pending: number;
  vehicle_commission_effective: number;
  issued_freight_financing_commission_income: number;
};

export type AddaAccountEntry = {
  id: string;
  adda_id: string;
  entry_date: string;
  entry_kind: AddaAccountKind;
  category_id: string | null;
  category_code: string | null;
  category_name: string | null;
  amount: number;
  source_type: string;
  source_id: string;
  booking_id: string | null;
  loading_id: number | null;
  vehicle_id: string | null;
  employee_id: string | null;
  salary_record_id: number | null;
  reference_no: string | null;
  description: string | null;
  remarks: string | null;
  adda_name: string | null;
  reverses_entry_id: string | null;
  request_id: string | null;
  created_at: string;
  created_by: string | null;
  net_settled_amount: number;
  pending_amount: number;
  is_reversal: boolean;
  is_reversed: boolean;
  entry_status: AddaAccountStatus;
  earned_amount: number | null;
  realized_amount: number | null;
  margin_pending_amount: number | null;
  received_basis_amount: number | null;
  vehicle_freight: number | null;
  freight: number | null;
  realization_status: "pending" | "partial" | "realized" | "reversed" | null;
  loading_details?: AddaLoadingMarginDetails | null;
};

export type AddaLoadingMarginDetails = {
  loading_id: number;
  booking_id: string;
  booking_no: string | null;
  loading_no: string | null;
  loading_date: string | null;
  vehicle_no: string | null;
  from_city: string | null;
  to_city: string | null;
  route: string | null;
  margin_amount: number;
  is_reversed: boolean;
};

export type AddaFinanceSettlement = {
  id: string;
  account_entry_id: string;
  event_type: "settlement" | "reversal";
  payment_date: string;
  amount: number;
  payment_method: string | null;
  reference_no: string | null;
  remarks: string | null;
  reversal_reason: string | null;
  reverses_settlement_id: string | null;
  created_at: string;
  entry_kind: AddaAccountKind;
  cashbook_entry_type: "Cash In" | "Cash Out" | null;
  cashbook_reference_type: string | null;
  cashbook_reference_id: string | null;
};

export type AddaAccountEmployee = { id: string; employee_name: string };

export type AddaAccountFilters = {
  from: string | null;
  to: string | null;
  kind: AddaAccountKind | null;
  categoryId: string | null;
  employeeId: string | null;
  search: string | null;
  limit: number;
  offset: number;
};

export type AddaExpensePayload = {
  addaId: string;
  expenseDate: string;
  categoryId: string;
  amount: number;
  paidAmount: number;
  paymentMethod: string | null;
  employeeId: string | null;
  referenceNo: string | null;
  description: string | null;
  remarks: string | null;
  requestId: string;
};

export type AddaOtherIncomePayload = {
  addaId: string;
  incomeDate: string;
  amount: number;
  receivedAmount: number;
  paymentMethod: string | null;
  referenceNo: string | null;
  description: string | null;
  remarks: string | null;
  requestId: string;
};

export type AddaSettlementPayload = {
  addaId: string;
  accountEntryId: string;
  paymentDate: string;
  amount: number;
  paymentMethod: string;
  requestId: string;
  referenceNo: string | null;
  remarks: string | null;
};

export type AddaAccountEntryMetadataPayload = {
  addaId: string;
  accountEntryId: string;
  referenceNo: string | null;
  description: string | null;
  remarks: string | null;
  requestId: string;
};

export type AddaAccountEntryMetadata = {
  account_entry_id: string;
  adda_name: string;
  reference_no: string | null;
  description: string | null;
  remarks: string | null;
};
