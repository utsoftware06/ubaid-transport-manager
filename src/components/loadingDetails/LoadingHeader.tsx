"use client";

import type { LoadingDetailsData } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

type Props = {
  loading: LoadingDetailsData;
};

export default function LoadingHeader({ loading }: Props) {
  const { t, dir } = useLanguage();
  return (
    <div dir={dir} className="min-w-0">
      <ModulePageHeading icon="trip" accent="blue" title={t("loadings.details.title")} />
      <p className="mt-3 text-sm font-semibold text-slate-800">
        {t("loadings.loadingNo")}: <span dir="ltr">{loading.loadingNo}</span>
      </p>
      <p className="mt-1 text-sm font-medium text-slate-600">
        {t("common.date")}:{" "}
        <span dir="ltr">{loading.loadingDate?.slice(0, 10)}</span>
      </p>
    </div>
  );
}
