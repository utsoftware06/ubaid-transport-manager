export type OilShopType = "external_supplier" | "adda_owned";
export type OilSourceType = "external_shop" | "adda_stock";
export type OilMovementType = "opening_stock" | "purchase" | "own_vehicle_issue" | "external_vehicle_sale" | "adjustment_in" | "adjustment_out";

export type OilShop = { id: string; addaId: string; shopName: string; shopType: OilShopType; ownerName: string; phone: string; address: string; openingBalance: number; isActive: boolean };
export type OilProduct = { id: string; addaId: string; oilType: string; brand: string; grade: string; isActive: boolean };
export type VehicleOption = { id: string; vehicleNo: string; ownerName: string };
export type PartyOption = { id: string; partyName: string };
export type PurchaseLine = { key: string; oilProductId: string; liters: string; ratePerLiter: string; batchReference: string };
export type OilPurchase = { id: string; purchaseDate: string; oilShopId: string; shopName: string; billNo: string; totalAmount: number; paidAmount: number; remainingAmount: number; paymentStatus: string; remarks: string; items: PurchaseLine[] };
export type OilSupplierBill = { id: string; oilShopId: string; sourceType: "oil_purchase" | "oil_vehicle_entry"; sourceId: string; billDate: string; billNo: string; amount: number; paidAmount: number; remainingAmount: number; paymentStatus: string };
export type OilStockMovement = { id: string; movementDate: string; oilProductId: string; movementType: OilMovementType; litersIn: number; litersOut: number; unitCost: number; referenceType: string; referenceId: string; remarks: string };
export type OilVehicleEntry = { id: string; entryDate: string; vehicleId: string; sourceType: OilSourceType; oilShopId: string; oilProductId: string; liters: number; ratePerLiter: number; totalAmount: number; billNo: string; odometer: number | null; nextOilChangeDate: string; remarks: string; attachedVoucherId: number | null; attachedVoucherNo: string; attachedVoucherDate: string };
export type OilExternalSale = { id: string; saleDate: string; oilProductId: string; vehicleNo: string; partyId: string; ownerName: string; phone: string; liters: number; saleRatePerLiter: number; totalAmount: number; receivedAmount: number; remainingAmount: number; saleStatus: string; paymentMethod: string; remarks: string };

export function productLabel(product: OilProduct | undefined) {
  return product ? [product.oilType, product.brand, product.grade].filter(Boolean).join(" · ") : "-";
}

export function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}
