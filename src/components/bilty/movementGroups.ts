import type { BiltyMovementGroup, BiltyRow } from "./types";

export function shortMovementGroupId(id: string): string {
  return id.replaceAll("-", "").slice(0, 6).toUpperCase();
}

export function movementGroupReference(
  group: BiltyMovementGroup,
  groupLabel: string
): string {
  return `${group.outbound_bilty_no} — ${groupLabel} ${shortMovementGroupId(group.id)}`;
}

export function getOpenMovementGroups(
  groups: BiltyMovementGroup[],
  addaId: string,
  bilties: BiltyRow[]
): BiltyMovementGroup[] {
  return groups.filter((group) =>
    group.adda_id === addaId &&
    group.status === "open" &&

    // Local trips do NOT close the Movement Group.
    // Only an existing Return Bilty makes the group unavailable.
    !bilties.some((bilty) =>
      bilty.adda_id === addaId &&
      bilty.bilty_group_id === group.id &&
      bilty.trip_type === "return"
    )
  );
}