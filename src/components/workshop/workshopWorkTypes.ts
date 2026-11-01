export const WORKSHOP_WORK_TYPE_GROUPS = [
  ["engine", ["engine_repair","engine_overhaul","engine_tuning","head_gasket","valve_work","piston_ring_work","timing_work","engine_mount","oil_leakage_repair"]],
  ["oil_filters", ["engine_oil_change","gear_oil","differential_oil","oil_filter","diesel_fuel_filter","air_filter","greasing"]],
  ["clutch_gear", ["clutch_plate","pressure_plate","clutch_bearing","clutch_repair","gearbox_repair","gearbox_overhaul","gear_lever_linkage"]],
  ["brakes", ["brake_service","brake_shoe_lining","brake_pad","brake_drum","brake_disc","brake_chamber","master_cylinder","brake_oil","air_brake_repair"]],
  ["suspension", ["leaf_spring_kamani","kamani_bush","shock_absorber","u_bolt","hanger","suspension_bush","axle_repair"]],
  ["steering", ["steering_repair","steering_box","power_steering","tie_rod","drag_link","ball_joint","wheel_alignment"]],
  ["tyre_wheel", ["tyre_change","tyre_repair_puncture","tube_change","wheel_rim_repair","wheel_bearing","wheel_balancing"]],
  ["electrical", ["self_starter","alternator","battery_work","wiring","lights","horn","fuse_relay","meter_sensor","dynamo"]],
  ["cooling", ["radiator_repair","radiator_cleaning","water_pump","coolant","fan_belt","hose_pipe","thermostat"]],
  ["fuel_diesel", ["diesel_pump","injector_service","fuel_pump","fuel_tank_repair","fuel_pipe_leakage"]],
  ["body", ["body_repair","welding","denting","painting","cabin_repair","door_lock","glass_mirror","bumper"]],
  ["truck_trailer", ["chassis_repair","chassis_welding","axle_work","hub_repair","king_pin","propeller_cross","differential_repair","crown_pinion","trailer_body_floor"]],
  ["other", ["ac_repair","silencer_exhaust","general_service","washing_service","labour","emergency_repair","other_work"]],
] as const;

export type WorkshopWorkCategory = (typeof WORKSHOP_WORK_TYPE_GROUPS)[number][0];
export type WorkshopWorkType = (typeof WORKSHOP_WORK_TYPE_GROUPS)[number][1][number];

export type WorkshopWorkItem = {
  id?: number;
  clientId: string;
  workType: string;
  category: string;
  quantity: string;
  rate: string;
  amount: number;
  remarks: string;
};

export function createWorkshopWorkItem(): WorkshopWorkItem {
  return { clientId: crypto.randomUUID(), workType: "", category: "", quantity: "1", rate: "0", amount: 0, remarks: "" };
}

export function getWorkCategory(workType: string) {
  return WORKSHOP_WORK_TYPE_GROUPS.find(([, items]) => (items as readonly string[]).includes(workType))?.[0] ?? "";
}

export function getWorkTypeLabel(workType: string, t: (key: string) => string) {
  const key = `workshop.workItems.types.${workType}`;
  const translated = t(key);
  return translated === key ? workType : translated;
}
