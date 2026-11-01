import { useState } from "react";
import type { PackingSlipRecord } from "@/types/packing";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type PackingTableProps = {
  packingSlips: PackingSlipRecord[];
  search: string;
  setSearch: (value: string) => void;
  onView: (packingSlip: PackingSlipRecord) => void;
  onEdit: (packingSlip: PackingSlipRecord) => void;
  onDelete: (packingSlip: PackingSlipRecord) => void;
  onPrint: (packingSlip: PackingSlipRecord) => void;
  isDeleting?: boolean;
};

function getUnitLabel(unit: string, t: (key: string) => string): string {
  const unitKey = {
    Kg: "kg",
    Ton: "ton",
    Bag: "bag",
    Piece: "piece",
  }[unit];

  return unitKey ? t(`packing.units.${unitKey}`) : unit;
}

export default function PackingTable({
  packingSlips,
  search,
  setSearch,
  onView,
  onEdit,
  onDelete,
  onPrint,
  isDeleting = false,
}: PackingTableProps) {
  const { t, dir } = useLanguage();
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(packingSlips.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visiblePackingSlips = packingSlips.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">

      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">{t("packing.listTitle")}</h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            {t("packing.tableDescription")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("packing.searchPlaceholder")} mode="text"><input
          type="text"
          placeholder={t("packing.searchPlaceholder")}
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          aria-label={t("packing.searchPlaceholder")}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        /></VoiceTypingField>
      </div>


      <div className="overflow-x-auto rounded-xl border border-gray-300">
        <table className="w-full min-w-[1280px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-start font-bold">{t("packing.slipNo")}</th>
              <th className="p-3 text-start font-bold">{t("packing.date")}</th>
              <th className="p-3 text-start font-bold">{t("common.loadingNo")}</th>
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
            {packingSlips.length === 0 && (
              <tr>
                <td
                  colSpan={12}
                  className="p-8 text-center text-base font-semibold text-gray-900"
                >
                  {t("packing.empty")}
                </td>
              </tr>
            )}

            {visiblePackingSlips.map((packingSlip) => {
              const items = packingSlip.packing_slip_items ?? [];
              const rows =
                items.length > 0
                  ? items
                  : [
                      {
                        id: 0,
                        packing_slip_id: packingSlip.id,
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
                    key={`${packingSlip.id}-${item.id}-${index}`}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    {isFirstRow && (
                      <>
                        <td
                          rowSpan={rowSpan}
                          dir="ltr"
                          className="border-e border-gray-200 p-3 align-top font-bold text-gray-900"
                        >
                          {packingSlip.packing_slip_no}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          dir="ltr"
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.packing_date}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          dir="ltr"
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.loading_no ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          dir="ltr"
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.vehicles?.vehicle_no ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.drivers?.name ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-e border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.route ?? "-"}
                        </td>
                      </>
                    )}

                    <td className="p-3 font-semibold text-gray-900">
                      {item.item_name}
                    </td>
                    <td dir="ltr" className="p-3 text-end font-semibold text-gray-900">
                      {item.quantity || "-"}
                    </td>
                    <td dir="ltr" className="p-3 text-end font-semibold text-gray-900">
                      {item.weight || "-"}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {getUnitLabel(item.unit, t)}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.remarks || packingSlip.remarks || "-"}
                    </td>

                    {isFirstRow && (
                      <td
                        rowSpan={rowSpan}
                        className="min-w-[230px] p-3 align-top"
                      >
                        <div className="flex flex-wrap gap-2">
                          <button
                            type="button"
                            aria-label={`${t("common.actions.view")} ${packingSlip.packing_slip_no}`}
                            onClick={() => onView(packingSlip)}
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            {t("common.actions.view")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("common.actions.edit")} ${packingSlip.packing_slip_no}`}
                            onClick={() => onEdit(packingSlip)}
                            className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                          >
                            {t("common.actions.edit")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("common.actions.delete")} ${packingSlip.packing_slip_no}`}
                            onClick={() => onDelete(packingSlip)}
                            disabled={isDeleting}
                            className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                          >
                            {t("common.actions.delete")}
                          </button>

                          <button
                            type="button"
                            aria-label={`${t("packing.print")} ${packingSlip.packing_slip_no}`}
                            onClick={() => onPrint(packingSlip)}
                            className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                          >
                            {t("packing.print")}
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
      {packingSlips.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900">
          <span className="font-bold">
            {t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}
          </span>
          <div className="flex gap-2">
            <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.previous")}
            </button>
            <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.next")}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
