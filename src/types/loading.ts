export type LoadingBooking = {
  id: string;
  adda_id?: string | null;
  booking_no: string | null;
  sender_name: string | null;
  receiver_name: string | null;
  freight: number | string | null;
  party_id: string | null;
  parties?: {
    name: string | null;
  } | null;
};

export type LoadingVehicle = {
  id: string;
  vehicle_no: string;
};

export type LoadingDriver = {
  id: string;
  name: string;
};

export type LoadingItem = {
  id: string;
  loading_id: string;
  item_name: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string | null;
};

export type LoadingRecord = {
  id: string;
  loading_no: string;
  loading_date: string;
  booking_id: string | null;
  vehicle_id: string;
  driver_id: string;
  route: string;
  advance_amount: number | null;
  remaining_amount: number | null;
  payment_status: string | null;
  vehicles?: {
    vehicle_no: string;
  } | null;
  drivers?: {
    name: string;
  } | null;
  bookings?: Omit<LoadingBooking, "id"> | null;
  loading_items?: LoadingItem[];
};
