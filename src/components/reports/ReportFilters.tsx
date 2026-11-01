import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

function formatInputDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export type ReportFilterValues = {
  fromDate: string;
  toDate: string;
  vehicle: string;
  driver: string;
  route: string;
};

type VehicleOption = {
  id: string;
  vehicle_no: string;
};

type DriverOption = {
  id: string;
  name: string;
};

type ReportFiltersProps = {
  filters: ReportFilterValues;
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  onChange: (field: keyof ReportFilterValues, value: string) => void;
  onSearch: () => void;
  onReset: () => void;
};

export default function ReportFilters({
  filters,
  vehicles,
  drivers,
  onChange,
  onSearch,
  onReset,
}: ReportFiltersProps) {
  const { t, dir } = useLanguage();
  function applyQuickDateFilter(value: string) {
    if (value === "all") {
      onChange("fromDate", "");
      onChange("toDate", "");
      return;
    }
    const today = new Date();
    const toDate = formatInputDate(today);
    const fromDate = new Date(today);
    if (value === "last7Days") fromDate.setDate(today.getDate() - 6);
    if (value === "thisMonth") fromDate.setDate(1);
    if (value === "last6Months") fromDate.setMonth(today.getMonth() - 6);
    if (value === "thisYear") {
      fromDate.setMonth(0);
      fromDate.setDate(1);
    }
    onChange("fromDate", formatInputDate(fromDate));
    onChange("toDate", toDate);
  }
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">
        {t("reports.filters.title")}
      </h2>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label
            htmlFor="report-quick-date"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("reports.print.period")}
          </label>
          <select
            id="report-quick-date"
            value=""
            onChange={(event) => applyQuickDateFilter(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("reports.print.period")}</option>
            <option value="all">{t("common.dateFilters.allTime")}</option>
            <option value="today">{t("common.dateFilters.today")}</option>
            <option value="last7Days">{t("common.dateFilters.last7Days")}</option>
            <option value="thisMonth">{t("common.dateFilters.thisMonth")}</option>
            <option value="last6Months">{t("common.dateFilters.last6Months")}</option>
            <option value="thisYear">{t("common.dateFilters.thisYear")}</option>
          </select>
        </div>

        <div>
          <label
            htmlFor="report-from-date"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("common.fromDate")}
          </label>
          <VoiceTypingField fieldLabel="report from date" mode="date"><input
            id="report-from-date"
            type="date"
            dir="ltr"
            value={filters.fromDate}
            onChange={(event) => onChange("fromDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label
            htmlFor="report-to-date"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("common.toDate")}
          </label>
          <VoiceTypingField fieldLabel="report to date" mode="date"><input
            id="report-to-date"
            type="date"
            dir="ltr"
            value={filters.toDate}
            onChange={(event) => onChange("toDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label
            htmlFor="report-vehicle"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("common.vehicle")}
          </label>
          <select
            id="report-vehicle"
            value={filters.vehicle}
            onChange={(event) => onChange("vehicle", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("reports.filters.allVehicles")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicle_no}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="report-driver"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("common.driver")}
          </label>
          <select
            id="report-driver"
            value={filters.driver}
            onChange={(event) => onChange("driver", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("reports.filters.allDrivers")}</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>


        <div className="md:col-span-2 xl:col-span-2">
          <label
            htmlFor="report-route"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            {t("common.route")}
          </label>
          <VoiceTypingField fieldLabel={t("reports.filters.routePlaceholder")} mode="text"><input
            id="report-route"
            type="text"
            value={filters.route}
            onChange={(event) => onChange("route", event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                onSearch();
              }
            }}
            placeholder={t("reports.filters.routePlaceholder")}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="flex items-end">
          <button
            type="button"
            onClick={onSearch}
            className="w-full rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white transition hover:bg-blue-700"
          >
            {t("common.actions.search")}
          </button>
        </div>

        <div className="flex items-end">
          <button
            type="button"
            onClick={onReset}
            className="w-full rounded-lg bg-gray-600 px-6 py-3 font-semibold text-white transition hover:bg-gray-700"
          >
            {t("common.actions.reset")}
          </button>
        </div>
      </div>
    </div>
  );
}
