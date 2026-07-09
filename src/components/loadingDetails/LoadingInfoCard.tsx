"use client";

import type { LoadingDetailsData } from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";

type Props = {
  loading: LoadingDetailsData;
};

export default function LoadingInfoCard({ loading }: Props) {
  const items = [
    { label: "Vehicle", value: loading.vehicleNo },
    { label: "Owner", value: loading.ownerName },
    { label: "Driver", value: loading.driverName },
    { label: "Customer", value: loading.customerName },
    { label: "Route", value: loading.route },
    { label: "Freight", value: formatAmount(loading.freight) },
  ];

  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-5 text-2xl font-bold text-gray-900">
        Trip Information
      </h2>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {items.map((item) => (
          <div
            key={item.label}
            className="rounded-lg border border-gray-200 bg-white p-4"
          >
            <p className="text-sm font-semibold text-gray-700">
              {item.label}
            </p>
            <p className="mt-2 text-lg font-bold text-gray-900">
              {item.value}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}