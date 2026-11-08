/* eslint-disable @typescript-eslint/no-require-imports -- Node test harness. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");

const repo = path.resolve(__dirname, "..");
const helperPath = path.join(repo, "src/lib/storage/addaLogoCore.ts");
const migrationPath = path.join(repo, "supabase/migrations/202611080002_adda_logos_private_storage.sql");
const source = fs.readFileSync(helperPath, "utf8");
const migration = fs.readFileSync(migrationPath, "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
const moduleBox = { exports: {} };
vm.runInNewContext(
  `(function(require,module,exports){${compiled.outputText}\n})`,
  { Uint8Array, String, Object, RegExp, Error, Promise, Math },
  { filename: helperPath },
)(require, moduleBox, moduleBox.exports);

const {
  ADDA_LOGO_MAX_BYTES,
  buildAddaLogoReference,
  canManageAddaLogo,
  clearAddaLogoReference,
  parseAddaLogoReference,
  replaceAddaLogoReference,
  validateAddaLogoFile,
} = moduleBox.exports;

const addaA = "11111111-1111-4111-8111-111111111111";
const addaB = "22222222-2222-4222-8222-222222222222";
const objectA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const objectB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0x00]);
const webp = Uint8Array.from([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);

function file(name, type, bytes, size = bytes.length) {
  return { name, type, size, arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
}

function operations({ uploadResult = true, saveResult = "saved", removeResult = true, calls = [] } = {}) {
  return {
    upload: async (objectPath, selectedFile, mime) => { calls.push(["upload", objectPath, mime, selectedFile.name]); return uploadResult; },
    saveReference: async (reference) => { calls.push(["save", reference]); return saveResult; },
    remove: async (objectPath) => { calls.push(["remove", objectPath]); return removeResult; },
  };
}

async function main() {
  const validPng = await validateAddaLogoFile(file("mark.png", "image/png", png));
  assert.equal(validPng.valid && validPng.extension, "png");
  const validJpeg = await validateAddaLogoFile(file("mark.JPG", "image/jpeg", jpeg));
  assert.equal(validJpeg.valid && validJpeg.extension, "jpg");
  const validWebp = await validateAddaLogoFile(file("mark.webp", "image/webp", webp));
  assert.equal(validWebp.valid && validWebp.extension, "webp");
  assert.equal((await validateAddaLogoFile(file("mark.svg", "image/svg+xml", png))).reason, "type");
  assert.equal((await validateAddaLogoFile(file("mark.png", "text/html", png))).reason, "type");
  assert.equal((await validateAddaLogoFile(file("mark.png", "image/png", new TextEncoder().encode("<html>")))).reason, "content");
  assert.equal((await validateAddaLogoFile(file("broken.png", "image/png", png), async () => false)).reason, "content");
  assert.equal((await validateAddaLogoFile(file("mark.png", "image/png", png, ADDA_LOGO_MAX_BYTES + 1))).reason, "size");
  const invalidCalls = [];
  const invalidAttempt = await replaceAddaLogoReference({
    addaId: addaA, currentReference: null, file: file("markup.svg", "image/svg+xml", png), objectId: objectB,
    operations: operations({ calls: invalidCalls }),
  });
  assert.equal(invalidAttempt.status, "invalid");
  assert.equal(invalidCalls.length, 0);

  const privateReference = buildAddaLogoReference(`${addaA}/${objectA}.png`);
  assert.equal(parseAddaLogoReference(privateReference)?.addaId, addaA);
  assert.equal(parseAddaLogoReference(privateReference)?.path, `${addaA}/${objectA}.png`);
  assert.equal(parseAddaLogoReference(`storage://adda-logos/${addaB}/${objectA}.png`).addaId, addaB);
  assert.equal(parseAddaLogoReference("storage://adda-logos/not-a-uuid/logo.svg"), null);

  assert.equal(canManageAddaLogo("adda_admin", true, addaA, addaA), true);
  assert.equal(canManageAddaLogo("adda_admin", true, addaA, addaB), false);
  assert.equal(canManageAddaLogo("operator", true, addaA, addaA), false);
  assert.equal(canManageAddaLogo("adda_admin", false, addaA, addaA), false);
  assert.equal(canManageAddaLogo("super_admin", true, null, addaB), true);
  assert.equal(canManageAddaLogo("super_admin", true, null, null), false);

  const failedUploadCalls = [];
  const uploadFailure = await replaceAddaLogoReference({
    addaId: addaA, currentReference: privateReference, file: file("new.png", "image/png", png), objectId: objectB,
    operations: operations({ uploadResult: false, calls: failedUploadCalls }),
  });
  assert.equal(uploadFailure.status, "upload_failed");
  assert.equal(failedUploadCalls.some((call) => call[0] === "save" || call[0] === "remove"), false);

  const saveFailureCalls = [];
  const saveFailure = await replaceAddaLogoReference({
    addaId: addaA, currentReference: privateReference, file: file("new.png", "image/png", png), objectId: objectB,
    operations: operations({ saveResult: "unchanged", calls: saveFailureCalls }),
  });
  assert.equal(saveFailure.status, "save_failed");
  assert.deepEqual(saveFailureCalls.map((call) => call[0]), ["upload", "save", "remove"]);
  assert.equal(saveFailureCalls.at(-1)[1], `${addaA}/${objectB}.png`);

  const replaceCalls = [];
  const replaced = await replaceAddaLogoReference({
    addaId: addaA, currentReference: privateReference, file: file("new.png", "image/png", png), objectId: objectB,
    operations: operations({ calls: replaceCalls }),
  });
  assert.equal(replaced.status, "saved");
  assert.equal(replaced.reference, `storage://adda-logos/${addaA}/${objectB}.png`);
  assert.deepEqual(replaceCalls.map((call) => call[0]), ["upload", "save", "remove"]);
  assert.equal(replaceCalls[2][1], `${addaA}/${objectA}.png`);

  const legacyCalls = [];
  const legacyReplace = await replaceAddaLogoReference({
    addaId: addaA, currentReference: "https://legacy.example/logo.png", file: file("new.jpg", "image/jpeg", jpeg), objectId: objectB,
    operations: operations({ calls: legacyCalls }),
  });
  assert.equal(legacyReplace.status, "saved");
  assert.equal(legacyCalls.some((call) => call[0] === "remove"), false);

  const uncertainCalls = [];
  const uncertainReplace = await replaceAddaLogoReference({
    addaId: addaA, currentReference: privateReference, file: file("new.png", "image/png", png), objectId: objectB,
    operations: operations({ saveResult: "unknown", calls: uncertainCalls }),
  });
  assert.equal(uncertainReplace.status, "save_uncertain");
  assert.deepEqual(uncertainCalls.map((call) => call[0]), ["upload", "save"]);

  const crossTenantCalls = [];
  await clearAddaLogoReference({ addaId: addaA, currentReference: `storage://adda-logos/${addaB}/${objectA}.png`, operations: operations({ calls: crossTenantCalls }) });
  assert.deepEqual(crossTenantCalls.map((call) => call[0]), ["save"]);
  const removalFailureCalls = [];
  assert.equal(await clearAddaLogoReference({
    addaId: addaA, currentReference: privateReference, operations: operations({ saveResult: "unchanged", calls: removalFailureCalls }),
  }), "save_failed");
  assert.deepEqual(removalFailureCalls.map((call) => call[0]), ["save"]);
  const removalCalls = [];
  assert.equal(await clearAddaLogoReference({
    addaId: addaA, currentReference: privateReference, operations: operations({ calls: removalCalls }),
  }), "removed");
  assert.deepEqual(removalCalls.map((call) => call[0]), ["save", "remove"]);
  const legacyRemovalCalls = [];
  assert.equal(await clearAddaLogoReference({
    addaId: addaA, currentReference: "https://legacy.example/logo.png", operations: operations({ calls: legacyRemovalCalls }),
  }), "removed");
  assert.deepEqual(legacyRemovalCalls.map((call) => call[0]), ["save"]);
  assert.equal(buildAddaLogoReference(`${addaA}/${objectA}.png`) !== buildAddaLogoReference(`${addaA}/${objectB}.png`), true);

  assert.equal((migration.match(/^BEGIN;$/gm) ?? []).length, 1);
  assert.equal((migration.match(/^COMMIT;$/gm) ?? []).length, 1);
  assert.match(migration, /profile_row\.is_active IS TRUE/);
  assert.match(migration, /profile_row\.role = 'super_admin'/);
  assert.match(migration, /profile_row\.role = 'adda_admin'/);
  assert.match(migration, /profile_row\.role IN \('adda_admin', 'operator'\)/);
  assert.match(migration, /AS RESTRICTIVE[\s\S]*FOR UPDATE[\s\S]*USING \(bucket_id <> 'adda-logos'\)[\s\S]*WITH CHECK \(bucket_id <> 'adda-logos'\)/);
  assert.match(migration, /profile_row\.adda_id = adda_row\.id/);
  assert.match(migration, /metadata->>'mimetype' = 'image\/png'/);
  assert.match(migration, /metadata->>'mimetype' = 'image\/jpeg'/);
  assert.match(migration, /metadata->>'mimetype' = 'image\/webp'/);
  assert.doesNotMatch(migration, /GRANT\s+UPDATE\s+ON\s+storage\.objects/i);

  console.log("PASS: image validation, canonical owner paths, role/tenant UI guard, replacement/removal ordering, failure safety and legacy URL preservation");
  console.log("PASS: static migration guard assertions for active roles, tenant folder ownership and target-bucket UPDATE denial");
  console.log("UNVERIFIED: Supabase Storage RLS/API behavior and browser file-picker/preview runtime require staging checks");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
