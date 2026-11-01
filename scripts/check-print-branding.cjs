const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const ts = require("typescript");

const sourcePath = path.join(__dirname, "../src/lib/print/brandingProjection.ts");
const source = fs.readFileSync(sourcePath, "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
const projectionModule = { exports: {} };
new Function("module", "exports", compiled)(projectionModule, projectionModule.exports);
const { projectPrintBranding } = projectionModule.exports;

const addaA = {
  id: "adda-a",
  name: "Transport A",
  address: "A Address",
  city: "A City",
  phone: "0300-0000001",
};
const addaB = {
  id: "adda-b",
  name: "Ubaid Goods Transport",
  address: "B Address",
  city: "B City",
  phone: "0300-0000002",
};
const settingsA = {
  adda_id: "adda-a",
  company_name: "UT Software",
  business_tagline: "A stationery",
  logo_url: "https://example.invalid/a.png",
  address: "A Settings Address",
  city: "A Settings City",
  phone: "0300-1111111",
  alternate_phone: null,
  paper_size: "A4",
  show_logo_on_print: true,
  print_footer_text: null,
};
const settingsB = {
  ...settingsA,
  adda_id: "adda-b",
  company_name: "UT Software",
  business_tagline: "B stationery",
  logo_url: "https://example.invalid/b.png",
  address: "B Settings Address",
  city: "B Settings City",
  phone: "0300-2222222",
};

// Super Admin prints Adda B while Adda A is another available/current context.
const superAdminDocumentBrand = projectPrintBranding("adda-b", settingsB, addaB);
assert.equal(superAdminDocumentBrand.addaName, "Ubaid Goods Transport");
assert.equal(superAdminDocumentBrand.address, "B Settings Address");
assert.equal(superAdminDocumentBrand.phone, "0300-2222222");
assert.equal(superAdminDocumentBrand.logoUrl, "https://example.invalid/b.png");

// Mismatched settings/fallback records cannot leak Adda A into Adda B's output.
const mismatchedBrand = projectPrintBranding("adda-b", settingsA, addaA);
assert.equal(mismatchedBrand.addaName, "");
assert.equal(mismatchedBrand.address, null);
assert.equal(mismatchedBrand.phone, null);
assert.equal(mismatchedBrand.logoUrl, null);

// The legacy company_settings.company_name value is not an organization-name fallback.
const noAddaNameBrand = projectPrintBranding("adda-b", settingsB, null);
assert.equal(noAddaNameBrand.addaName, "");

// Missing settings use only the owning Adda's identity/contact fallback.
const noSettingsBrand = projectPrintBranding("adda-b", null, addaB);
assert.equal(noSettingsBrand.addaName, "Ubaid Goods Transport");
assert.equal(noSettingsBrand.address, "B Address");
assert.equal(noSettingsBrand.city, "B City");
assert.equal(noSettingsBrand.phone, "0300-0000002");

console.log("PASS: owning-Adda branding projection, cross-Adda isolation and missing-settings fallback");
