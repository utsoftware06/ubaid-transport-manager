import {
  Banknote,
  BarChart3,
  Building2,
  ClipboardList,
  Disc3,
  Droplets,
  FileClock,
  Fuel,
  HandCoins,
  Handshake,
  NotebookTabs,
  PackageOpen,
  ReceiptText,
  Settings,
  ShieldCheck,
  Truck,
  UserCog,
  UserRound,
  Users,
  WalletCards,
  Wrench,
  type LucideIcon,
} from "lucide-react";
import type { ReactNode } from "react";

const icons = {
  addas: Building2,
  audit: ShieldCheck,
  broker: Handshake,
  cashbook: WalletCards,
  diesel: Fuel,
  driver: UserRound,
  employee: UserCog,
  employeeLedger: FileClock,
  ledger: NotebookTabs,
  oil: Droplets,
  otherAdda: Handshake,
  package: PackageOpen,
  parties: Users,
  payment: Banknote,
  receipt: ReceiptText,
  reports: BarChart3,
  settings: Settings,
  trip: ClipboardList,
  tyre: Disc3,
  vehicle: Truck,
  workshop: Wrench,
  expenses: HandCoins,
  users: Users,
} satisfies Record<string, LucideIcon>;

const accents = {
  blue: "bg-gradient-to-br from-blue-500 to-blue-700 shadow-blue-900/15",
  cyan: "bg-gradient-to-br from-cyan-500 to-teal-600 shadow-teal-900/15",
  green: "bg-gradient-to-br from-emerald-500 to-green-700 shadow-green-900/15",
  orange: "bg-gradient-to-br from-orange-400 to-orange-600 shadow-orange-900/15",
  purple: "bg-gradient-to-br from-violet-500 to-purple-700 shadow-purple-900/15",
  red: "bg-gradient-to-br from-rose-500 to-red-700 shadow-red-900/15",
  coral: "bg-gradient-to-br from-rose-400 to-orange-600 shadow-rose-900/15",
  slate: "bg-gradient-to-br from-slate-500 to-slate-700 shadow-slate-900/15",
  gold: "bg-gradient-to-br from-amber-400 to-yellow-600 shadow-yellow-900/15",
} as const;

type Props = {
  icon: keyof typeof icons;
  title: ReactNode;
  description?: ReactNode;
  accent?: keyof typeof accents;
};

export default function ModulePageHeading({
  icon,
  title,
  description,
  accent = "blue",
}: Props) {
  const Icon = icons[icon];

  return (
    <div className="flex min-w-0 items-center gap-3.5">
      <span
        aria-hidden="true"
        className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-white shadow-md ${accents[accent]}`}
      >
        <Icon className="h-6 w-6" strokeWidth={2.2} />
      </span>
      <div className="min-w-0">
        <h1 className="ut-page-heading-title text-xl font-extrabold tracking-tight text-slate-900 sm:text-2xl">
          {title}
        </h1>
        {description && (
          <p className="mt-1 max-w-3xl text-sm font-medium leading-5 text-slate-600">
            {description}
          </p>
        )}
      </div>
    </div>
  );
}
