"use client";

import { useEffect, useState } from "react";
import LegacyReports from "@/components/reports/LegacyReports";
import VehicleOwnerSummary from "@/components/reports/VehicleOwnerSummary";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type AccessState =
  | { status: "loading" }
  | { status: "denied" }
  | { status: "operator" }
  | { status: "admin"; role: "super_admin" | "adda_admin"; addaId: string | null };

export default function ReportsPage() {
  const { t, dir } = useLanguage();
  const [access, setAccess] = useState<AccessState>({ status: "loading" });

  useEffect(() => {
    let active = true;
    async function verifyAccess() {
      try {
        const auth = await supabase.auth.getUser();
        if (auth.error || !auth.data.user) throw new Error("Authentication unavailable.");
        const result = await supabase.from("profiles").select("role,adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
        if (result.error || !result.data || result.data.is_active !== true) throw new Error("An active profile is required.");
        const role = result.data.role;
        if (role === "operator") {
          if (active) setAccess({ status: "operator" });
          return;
        }
        if (role === "super_admin") {
          if (active) setAccess({ status: "admin", role, addaId: null });
          return;
        }
        if (role === "adda_admin" && result.data.adda_id) {
          if (active) setAccess({ status: "admin", role, addaId: result.data.adda_id });
          return;
        }
        throw new Error("This profile is not authorized for the report.");
      } catch (error) {
        console.error("Vehicle & Owner Summary access check failed", error);
        if (active) setAccess({ status: "denied" });
      }
    }
    void verifyAccess();
    return () => { active = false; };
  }, []);

  if (access.status === "operator") return <LegacyReports />;
  if (access.status === "admin") return <VehicleOwnerSummary role={access.role} profileAddaId={access.addaId} />;
  return <main dir={dir} className="ut-module-page mx-auto max-w-3xl rounded-2xl border bg-white p-8 text-center shadow-sm">{access.status === "loading" ? <p role="status" className="font-bold">{t("reports.vehicleOwnerSummary.accessChecking")}</p> : <p role="alert" className="font-bold text-red-800">{t("reports.vehicleOwnerSummary.accessDenied")}</p>}</main>;
}
