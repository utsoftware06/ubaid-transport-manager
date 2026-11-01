export type PaymentReceiptBooking = {
  booking_no: string | null;
  sender_name: string | null;
  freight: number | string | null;
  parties: {
    name: string | null;
  } | null;
};

export type PaymentReceiptLoading = {
  id: number;
  loading_no: string | null;
  loading_date: string | null;
  advance_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  bookings: PaymentReceiptBooking | null;
};

export type PaymentReceiptRecord = {
  id: string;
  receipt_no: string;
  receipt_date: string;
  loading_id: number;
  amount: number;
  payment_method: string;
  remarks: string | null;
  created_at?: string | null;
  loadings: {
    id?: number;
    loading_no: string | null;
    advance_amount?: number | string | null;
    remaining_amount?: number | string | null;
    payment_status?: string | null;
    bookings: PaymentReceiptBooking | null;
  } | null;
};
