export type PackingLoadingItem = {
  id: number;
  loading_id: number;
  item_name: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string | null;
};

export type PackingLoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  booking_id: number | string | null;
  vehicle_id: number | string;
  driver_id: number | string;
  route: string;
  vehicles?: {
    vehicle_no: string;
    adda_id: string | null;
  } | null;
  bookings?: { adda_id: string | null } | null;
  drivers?: {
    name: string;
  } | null;
  loading_items?: PackingLoadingItem[];
};

export type PackingSlipItem = {
  id: number;
  packing_slip_id: number;
  item_name: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string | null;
};

export type PackingSlipRecord = {
  id: number;
  packing_slip_no: string;
  packing_date: string;
  loading_id: number | string;
  remarks: string | null;
  loadings?: PackingLoadingRecord | null;
  packing_slip_items?: PackingSlipItem[];
};
