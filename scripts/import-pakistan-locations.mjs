/**
 * Imports an authoritative, reviewed hierarchy JSON file. This script ships no
 * fabricated location data. Input rows: { key, parentKey, type, name }.
 * Run server-side only with SUPABASE_SERVICE_ROLE_KEY after reviewing the file.
 */
import { readFile } from "node:fs/promises";
import { createClient } from "@supabase/supabase-js";

const argumentsList = process.argv.slice(2);
const dryRun = argumentsList.includes("--dry-run");
const inputPath = argumentsList.find((value) => value !== "--dry-run");
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!inputPath) throw new Error("Usage: node scripts/import-pakistan-locations.mjs data/pakistan-locations.json [--dry-run]");
const rows = JSON.parse(await readFile(inputPath, "utf8"));
if (!Array.isArray(rows)) throw new Error("Verified location input must be an array");
const allowed = new Set(["province","division","district","tehsil","city","town","village","locality"]);
const rowsByKey = new Map();
for (const row of rows) {
  const key = typeof row?.key === "string" ? row.key.trim() : "";
  if (!row || typeof row !== "object" || typeof row.key !== "string" || !row.key.trim() ||
      typeof row.name !== "string" || !row.name.trim() || !allowed.has(row.type) ||
      (row.parentKey !== null && row.parentKey !== undefined && typeof row.parentKey !== "string")) {
    throw new Error(`Invalid authoritative row: ${JSON.stringify(row)}`);
  }
  if (rowsByKey.has(key)) throw new Error(`Duplicate location key: ${key}`);
  rowsByKey.set(key, { ...row, key, name: row.name.trim(), parentKey: row.parentKey?.trim() || null });
}
for (const row of rowsByKey.values()) {
  if (row.parentKey && !rowsByKey.has(row.parentKey)) throw new Error(`Missing parent ${row.parentKey} for ${row.key}`);
  if (row.parentKey === row.key) throw new Error(`Location ${row.key} cannot parent itself`);
}
const visiting = new Set();
const visited = new Set();
function validateAcyclic(key) {
  if (visited.has(key)) return;
  if (visiting.has(key)) throw new Error(`Cyclic location hierarchy detected at ${key}`);
  visiting.add(key);
  const parentKey = rowsByKey.get(key).parentKey;
  if (parentKey) validateAcyclic(parentKey);
  visiting.delete(key);
  visited.add(key);
}
for (const key of rowsByKey.keys()) validateAcyclic(key);
if (dryRun) {
  console.log(`Validated ${rowsByKey.size} reviewed Pakistan location rows; no database writes performed.`);
  process.exit(0);
}
if (!url || !serviceKey) throw new Error("NEXT_PUBLIC_SUPABASE_URL and server-only SUPABASE_SERVICE_ROLE_KEY are required");
const client = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
const ids = new Map();
const signature = (parentId, type, name) => `${parentId ?? "ROOT"}|${type}|${name.normalize("NFKC").toLocaleLowerCase("en").replace(/\s+/g, " ").trim()}`;
const existingBySignature = new Map();
for (let offset = 0; ; offset += 1000) {
  const { data, error } = await client.from("pakistan_locations")
    .select("id, parent_id, location_type, normalized_name, is_active")
    .order("id").range(offset, offset + 999);
  if (error) throw error;
  for (const row of data ?? []) existingBySignature.set(signature(row.parent_id, row.location_type, row.normalized_name), row);
  if ((data?.length ?? 0) < 1000) break;
}
const depthMemo = new Map();
function depthFor(key) {
  if (depthMemo.has(key)) return depthMemo.get(key);
  const parentKey = rowsByKey.get(key).parentKey;
  const depth = parentKey ? depthFor(parentKey) + 1 : 0;
  depthMemo.set(key, depth);
  return depth;
}
const rowsByDepth = new Map();
for (const [key, row] of rowsByKey) {
  const depth = depthFor(key);
  if (!rowsByDepth.has(depth)) rowsByDepth.set(depth, []);
  rowsByDepth.get(depth).push([key, row]);
}
const reactivationIds = [];
for (const depth of [...rowsByDepth.keys()].sort((a, b) => a - b)) {
  const missing = [];
  for (const [key, row] of rowsByDepth.get(depth)) {
    const parent_id = row.parentKey ? ids.get(row.parentKey) : null;
    if (row.parentKey && !parent_id) throw new Error(`Parent ${row.parentKey} was not resolved for ${key}`);
    const existing = existingBySignature.get(signature(parent_id, row.type, row.name));
    if (existing) {
      ids.set(key, existing.id);
      if (!existing.is_active) reactivationIds.push(existing.id);
    } else missing.push({ key, payload: { parent_id, location_type: row.type, name: row.name, is_active: true } });
  }
  for (let index = 0; index < missing.length; index += 500) {
    const batch = missing.slice(index, index + 500);
    const { data, error } = await client.from("pakistan_locations").insert(batch.map((item) => item.payload))
      .select("id, parent_id, location_type, normalized_name, is_active");
    if (error) throw error;
    const inserted = new Map((data ?? []).map((row) => [signature(row.parent_id, row.location_type, row.normalized_name), row]));
    for (const item of batch) {
      const row = inserted.get(signature(item.payload.parent_id, item.payload.location_type, item.payload.name));
      if (!row) throw new Error(`Inserted location could not be resolved: ${item.key}`);
      ids.set(item.key, row.id);
      existingBySignature.set(signature(row.parent_id, row.location_type, row.normalized_name), row);
    }
  }
}
for (let index = 0; index < reactivationIds.length; index += 200) {
  const { error } = await client.from("pakistan_locations").update({ is_active: true }).in("id", reactivationIds.slice(index, index + 200));
  if (error) throw error;
}
console.log(`Imported ${ids.size} reviewed Pakistan location rows.`);
