-- Stage A: add nullable Cashbook tenant ownership metadata only.
-- This migration deliberately does not backfill data or change access controls.
BEGIN;

ALTER TABLE public.cashbook_entries
  ADD COLUMN adda_id uuid NULL;

ALTER TABLE public.cashbook_entries
  ADD CONSTRAINT cashbook_entries_adda_id_fkey
  FOREIGN KEY (adda_id)
  REFERENCES public.addas (id)
  ON DELETE RESTRICT
  NOT VALID;

-- Existing rows receive NULL for the new column. Validate the FK now so the
-- catalog records a fully validated constraint before tenant values are added.
ALTER TABLE public.cashbook_entries
  VALIDATE CONSTRAINT cashbook_entries_adda_id_fkey;

-- Tenant equality is the leading lookup key; entry_date supports date ranges
-- and ordering within one tenant. Legacy NULL rows are omitted from this index.
CREATE INDEX cashbook_entries_adda_id_entry_date_idx
  ON public.cashbook_entries (adda_id, entry_date)
  WHERE adda_id IS NOT NULL;

COMMIT;
