"use client";

import type { LoadingDetailsData } from "./LoadingDetails";

type Props = {
  loading: LoadingDetailsData;
};

export default function LoadingHeader({ loading }: Props) {
  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900">
        Loading Details
      </h1>
      <p className="mt-2 text-base font-semibold text-gray-900">
        Loading No: {loading.loadingNo}
      </p>
      <p className="mt-1 text-sm font-medium text-gray-700">
        Date: {loading.loadingDate?.slice(0, 10)}
      </p>
    </div>
  );
}