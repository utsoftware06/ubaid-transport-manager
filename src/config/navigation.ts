import type { LucideIcon } from "lucide-react";
import {
  BarChart3,
  Banknote,
  BriefcaseBusiness,
  Building2,
  Bus,
  Calculator,
  ClipboardList,
  ClipboardMinus,
  Coins,
  CreditCard,
  Disc3,
  Droplets,
  FileClock,
  FileText,
  Fuel,
  Gauge,
  HandCoins,
  Handshake,
  LayoutDashboard,
  ListChecks,
  NotebookTabs,
  NotebookText,
  PackageOpen,
  Printer,
  ReceiptText,
  ScrollText,
  Settings,
  ShieldCheck,
  Truck,
  UserRound,
  Users,
  UsersRound,
  WalletCards,
  Wrench,
} from "lucide-react";

export const USER_ROLES = {
  superAdmin: "super_admin",
  addaAdmin: "adda_admin",
  operator: "operator",
} as const;

export type UserRole = (typeof USER_ROLES)[keyof typeof USER_ROLES];

export function isUserRole(value: unknown): value is UserRole {
  return Object.values(USER_ROLES).some((role) => role === value);
}

export function userRoleTranslationKey(value: string | null): string | null {
  if (!isUserRole(value)) return null;

  const keys: Record<UserRole, string> = {
    [USER_ROLES.superAdmin]: "roles.superAdmin",
    [USER_ROLES.addaAdmin]: "roles.addaAdmin",
    [USER_ROLES.operator]: "roles.operator",
  };

  return keys[value];
}

export function userRoleLabel(
  value: string | null,
  translate: (key: string) => string
): string {
  const translationKey = userRoleTranslationKey(value);
  return translationKey ? translate(translationKey) : value ?? "-";
}

export type NavigationItem = {
  titleKey: string;
  href: string;
  icon: LucideIcon;
  roles: UserRole[];
  exact?: boolean;
};

export type NavigationGroup = {
  titleKey: string | null;
  items: NavigationItem[];
};

const allRoles: UserRole[] = Object.values(USER_ROLES);
const adminRoles: UserRole[] = [
  USER_ROLES.superAdmin,
  USER_ROLES.addaAdmin,
];
const superAdminOnly: UserRole[] = [USER_ROLES.superAdmin];

const additionalRoutePermissions = [
  { pathPrefix: "/other-adda-account", roles: allRoles },
  // Hidden compatibility routes remain authorized while legacy accounting and
  // document dependencies are retired in a later reviewed migration.
  { pathPrefix: "/bookings", roles: allRoles },
  { pathPrefix: "/loading", roles: allRoles },
  { pathPrefix: "/packing", roles: allRoles },
  {
    pathPrefix: "/loading-details",
    roles: allRoles,
  },
] as const;

export const navigationGroups: NavigationGroup[] = [
  {
    titleKey: null,
    items: [
      {
        titleKey: "sidebar.items.dashboard",
        href: "/dashboard",
        icon: LayoutDashboard,
        roles: allRoles,
        exact: true,
      },
      {
        titleKey: "sidebar.items.cashbook",
        href: "/cashbook",
        icon: Coins,
        roles: allRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.transportOperations",
    items: [
      {
        titleKey: "sidebar.items.tripManagement",
        href: "/trip-management",
        icon: Bus,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.bilty",
        href: "/bilty",
        icon: PackageOpen,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.expenses",
        href: "/expenses",
        icon: HandCoins,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.parchi",
        href: "/parchi",
        icon: ReceiptText,
        roles: allRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.partiesRecords",
    items: [
      {
        titleKey: "sidebar.items.parties",
        href: "/parties",
        icon: Users,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.brokers",
        href: "/brokers",
        icon: BriefcaseBusiness,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.otherAdda",
        href: "/other-addas",
        icon: Handshake,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.vehicles",
        href: "/vehicles",
        icon: Truck,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.drivers",
        href: "/drivers",
        icon: UserRound,
        roles: allRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.accountsLedgers",
    items: [
      {
        titleKey: "sidebar.items.addaAccount",
        href: "/adda-account",
        icon: WalletCards,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.paymentReceipts",
        href: "/payment-receipts",
        icon: ReceiptText,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.partyLedger",
        href: "/party-ledger",
        icon: ScrollText,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.customerLedger",
        href: "/customer-ledger",
        icon: NotebookText,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.ownerLedger",
        href: "/owner-ledger",
        icon: ClipboardList,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.vehicleLedger",
        href: "/vehicle-ledger",
        icon: ListChecks,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.driverLedger",
        href: "/drivers-ledger",
        icon: NotebookTabs,
        roles: adminRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.fuelMaintenance",
    items: [
      {
        titleKey: "sidebar.items.diesel",
        href: "/diesel",
        icon: Fuel,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.petrolPumps",
        href: "/petrol-pumps",
        icon: Gauge,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.pumpPayments",
        href: "/petrol-pump-payments",
        icon: CreditCard,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.oil",
        href: "/oil",
        icon: Droplets,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.tyre",
        href: "/tyre",
        icon: Disc3,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.workshop",
        href: "/workshop",
        icon: Wrench,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.vehicleDocuments",
        href: "/vehicle-documents",
        icon: FileText,
        roles: adminRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.employees",
    items: [
      {
        titleKey: "sidebar.items.employees",
        href: "/employees",
        icon: UsersRound,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.employeeSalary",
        href: "/employee-salary",
        icon: Banknote,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.employeeLoans",
        href: "/employee-loans",
        icon: ClipboardMinus,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.employeeLedger",
        href: "/employee-ledger",
        icon: FileClock,
        roles: adminRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.reports",
    items: [
      {
        titleKey: "sidebar.items.reports",
        href: "/reports",
        icon: BarChart3,
        roles: allRoles,
      },
      {
        titleKey: "sidebar.items.vehicleMonthlyHisab",
        href: "/vehicle-monthly-hisab",
        icon: Calculator,
        roles: adminRoles,
      },
      {
        titleKey: "sidebar.items.ownerGariAccount",
        href: "/owner-gari-account",
        icon: WalletCards,
        roles: adminRoles,
      },
    ],
  },
  {
    titleKey: "sidebar.groups.administrationSettings",
    items: [
      {
        titleKey: "sidebar.items.addas",
        href: "/addas",
        icon: Building2,
        roles: superAdminOnly,
      },
      {
        titleKey: "sidebar.items.users",
        href: "/users",
        icon: UsersRound,
        roles: superAdminOnly,
      },
      {
        titleKey: "sidebar.items.auditLogs",
        href: "/audit-logs",
        icon: ShieldCheck,
        roles: superAdminOnly,
      },
      {
        titleKey: "sidebar.items.settings",
        href: "/settings",
        icon: Settings,
        roles: adminRoles,
        exact: true,
      },
      {
        titleKey: "sidebar.items.printTemplates",
        href: "/settings/print-templates",
        icon: Printer,
        roles: allRoles,
      },
    ],
  },
];

export function isNavigationRouteAllowed(
  pathname: string,
  role: UserRole
): boolean {
  const matchingItem = navigationGroups
    .flatMap((group) => group.items)
    .filter((item) =>
      item.exact
        ? pathname === item.href
        : pathname === item.href || pathname.startsWith(`${item.href}/`)
    )
    .sort((first, second) => second.href.length - first.href.length)[0];

  if (matchingItem) {
    return matchingItem.roles.includes(role);
  }

  const additionalRoute = additionalRoutePermissions.find((route) =>
    pathname === route.pathPrefix || pathname.startsWith(`${route.pathPrefix}/`)
  );

  return additionalRoute ? additionalRoute.roles.includes(role) : false;
}
