"use client";

import type { LoadingDetailsData } from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  loading: LoadingDetailsData;
};

export default function LoadingInfoCard({ loading }: Props) {
  const { t, dir } = useLanguage();
  const items = [
    { label: t("common.vehicle"), value: loading.vehicleNo, technical: true },
    { label: t("vehicles.owner"), value: loading.ownerName },
    { label: t("common.driver"), value: loading.driverName },
    { label: t("common.party"), value: loading.partyName },
    { label: t("common.route"), value: loading.route },
    {
      label: t("common.freight"),
      value: formatAmount(loading.freight),
      technical: true,
    },
  ];

  return (
    <section dir={dir} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <h2 className="mb-4 text-lg font-extrabold text-slate-900">
        {t("loadings.details.tripInformation")}
      </h2>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {items.map((item) => (
          <div
            key={item.label}
            className="rounded-xl border border-slate-200 bg-slate-50/70 p-4"
          >
            <p className="text-sm font-semibold text-slate-600">
              {item.label}
            </p>
            <p
              className="mt-1.5 text-base font-bold text-slate-900"
              dir={item.technical ? "ltr" : undefined}
            >
              {item.value}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
