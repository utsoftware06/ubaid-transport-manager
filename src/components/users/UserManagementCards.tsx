"use client";

import { ShieldCheck, UserCheck, UserCog, UserRound, Users, UserX } from "lucide-react";

import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import type { ManagedUser } from "@/components/users/types";

type UserManagementCardsProps = {
  users: ManagedUser[];
};

export default function UserManagementCards({
  users,
}: UserManagementCardsProps) {
  const { t } = useLanguage();
  const cards = [
    {
      key: "total",
      label: t("userManagement.cards.total"),
      value: users.length,
      icon: Users,
    },
    {
      key: "superAdmins",
      label: t("userManagement.cards.superAdmins"),
      value: users.filter((user) => user.role === USER_ROLES.superAdmin).length,
      icon: ShieldCheck,
    },
    {
      key: "addaAdmins",
      label: t("userManagement.cards.addaAdmins"),
      value: users.filter((user) => user.role === USER_ROLES.addaAdmin).length,
      icon: UserCog,
    },
    {
      key: "operators",
      label: t("userManagement.cards.operators"),
      value: users.filter((user) => user.role === USER_ROLES.operator).length,
      icon: UserRound,
    },
    {
      key: "active",
      label: t("userManagement.cards.active"),
      value: users.filter((user) => user.isActive).length,
      icon: UserCheck,
    },
    {
      key: "inactive",
      label: t("userManagement.cards.inactive"),
      value: users.filter((user) => !user.isActive).length,
      icon: UserX,
    },
  ];

  return (
    <section
      aria-label={t("userManagement.cards.summaryLabel")}
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6"
    >
      {cards.map(({ key, label, value, icon: Icon }) => (
        <article
          key={key}
          className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
        >
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-bold text-slate-700">{label}</p>
              <p dir="ltr" className="mt-2 text-3xl font-extrabold text-slate-900">
                {value}
              </p>
            </div>
            <span className="rounded-xl bg-blue-50 p-3 text-blue-700">
              <Icon className="h-6 w-6" aria-hidden="true" />
            </span>
          </div>
        </article>
      ))}
    </section>
  );
}
