export interface Booking {
  id: string;
  adda_id: string;
  party_id: string | null;
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
  parties?: {
    name: string | null;
  } | null;
}

export interface Adda {
  id: string;
  name: string;
}

export interface BookingParty {
  id: string;
  adda_id: string;
  name: string;
  phone: string | null;
  city: string | null;
}
