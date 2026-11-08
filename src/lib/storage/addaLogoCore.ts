export const ADDA_LOGO_BUCKET = "adda-logos";
export const ADDA_LOGO_MAX_BYTES = 2 * 1024 * 1024;

export function canManageAddaLogo(
  role: string | null,
  isActive: boolean,
  profileAddaId: string | null,
  targetAddaId: string | null,
): boolean {
  if (!isActive || !targetAddaId) return false;
  return role === "super_admin" || (role === "adda_admin" && profileAddaId === targetAddaId);
}

export type AddaLogoExtension = "png" | "jpg" | "jpeg" | "webp";
export type AddaLogoValidationError = "size" | "type" | "content";
export type AddaLogoValidationResult =
  | { valid: true; extension: AddaLogoExtension }
  | { valid: false; reason: AddaLogoValidationError };

const mimeByExtension: Record<AddaLogoExtension, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  webp: "image/webp",
};

export function getAddaLogoExtension(fileName: string): AddaLogoExtension | null {
  const extension = fileName.split(".").pop()?.toLowerCase();
  return extension && Object.prototype.hasOwnProperty.call(mimeByExtension, extension)
    ? (extension as AddaLogoExtension)
    : null;
}

export async function validateAddaLogoFile(
  file: File,
  decodeImage: (value: Blob) => Promise<boolean> = async (value) => {
    if (typeof createImageBitmap === "function") {
      try {
        const bitmap = await createImageBitmap(value);
        const valid = bitmap.width > 0 && bitmap.height > 0;
        bitmap.close();
        return valid;
      } catch {
        return false;
      }
    }
    if (typeof Image === "undefined" || typeof URL.createObjectURL !== "function") return true;
    const objectUrl = URL.createObjectURL(value);
    try {
      const image = new Image();
      image.src = objectUrl;
      await image.decode();
      return image.naturalWidth > 0 && image.naturalHeight > 0;
    } catch {
      return false;
    } finally {
      URL.revokeObjectURL(objectUrl);
    }
  },
): Promise<AddaLogoValidationResult> {
  if (file.size <= 0 || file.size > ADDA_LOGO_MAX_BYTES) {
    return { valid: false, reason: "size" };
  }
  const extension = getAddaLogoExtension(file.name);
  if (!extension || file.type.toLowerCase() !== mimeByExtension[extension]) {
    return { valid: false, reason: "type" };
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const isPng =
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
    bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a;
  const isJpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isWebp = bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  const contentMatches =
    (extension === "png" && isPng) ||
    ((extension === "jpg" || extension === "jpeg") && isJpeg) ||
    (extension === "webp" && isWebp);
  if (!contentMatches || !(await decodeImage(file))) {
    return { valid: false, reason: "content" };
  }
  return { valid: true, extension };
}

export function buildAddaLogoPath(addaId: string, objectId: string, extension: AddaLogoExtension): string {
  return `${addaId}/${objectId}.${extension}`;
}

export function buildAddaLogoReference(path: string): string {
  return `storage://${ADDA_LOGO_BUCKET}/${path}`;
}

export function parseAddaLogoReference(value: string | null | undefined): { addaId: string; path: string } | null {
  const match = value?.match(
    /^storage:\/\/adda-logos\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.(png|jpg|jpeg|webp)$/i,
  );
  if (!match) return null;
  return { addaId: match[1].toLowerCase(), path: `${match[1].toLowerCase()}/${match[2].toLowerCase()}.${match[3].toLowerCase()}` };
}

export type AddaLogoOperations = {
  upload: (path: string, file: File, contentType: string) => Promise<boolean>;
  saveReference: (reference: string | null) => Promise<"saved" | "unchanged" | "unknown">;
  remove: (path: string) => Promise<boolean>;
};

export type ReplaceAddaLogoResult =
  | { status: "invalid"; reason: AddaLogoValidationError }
  | { status: "upload_failed" }
  | { status: "save_failed"; cleanupFailed: boolean }
  | { status: "save_uncertain" }
  | { status: "saved"; reference: string; oldCleanupFailed: boolean };

export async function replaceAddaLogoReference(args: {
  addaId: string;
  currentReference: string | null;
  file: File;
  objectId: string;
  operations: AddaLogoOperations;
}): Promise<ReplaceAddaLogoResult> {
  const validation = await validateAddaLogoFile(args.file);
  if (!validation.valid) return { status: "invalid", reason: validation.reason };
  const path = buildAddaLogoPath(args.addaId, args.objectId, validation.extension);
  try {
    if (!(await args.operations.upload(path, args.file, args.file.type))) return { status: "upload_failed" };
  } catch {
    return { status: "upload_failed" };
  }

  const reference = buildAddaLogoReference(path);
  let saveResult: "saved" | "unchanged" | "unknown" = "unknown";
  try {
    saveResult = await args.operations.saveReference(reference);
  } catch {
    saveResult = "unknown";
  }
  if (saveResult === "unknown") return { status: "save_uncertain" };
  if (saveResult === "unchanged") {
    let cleaned = false;
    try {
      cleaned = await args.operations.remove(path);
    } catch {
      cleaned = false;
    }
    return { status: "save_failed", cleanupFailed: !cleaned };
  }

  const previous = parseAddaLogoReference(args.currentReference);
  let oldCleanupFailed = false;
  if (previous?.addaId === args.addaId) {
    try {
      oldCleanupFailed = !(await args.operations.remove(previous.path));
    } catch {
      oldCleanupFailed = true;
    }
  }
  return { status: "saved", reference, oldCleanupFailed };
}

export type RemoveAddaLogoResult = "save_failed" | "save_uncertain" | "removed" | "removed_cleanup_failed";

export async function clearAddaLogoReference(args: {
  addaId: string;
  currentReference: string | null;
  operations: AddaLogoOperations;
}): Promise<RemoveAddaLogoResult> {
  let saveResult: "saved" | "unchanged" | "unknown" = "unknown";
  try {
    saveResult = await args.operations.saveReference(null);
  } catch {
    saveResult = "unknown";
  }
  if (saveResult === "unknown") return "save_uncertain";
  if (saveResult === "unchanged") return "save_failed";
  const previous = parseAddaLogoReference(args.currentReference);
  if (previous?.addaId === args.addaId) {
    try {
      if (!(await args.operations.remove(previous.path))) return "removed_cleanup_failed";
    } catch {
      return "removed_cleanup_failed";
    }
  }
  return "removed";
}
