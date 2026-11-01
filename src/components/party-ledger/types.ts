export type PartyLedgerPeriod =
  | "all"
  | "today"
  | "last7Days"
  | "thisMonth"
  | "last6Months"
  | "thisYear"
  | "custom";

export type PartyPaymentStatus = "paid" | "partial" | "unpaid";

export type PartyLedgerFilters = {
  addaId: string;
  partyId: string;
  period: PartyLedgerPeriod;
  fromDate: string;
  toDate: string;
  search: string;
  paymentStatus: "all" | PartyPaymentStatus;
};

export type PartyLedgerOption = {
  id: string;
  name: string;
  addaId: string;
};

export type PartyLedgerAdda = {
  id: string;
  name: string;
};

export type PartyTripRow = {
  id: string;
  partyId: string;
  partyName: string;
  addaId: string;
  addaName: string;
  loadingId: string;
  loadingNo: string;
  loadingDate: string;
  bookingId: string;
  bookingNo: string;
  route: string;
  vehicleNo: string;
  driverName: string;
  freight: number;
  advance: number;
  receiptPayments: number;
  totalReceived: number;
  remaining: number;
  paymentStatus: PartyPaymentStatus;
};

export type PartyLedgerReport = {
  partyId: string;
  partyName: string;
  addaId: string;
  addaName: string;
  totalBookings: number;
  totalTrips: number;
  totalFreight: number;
  totalAdvance: number;
  totalReceiptPayments: number;
  totalReceived: number;
  remainingBalance: number;
  paymentStatus: PartyPaymentStatus;
  trips: PartyTripRow[];
};

export type PartyLedgerSummary = {
  totalParties: number;
  totalTrips: number;
  totalFreight: number;
  totalReceived: number;
  totalRemaining: number;
  paidParties: number;
  partialParties: number;
  unpaidParties: number;
};
