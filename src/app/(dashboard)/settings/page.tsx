"use client";

import { useEffect, useState } from "react";
import { Building2, Settings } from "lucide-react";
import { useRouter } from "next/navigation";
import SettingsManager from "@/components/settings/SettingsManager";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import { settingsTabs, type SettingsTab } from "@/types/settings";

type ProfileRow = {
  adda_id: string | null;
};

type SettingsPageError = "load-error" | "no-adda" | null;

const settingsTabTranslationKeys: Record<
  SettingsTab,
  {
    label: string;
    description: string;
  }
> = {
  company: {
    label: "settings.companyProfile",
    description: "settings.companyProfileDescription",
  },
  localization: {
    label: "settings.languageRegional",
    description: "settings.languageRegionalDescription",
  },
  numbering: {
    label: "settings.documentNumbering",
    description: "settings.documentNumberingDescription",
  },
  printing: {
    label: "settings.printSettings",
    description: "settings.printSettingsDescription",
  },
};

export default function SettingsPage() {
  const router = useRouter();
  const { t, dir } = useLanguage();

  const [addaId, setAddaId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState<SettingsPageError>(null);

  useEffect(() => {
    let isMounted = true;

    async function loadCurrentAdda() {
      setIsLoading(true);
      setPageError(null);

      try {
        const {
          data: { user },
          error: userError,
        } = await supabase.auth.getUser();

        if (userError || !user) {
          router.replace("/login");
          return;
        }

        const { data: profile, error: profileError } = await supabase
          .from("profiles")
          .select("adda_id")
          .eq("id", user.id)
          .maybeSingle();

        if (!isMounted) return;

        if (profileError) {
          console.error("Unable to load settings profile:", profileError);
          setPageError("load-error");
          setAddaId(null);
          return;
        }

        const currentProfile = profile as ProfileRow | null;

        if (!currentProfile?.adda_id) {
          setPageError("no-adda");
          setAddaId(null);
          return;
        }

        setAddaId(currentProfile.adda_id);
      } catch (error) {
        console.error("Unable to load current settings context:", error);
        if (!isMounted) return;
        setPageError("load-error");
        setAddaId(null);
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    void loadCurrentAdda();

    return () => {
      isMounted = false;
    };
  }, [router]);

  return (
    <div dir={dir} className="ut-module-page p-0">
      <div className="mx-auto max-w-7xl space-y-8">
        <header className="rounded-2xl border border-gray-200 bg-white p-6 shadow-md">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
            <div className="flex items-start gap-4">
              <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-blue-100 text-blue-700">
                <Settings className="h-8 w-8" aria-hidden="true" />
              </div>

              <div>
                <h1 className="text-3xl font-extrabold text-gray-900">
                  {t("settings.title")}
                </h1>
                <p className="mt-2 max-w-3xl text-base font-semibold text-gray-900">
                  {t("settings.description")}
                </p>
              </div>
            </div>

            <div className="inline-flex w-fit items-center gap-2 rounded-full border border-blue-200 bg-blue-50 px-4 py-2 text-sm font-extrabold text-blue-700">
              <Building2 className="h-4 w-4" aria-hidden="true" />
              {t("settings.enterpriseEdition")}
            </div>
          </div>
        </header>

        <section className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
          {settingsTabs.map((tab) => {
            const translationKeys = settingsTabTranslationKeys[tab.id];

            return (
              <article
                key={tab.id}
                className="flex min-h-56 flex-col rounded-2xl border border-gray-200 bg-white p-6 shadow-md transition hover:-translate-y-1 hover:border-blue-200 hover:shadow-lg"
              >
                <div>
                  <h2 className="text-xl font-extrabold text-gray-900">
                    {translationKeys ? t(translationKeys.label) : tab.label}
                  </h2>
                  <p className="mt-3 text-sm font-semibold leading-6 text-gray-900">
                    {translationKeys
                      ? t(translationKeys.description)
                      : tab.description}
                  </p>
                </div>

                <div className="mt-auto pt-6">
                  <a
                    href={`#${tab.id}`}
                    className="block w-full rounded-xl bg-blue-600 px-5 py-3 text-center text-sm font-extrabold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
                  >
                    {t("settings.openSettings")}
                  </a>
                </div>
              </article>
            );
          })}
        </section>

        {isLoading ? (
          <div className="rounded-2xl border border-gray-200 bg-white p-8 text-center shadow-md">
            <p className="text-base font-extrabold text-gray-900">
              {t("settings.loading")}
            </p>
          </div>
        ) : pageError || !addaId ? (
          <div className="rounded-2xl border border-red-200 bg-red-50 p-6 shadow-md">
            <h2 className="text-xl font-extrabold text-red-700">
              {pageError === "load-error"
                ? t("settings.loadErrorTitle")
                : t("settings.unavailableTitle")}
            </h2>
            <p className="mt-2 text-sm font-bold text-red-700">
              {pageError === "load-error"
                ? t("settings.loadError")
                : t("settings.unavailableDescription")}
            </p>
          </div>
        ) : (
          <SettingsManager addaId={addaId} />
        )}
      </div>
    </div>
  );
}
