export interface Booking {
  id: string;
  adda_id: string;
  booking_no: string;
  booking_date: string;
  sender_name: string;
  sender_phone: string;
  receiver_name: string;
  receiver_phone: string;
  from_city: string;
  to_city: string;
  goods_name: string;
  quantity: number;
  weight: number;
  freight: number;
  status: string;
  created_at: string;
}

export interface Adda {
  id: string;
  name: string;
}