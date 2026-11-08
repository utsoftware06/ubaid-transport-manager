/** Resolve a document's tenant only from its saved vehicle relationship. */
export function resolveVehicleDocumentOwnerAddaId(
  documentAddaId: string | null | undefined,
  vehicleAddaId: string | null | undefined
): string | null {
  if (!vehicleAddaId) return null;
  if (documentAddaId && documentAddaId !== vehicleAddaId) return null;
  return vehicleAddaId;
}

/** Mixed, missing, or conflicting ownership must not receive shared branding. */
export function resolveSingleVehicleDocumentOwnerAddaId(
  ownerAddaIds: Array<string | null | undefined>
): string | null {
  if (ownerAddaIds.length === 0 || ownerAddaIds.some((id) => !id)) return null;
  const owners = new Set(ownerAddaIds);
  return owners.size === 1 ? (ownerAddaIds[0] ?? null) : null;
}
