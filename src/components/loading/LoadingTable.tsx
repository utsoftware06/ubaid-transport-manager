import Link from "next/link";
import { useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import type { LoadingRecord } from "@/types/loading";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type LoadingTableProps = {
  loadings: LoadingRecord[];
  search: string;
  setSearch: (value: string) => void;
  onView: (loading: LoadingRecord) => void;
  onEdit: (loading: LoadingRecord) => void;
  onDelete: (loading: LoadingRecord) => void;
  onPrint: (loading: LoadingRecord) => void;
  isDeleting?: boolean;
  isLoading?: boolean;
};

export default function LoadingTable({
  loadings,
  search,
  setSearch,
  onView,
  onEdit,
  onDelete,
  onPrint,
  isDeleting = false,
  isLoading = false,
}: LoadingTableProps) {
  const { t, dir } = useLanguage();
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(loadings.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleLoadings = loadings.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">

      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">{t("loadings.myLoadings")}</h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            {t("loadings.tableDescription")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("loadings.searchPlaceholder")} mode="text"><input
          type="text"
          aria-label={t("loadings.searchPlaceholder")}
          placeholder={t("loadings.searchPlaceholder")}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        /></VoiceTypingField>
      </div>


      <div className="overflow-x-auto rounded-xl border border-gray-200">
        <table className="w-full min-w-[1240px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-start font-bold">{t("loadings.loadingNo")}</th>
              <th className="p-3 text-start font-bold">{t("common.date")}</th>
              <th className="p-3 text-start font-bold">{t("common.vehicle")}</th>
              <th className="p-3 text-start font-bold">{t("common.driver")}</th>
              <th className="p-3 text-start font-bold">{t("common.route")}</th>
              <th className="p-3 text-start font-bold">{t("common.item")}</th>
              <th className="p-3 text-end font-bold">{t("common.quantity")}</th>
              <th className="p-3 text-end font-bold">{t("common.weight")}</th>
              <th className="p-3 text-start font-bold">{t("common.unit")}</th>
              <th className="p-3 text-start font-bold">{t("common.remarks")}</th>
              <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {isLoading && (
              <tr>
                <td colSpan={11} className="p-8 text-center text-base font-semibold">
                  {t("common.loading")}
                </td>
              </tr>
            )}
            {!isLoading && loadings.length === 0 && (
              <tr>
                <td
                  colSpan={11}
                  className="p-8 text-center text-base font-semibold text-gray-900"
                >
                  {t("loadings.empty")}
                </td>
              </tr>
            )}

            {!isLoading && visibleLoadings.map((loading) => {
              const items = loading.loading_items ?? [];
              const rows =
                items.length > 0
                  ? items
                  : [
                      {
                        id: `empty-${loading.id}`,
                        loading_id: loading.id,
                        item_name: "-",
                        quantity: 0,
                        weight: 0,
                        unit: "-",
                        remarks: "-",
                      },
                    ];

              return rows.map((item, index) => {
                const isFirstRow = index === 0;
                const rowSpan = rows.length;

                return (
                  <tr
                    key={`${loading.id}-${item.id}-${index}`}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    {isFirstRow && (
                      <>
                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-bold text-gray-900"
                          dir="ltr"
                        >
                          {loading.loading_no}
                        </td>

                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                          dir="ltr"
                        >
                          {loading.loading_date}
                        </td>

                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                          dir="ltr"
                        >
                          {loading.vehicles?.vehicle_no ?? "-"}
                        </td>

                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.drivers?.name ?? "-"}
                        </td>

                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.route}
                        </td>
                      </>
                    )}

                    <td className="p-3 font-semibold text-gray-900">
                      {item.item_name}
                    </td>

                    <td className="p-3 text-end font-semibold text-gray-900" dir="ltr">
                      {item.quantity || "-"}
                    </td>

                    <td className="p-3 text-end font-semibold text-gray-900" dir="ltr">
                      {item.weight || "-"}
                    </td>

                    <td className="p-3 font-semibold text-gray-900">
                      {item.unit}
                    </td>

                    <td className="p-3 font-semibold text-gray-900">
                      {item.remarks || "-"}
                    </td>

                    {isFirstRow && (
                      <td
                        rowSpan={rowSpan}
                        className="min-w-[280px] p-3 align-top"
                      >
                        <div className="flex flex-wrap gap-2">
                          <Link
                            href={`/loading-details/${loading.id}`}
                            aria-label={`${t("common.actions.details")} ${loading.loading_no}`}
                            className="rounded-lg bg-purple-600 px-3 py-2 font-semibold text-white transition hover:bg-purple-700"
                          >
                            {t("common.actions.details")}
                          </Link>

                          <button
                            type="button"
                            aria-label={`${t("common.actions.view")} ${loading.loading_no}`}
                            onClick={() => onView(loading)}
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            {t("common.actions.view")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("common.actions.edit")} ${loading.loading_no}`}
                            onClick={() => onEdit(loading)}
                            className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                          >
                            {t("common.actions.edit")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("common.actions.delete")} ${loading.loading_no}`}
                            onClick={() => onDelete(loading)}
                            disabled={isDeleting}
                            className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                          >
                            {t("common.actions.delete")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("loadings.printSlip")} ${loading.loading_no}`}
                            onClick={() => onPrint(loading)}
                            className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                          >
                            {t("loadings.printSlip")}
                          </button>
                        </div>
                      </td>
                    )}
                  </tr>
                );
              });
            })}
          </tbody>
        </table>
      </div>
      {!isLoading && loadings.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <span className="font-semibold">
            {t("common.pagination.page")} {currentPage}{" "}
            {t("common.pagination.of")} {totalPages}
          </span>
          <div className="flex gap-2">
            <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button>
            <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button>
          </div>
        </div>
      )}
    </div>
  );
}
