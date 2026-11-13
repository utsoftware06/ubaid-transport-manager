"use client";

import { useEffect, useState } from "react";
import ReportCards from "@/components/reports/ReportCards";
import ReportFilters, {
  type ReportFilterValues,
} from "@/components/reports/ReportFilters";
import ReportTable from "@/components/reports/ReportTable";
import VehicleWiseReport from "@/components/reports/VehicleWiseReport";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

type VehicleOption = {
  id: string;
  vehicle_no: string;
};

type DriverOption = {
  id: string;
  name: string;
};

const emptyFilters: ReportFilterValues = {
  fromDate: "",
  toDate: "",
  vehicle: "",
  driver: "",
  route: "",
};

export default function LegacyReports() {
  const { t, dir } = useLanguage();
  const [filterValues, setFilterValues] =
    useState<ReportFilterValues>(emptyFilters);
  const [appliedFilters, setAppliedFilters] =
    useState<ReportFilterValues>(emptyFilters);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [drivers, setDrivers] = useState<DriverOption[]>([]);

  useEffect(() => {
    let isMounted = true;

    async function loadFilterOptions() {
      const [vehiclesResult, driversResult] = await Promise.all([
        supabase.from("vehicles").select("id, vehicle_no").order("vehicle_no"),
        supabase.from("drivers").select("id, name").order("name"),
      ]);

      if (!isMounted) return;

      if (vehiclesResult.error) {
        console.error(
          "Unable to load vehicle filters:",
          vehiclesResult.error.message
        );
      } else {
        setVehicles((vehiclesResult.data ?? []) as VehicleOption[]);
      }

      if (driversResult.error) {
        console.error(
          "Unable to load driver filters:",
          driversResult.error.message
        );
      } else {
        setDrivers((driversResult.data ?? []) as DriverOption[]);
      }
    }

    void loadFilterOptions();

    return () => {
      isMounted = false;
    };
  }, []);

  function handleFilterChange(field: keyof ReportFilterValues, value: string) {
    setFilterValues((current) => ({
      ...current,
      [field]: value,
    }));
  }

  function handleSearch() {
    if (
      filterValues.fromDate &&
      filterValues.toDate &&
      filterValues.fromDate > filterValues.toDate
    ) {
      window.alert(t("reports.validation.invalidDateRange"));
      return;
    }

    setAppliedFilters({
      ...filterValues,
      route: filterValues.route.trim(),
    });
  }

  function handleReset() {
    setFilterValues(emptyFilters);
    setAppliedFilters(emptyFilters);
  }

  return (
    <div dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="reports" accent="purple" title={t("reports.title")} description={t("reports.description")} />
      </header>

      <ReportCards filters={appliedFilters} />

      <ReportFilters
        filters={filterValues}
        vehicles={vehicles}
        drivers={drivers}
        onChange={handleFilterChange}
        onSearch={handleSearch}
        onReset={handleReset}
      />

      <VehicleWiseReport />

      <ReportTable
        key={`${appliedFilters.fromDate}|${appliedFilters.toDate}|${appliedFilters.vehicle}|${appliedFilters.driver}|${appliedFilters.route}`}
        filters={appliedFilters}
      />
    </div>
  );
}
