export type PartyRecord = {
  id: string;
  adda_id: string;
  name: string;
  phone: string | null;
  city: string | null;
  address: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type PartyFormValues = {
  name: string;
  phone: string;
  city: string;
  address: string;
  addaId: string;
  isActive: boolean;
};

export type PartyAddaOption = {
  id: string;
  name: string;
};
