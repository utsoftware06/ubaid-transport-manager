"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { ImagePlus, LoaderCircle, Trash2 } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import {
  ADDA_LOGO_BUCKET,
  clearAddaLogoReference,
  replaceAddaLogoReference,
  resolveAddaLogoDisplayUrl,
} from "@/lib/storage/addaLogo";

type CompanyLogoUploadProps = {
  addaId: string;
  logoReference: string;
  settingsExists: boolean;
  canManage: boolean;
  onSaved: (reference: string) => void;
  onBusyChange: (busy: boolean) => void;
};

async function saveLogoReference(
  addaId: string,
  nextReference: string | null,
  previousReference: string | null,
): Promise<"saved" | "unchanged" | "unknown"> {
  const { data, error } = await supabase
    .from("company_settings")
    .update({ logo_url: nextReference })
    .eq("adda_id", addaId)
    .select("adda_id")
    .maybeSingle();
  if (!error && data?.adda_id === addaId) return "saved";

  const { data: observed, error: readError } = await supabase
    .from("company_settings")
    .select("logo_url")
    .eq("adda_id", addaId)
    .maybeSingle();
  if (readError || !observed) return "unknown";
  if (observed.logo_url === nextReference) return "saved";
  if (observed.logo_url === previousReference) return "unchanged";
  return "unknown";
}

export default function CompanyLogoUpload({
  addaId,
  logoReference,
  settingsExists,
  canManage,
  onSaved,
  onBusyChange,
}: CompanyLogoUploadProps) {
  const { t, dir } = useLanguage();
  const inputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [selectedPreview, setSelectedPreview] = useState<string | null>(null);
  const selectedPreviewRef = useRef<string | null>(null);
  const [savedPreview, setSavedPreview] = useState<{ reference: string; url: string | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let active = true;
    void resolveAddaLogoDisplayUrl(addaId, logoReference).then((url) => {
      if (active) setSavedPreview({ reference: logoReference, url });
    });
    return () => {
      active = false;
    };
  }, [addaId, logoReference]);

  useEffect(() => {
    return () => {
      if (selectedPreviewRef.current) URL.revokeObjectURL(selectedPreviewRef.current);
    };
  }, []);

  function setBusyState(value: boolean) {
    setBusy(value);
    onBusyChange(value);
  }

  function clearSelection() {
    if (selectedPreviewRef.current) URL.revokeObjectURL(selectedPreviewRef.current);
    selectedPreviewRef.current = null;
    setSelectedPreview(null);
    setSelectedFile(null);
    if (inputRef.current) inputRef.current.value = "";
  }

  async function uploadSelectedLogo() {
    if (!selectedFile || !canManage || !settingsExists || busy) return;
    setError("");
    setNotice("");
    setBusyState(true);
    try {
      const result = await replaceAddaLogoReference({
        addaId,
        currentReference: logoReference || null,
        file: selectedFile,
        objectId: crypto.randomUUID(),
        operations: {
          upload: async (path, file, contentType) => {
            const { error: uploadError } = await supabase.storage
              .from(ADDA_LOGO_BUCKET)
              .upload(path, file, { contentType, cacheControl: "3600", upsert: false });
            return !uploadError;
          },
          saveReference: (reference) => saveLogoReference(addaId, reference, logoReference || null),
          remove: async (path) => {
            const { error: removeError } = await supabase.storage
              .from(ADDA_LOGO_BUCKET)
              .remove([path]);
            return !removeError;
          },
        },
      });

      if (result.status === "invalid") {
        setError(t(`companyProfile.logoErrors.${result.reason}`));
        return;
      }
      if (result.status === "upload_failed") {
        setError(t("companyProfile.logoUploadFailed"));
        return;
      }
      if (result.status === "save_failed") {
        setError(t(result.cleanupFailed ? "companyProfile.logoCleanupFailed" : "companyProfile.logoSaveFailed"));
        return;
      }
      if (result.status === "save_uncertain") {
        setError(t("companyProfile.logoSaveUnconfirmed"));
        return;
      }

      onSaved(result.reference);
      clearSelection();
      if (result.oldCleanupFailed) setNotice(t("companyProfile.logoOldFileCleanupFailed"));
    } catch (caught) {
      setError(t("companyProfile.logoUploadFailed"));
      console.error("Adda logo upload failed", caught);
    } finally {
      setBusyState(false);
    }
  }

  async function removeSavedLogo() {
    if (!logoReference || !canManage || busy) return;
    setError("");
    setNotice("");
    setBusyState(true);
    try {
      const result = await clearAddaLogoReference({
        addaId,
        currentReference: logoReference || null,
        operations: {
          upload: async () => false,
          saveReference: (reference) => saveLogoReference(addaId, reference, logoReference || null),
          remove: async (path) => {
            const { error: removeError } = await supabase.storage
              .from(ADDA_LOGO_BUCKET)
              .remove([path]);
            return !removeError;
          },
        },
      });
      if (result === "save_failed") {
        setError(t("companyProfile.logoSaveFailed"));
        return;
      }
      if (result === "save_uncertain") {
        setError(t("companyProfile.logoSaveUnconfirmed"));
        return;
      }
      onSaved("");
      clearSelection();
      if (result === "removed_cleanup_failed") setNotice(t("companyProfile.logoOldFileCleanupFailed"));
    } catch (caught) {
      console.error("Adda logo removal failed", caught);
      setError(t("companyProfile.logoSaveFailed"));
    } finally {
      setBusyState(false);
    }
  }

  const displayedPreview = selectedPreview ?? (savedPreview?.reference === logoReference ? savedPreview.url : null);

  return (
    <section className="block lg:col-span-2" dir={dir} aria-labelledby="company-logo-heading">
      <h3 id="company-logo-heading" className="text-sm font-extrabold text-gray-900">
        {t("companyProfile.logo")}
      </h3>
      <p className="mt-1 text-xs font-semibold text-gray-600">
        {t("companyProfile.logoDescription")}
      </p>

      <div className="mt-3 flex flex-col gap-4 rounded-xl border border-gray-200 bg-gray-50 p-4 sm:flex-row sm:items-center">
        <div className="flex h-24 w-36 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-white p-2">
          {displayedPreview ? (
            <Image
              src={displayedPreview}
              alt={t("companyProfile.logoPreviewAlt")}
              width={144}
              height={96}
              unoptimized
              className="h-full w-full object-contain"
              onError={() => {
                if (selectedPreviewRef.current) URL.revokeObjectURL(selectedPreviewRef.current);
                selectedPreviewRef.current = null;
                setSelectedPreview(null);
                setSavedPreview((current) => current ? { ...current, url: null } : null);
              }}
            />
          ) : (
            <span className="text-xs font-bold text-gray-500">{t("companyProfile.noLogo")}</span>
          )}
        </div>

        <div className="min-w-0 flex-1 space-y-3">
          {canManage ? (
            <>
              <input
                ref={inputRef}
                type="file"
                accept="image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp"
                className="sr-only"
                aria-label={t("companyProfile.chooseLogo")}
                disabled={busy || !settingsExists}
                onChange={(event) => {
                  setError("");
                  setNotice("");
                  if (selectedPreviewRef.current) URL.revokeObjectURL(selectedPreviewRef.current);
                  const file = event.target.files?.[0] ?? null;
                  const previewUrl = file ? URL.createObjectURL(file) : null;
                  selectedPreviewRef.current = previewUrl;
                  setSelectedPreview(previewUrl);
                  setSelectedFile(file);
                }}
              />
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  disabled={busy || !settingsExists}
                  onClick={() => inputRef.current?.click()}
                  className="inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
                >
                  <ImagePlus className="h-4 w-4" aria-hidden="true" />
                  {t(logoReference && !selectedFile ? "companyProfile.replaceLogo" : "companyProfile.chooseLogo")}
                </button>
                {selectedFile && (
                  <>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void uploadSelectedLogo()}
                      className="inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-emerald-700 px-4 py-2 text-sm font-bold text-white hover:bg-emerald-800 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600 focus-visible:ring-offset-2"
                    >
                      {busy ? <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" /> : null}
                      {busy ? t("companyProfile.logoUploading") : t(logoReference ? "companyProfile.replaceLogo" : "companyProfile.uploadLogo")}
                    </button>
                    <button type="button" disabled={busy} onClick={clearSelection} className="min-h-10 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-bold text-gray-800 disabled:opacity-50">
                      {t("common.actions.cancel")}
                    </button>
                  </>
                )}
                {logoReference && !selectedFile && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void removeSavedLogo()}
                    className="inline-flex min-h-10 items-center justify-center gap-2 rounded-lg border border-red-300 bg-white px-4 py-2 text-sm font-bold text-red-700 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2"
                  >
                    {busy ? <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Trash2 className="h-4 w-4" aria-hidden="true" />}
                    {t("companyProfile.removeLogo")}
                  </button>
                )}
              </div>
              {!settingsExists && <p className="text-xs font-semibold text-amber-800">{t("companyProfile.logoSaveDetailsFirst")}</p>}
            </>
          ) : (
            <p className="text-sm font-semibold text-gray-600">{t("companyProfile.logoAdminOnly")}</p>
          )}
          {error && <p role="alert" className="text-sm font-bold text-red-700">{error}</p>}
          {notice && <p role="status" className="text-sm font-bold text-amber-800">{notice}</p>}
          {busy && <p role="status" aria-live="polite" className="text-sm font-bold text-blue-800">{t("companyProfile.logoUploading")}</p>}
        </div>
      </div>
    </section>
  );
}
