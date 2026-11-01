/**
 * Build UT Software's reviewed Pakistan hierarchy from the official GeoNames
 * Pakistan country dump. GeoNames data: CC BY 4.0, https://www.geonames.org/.
 *
 * Usage:
 *   node scripts/build-pakistan-locations-geonames.mjs <PK.txt> [output.json]
 */
import { readFile, writeFile } from "node:fs/promises";

const [sourcePath, outputPath = "data/pakistan-locations.json"] = process.argv.slice(2);
if (!sourcePath) throw new Error("Usage: node scripts/build-pakistan-locations-geonames.mjs <PK.txt> [output.json]");

const source = await readFile(sourcePath, "utf8");
const sourceRows = source.split(/\r?\n/).filter(Boolean).map((line) => {
  const field = line.split("\t");
  return {
    id: field[0], name: field[1]?.trim().replace(/\s+/g, " "),
    featureClass: field[6], featureCode: field[7], countryCode: field[8],
    admin1: field[10] || "", admin2: field[11] || "",
    admin3: field[12] || "", admin4: field[13] || "",
    population: Number(field[14] || 0),
  };
}).filter((row) => row.countryCode === "PK" && row.id && row.name);

const byAdmin1 = new Map();
const byAdmin2 = new Map();
const byAdmin3 = new Map();
const byAdmin4 = new Map();
for (const row of sourceRows) {
  if (row.featureCode === "ADM1" && row.admin1) byAdmin1.set(row.admin1, row);
  if (row.featureCode === "ADM2" && row.admin1 && row.admin2) byAdmin2.set(`${row.admin1}|${row.admin2}`, row);
  if (row.featureCode === "ADM3" && row.admin1 && row.admin3) byAdmin3.set(`${row.admin1}|${row.admin2}|${row.admin3}`, row);
  if (row.featureCode === "ADM4" && row.admin1 && row.admin4) byAdmin4.set(`${row.admin1}|${row.admin2}|${row.admin3}|${row.admin4}`, row);
}

const output = [];
const included = new Set();
const logicalKeys = new Map();
let duplicateConflictCount = 0;
let skippedWithoutProvince = 0;
const keyFor = (row) => `geonames:${row.id}`;
const normalized = (value) => value.normalize("NFKC").toLocaleLowerCase("en").replace(/\s+/g, " ").trim();

function add(row, type, parentRow) {
  const parentKey = parentRow ? keyFor(parentRow) : null;
  const logicalKey = `${parentKey ?? "ROOT"}|${type}|${normalized(row.name)}`;
  if (logicalKeys.has(logicalKey)) {
    duplicateConflictCount += 1;
    return false;
  }
  logicalKeys.set(logicalKey, row.id);
  output.push({ key: keyFor(row), parentKey, type, name: row.name });
  included.add(row.id);
  return true;
}

for (const row of sourceRows.filter((item) => item.featureCode === "ADM1")) add(row, "province", null);
for (const row of sourceRows.filter((item) => item.featureCode === "ADM2")) {
  const province = byAdmin1.get(row.admin1);
  if (!province || !included.has(province.id)) { skippedWithoutProvince += 1; continue; }
  add(row, "district", province);
}
for (const row of sourceRows.filter((item) => item.featureCode === "ADM3")) {
  const province = byAdmin1.get(row.admin1);
  const district = byAdmin2.get(`${row.admin1}|${row.admin2}`);
  const parent = district && included.has(district.id) ? district : province;
  if (!parent || !included.has(parent.id)) { skippedWithoutProvince += 1; continue; }
  add(row, "tehsil", parent);
}
for (const row of sourceRows.filter((item) => item.featureCode === "ADM4")) {
  const province = byAdmin1.get(row.admin1);
  const district = byAdmin2.get(`${row.admin1}|${row.admin2}`);
  const tehsil = byAdmin3.get(`${row.admin1}|${row.admin2}|${row.admin3}`);
  const parent = tehsil && included.has(tehsil.id) ? tehsil : district && included.has(district.id) ? district : province;
  if (!parent || !included.has(parent.id)) { skippedWithoutProvince += 1; continue; }
  add(row, "locality", parent);
}

const populatedCodes = new Set(["PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPL", "PPLF", "PPLG", "PPLL", "PPLR", "PPLS", "PPLX"]);
function populatedType(row) {
  if (["PPLL", "PPLS", "PPLX"].includes(row.featureCode)) return "locality";
  if (["PPLC", "PPLA", "PPLA2"].includes(row.featureCode) || row.population >= 100000) return "city";
  if (["PPLA3", "PPLA4", "PPLA5"].includes(row.featureCode) || row.population >= 10000) return "town";
  return "village";
}
for (const row of sourceRows.filter((item) => item.featureClass === "P" && populatedCodes.has(item.featureCode))) {
  const province = byAdmin1.get(row.admin1);
  const district = byAdmin2.get(`${row.admin1}|${row.admin2}`);
  const tehsil = byAdmin3.get(`${row.admin1}|${row.admin2}|${row.admin3}`);
  const admin4 = byAdmin4.get(`${row.admin1}|${row.admin2}|${row.admin3}|${row.admin4}`);
  const parent = admin4 && included.has(admin4.id) ? admin4 : tehsil && included.has(tehsil.id) ? tehsil : district && included.has(district.id) ? district : province;
  if (!parent || !included.has(parent.id)) { skippedWithoutProvince += 1; continue; }
  add(row, populatedType(row), parent);
}

const order = new Map(["province", "division", "district", "tehsil", "city", "town", "village", "locality"].map((type, index) => [type, index]));
output.sort((a, b) => (order.get(a.type) - order.get(b.type)) || a.key.localeCompare(b.key));
await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`, "utf8");
const counts = Object.fromEntries([...order.keys()].map((type) => [type, output.filter((row) => row.type === type).length]));
console.log(JSON.stringify({ sourceRows: sourceRows.length, outputRecords: output.length, counts, duplicateConflictCount, skippedWithoutProvince }, null, 2));
