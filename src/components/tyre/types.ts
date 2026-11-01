export type TyreShopType = "external_supplier" | "adda_owned";
export type TyreSourceType = "external_shop" | "adda_stock";
export type TyreProductType = "new" | "used" | "retread";
export type TyreAssetStatus = "in_stock" | "fitted" | "removed" | "transferred" | "repair" | "retread" | "fitted_again" | "sold" | "scrapped" | "lost";
export type TyreWorkType = "new_tyre" | "used_tyre" | "replacement" | "puncture" | "retread" | "tube" | "flap" | "wheel_alignment" | "wheel_balancing" | "other";
export type TyrePositionSide = "left" | "right" | "center" | "spare" | "other";

export type TyreShop = { id:string; addaId:string; shopName:string; shopType:TyreShopType; ownerName:string; phone:string; address:string; openingBalance:number; isActive:boolean };
export type TyreProduct = { id:string; addaId:string; brand:string; size:string; modelPattern:string; tyreType:TyreProductType; manufacturer:string; notes:string; isActive:boolean };
export type VehicleOption = { id:string; vehicleNo:string };
export type TyrePosition = { id:string; addaId:string; vehicleId:string; axleNumber:number|null; side:TyrePositionSide; slotNumber:number; isSpare:boolean; positionCode:string; positionLabel:string; sortOrder:number; isActive:boolean };
export type TyreAsset = { id:string; addaId:string; tyreProductId:string; serialNumber:string; normalizedSerialNumber:string; sourceType:TyreSourceType; tyreShopId:string; purchaseReference:string; purchaseDate:string; purchaseCost:number; currentStatus:TyreAssetStatus; currentVehicleId:string; currentPositionId:string; currentOdometer:number|null };
export type TyreEntry = { id:string; addaId:string; vehicleId:string; entryDate:string; sourceType:TyreSourceType; tyreShopId:string; workType:TyreWorkType; billNo:string; odometer:number|null; totalAmount:number; remarks:string };
export type TyreEntryItem = { id:string; entryId:string; lineNo:number; workType:TyreWorkType; tyreAssetId:string; positionId:string; quantity:number; rate:number; amount:number; remarks:string };
export type TyreFitment = { id:string; tyreAssetId:string; vehicleId:string; positionId:string; fittedDate:string; fittingOdometer:number|null; removedDate:string; removalOdometer:number|null; removalReason:string; resultingStatus:TyreAssetStatus|null; sourceEntryId:string };
export type TyreEvent = { id:string; tyreAssetId:string; eventType:TyreAssetStatus; eventDate:string; vehicleId:string; positionId:string; odometer:number|null; sourceEntryId:string; remarks:string; createdAt:string };
export type EntryLine = { key:string; workType:TyreWorkType; tyreAssetId:string; positionId:string; quantity:string; rate:string; remarks:string; removalReason:string };

export const money = (value:number) => `Rs. ${Number(value || 0).toLocaleString("en-PK",{maximumFractionDigits:2})}`;
