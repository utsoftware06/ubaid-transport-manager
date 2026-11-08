/* eslint-disable @typescript-eslint/no-require-imports */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const ts = require("typescript");

const sourcePath = path.join(
  __dirname,
  "..",
  "src",
  "components",
  "vehicle-documents",
  "ownership.ts"
);
const source = fs.readFileSync(sourcePath, "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
const ownershipModule = { exports: {} };
new Function("exports", "require", "module", compiled)(
  ownershipModule.exports,
  require,
  ownershipModule
);

const {
  resolveVehicleDocumentOwnerAddaId,
  resolveSingleVehicleDocumentOwnerAddaId,
} = ownershipModule.exports;

assert.equal(resolveVehicleDocumentOwnerAddaId("adda-a", "adda-a"), "adda-a");
assert.equal(resolveVehicleDocumentOwnerAddaId(null, "adda-a"), "adda-a");
assert.equal(resolveVehicleDocumentOwnerAddaId(undefined, "adda-a"), "adda-a");
assert.equal(resolveVehicleDocumentOwnerAddaId("adda-b", "adda-a"), null);
assert.equal(resolveVehicleDocumentOwnerAddaId("adda-a", null), null);
assert.equal(resolveVehicleDocumentOwnerAddaId(null, null), null);

assert.equal(resolveSingleVehicleDocumentOwnerAddaId(["adda-a", "adda-a"]), "adda-a");
assert.equal(resolveSingleVehicleDocumentOwnerAddaId(["adda-a", "adda-b"]), null);
assert.equal(resolveSingleVehicleDocumentOwnerAddaId(["adda-a", null]), null);
assert.equal(resolveSingleVehicleDocumentOwnerAddaId([]), null);

console.log("Vehicle document owner resolution: 10 assertions passed.");
