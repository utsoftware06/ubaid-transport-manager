export type ExpenseClass = "regular_trip" | "vehicle_periodic";

export const EXPENSE_TYPES_BY_CLASS: Record<ExpenseClass, readonly string[]> = {
  regular_trip: [
    "Fuel",
    "Toll Tax",
    "Food",
    "Labour",
    "Maintenance",
    "Police",
    "Parking",
    "Other",
    "Driver Kharcha",
    "Munshiana",
    "Loading / Unloading",
  ],
  vehicle_periodic: [
    "Workshop",
    "Tyre",
    "Oil / Lubricants",
    "Driver Salary",
  ],
};

const PERIODIC_TYPES = new Set(EXPENSE_TYPES_BY_CLASS.vehicle_periodic);

const EXPENSE_TYPE_LABEL_KEYS: Record<string, string> = {
  Fuel: "fuel",
  "Toll Tax": "tolltax",
  Food: "food",
  Labour: "labour",
  Maintenance: "maintenance",
  Police: "police",
  Parking: "parking",
  Other: "other",
  "Driver Kharcha": "driverKharcha",
  Munshiana: "munshiana",
  "Loading / Unloading": "loadingUnloading",
  Workshop: "workshop",
  Tyre: "tyre",
  "Oil / Lubricants": "oilLubricants",
  "Driver Salary": "driverSalary",
};

export function normalizeExpenseClass(
  value: string | null | undefined,
  expenseType = ""
): ExpenseClass {
  if (value === "vehicle_periodic") return "vehicle_periodic";
  if (value === "regular_trip") return "regular_trip";
  return PERIODIC_TYPES.has(expenseType) ? "vehicle_periodic" : "regular_trip";
}

export function expenseTypeLabelKey(expenseType: string) {
  return `expenses.categories.${EXPENSE_TYPE_LABEL_KEYS[expenseType] ?? "other"}`;
}
