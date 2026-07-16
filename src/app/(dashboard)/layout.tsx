"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-gray-100 flex">
      <aside className="w-72 bg-white border-r border-gray-200 shadow-sm p-6">
        <h1 className="text-3xl font-bold text-blue-600 mb-10">
          UT Software
        </h1>

        <nav className="space-y-3">
          <Link
            href="/dashboard"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/dashboard"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📊 Dashboard
          </Link>

          <Link
            href="/addas"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/addas"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            🏢 Addas
          </Link>

          <Link
            href="/drivers"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/drivers"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            👨 Drivers
          </Link>

          <Link
            href="/vehicles"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/vehicles"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            🚚 Vehicles
          </Link>

          <Link
            href="/reports"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/reports"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📊 Reports
          </Link>

          <Link
            href="/drivers-ledger"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/drivers-ledger"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📒 Driver Ledger
          </Link>

           <Link
  href="/customer-ledger"
  className={`block p-3 rounded-lg font-medium ${
    pathname === "/customer-ledger"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  👥 Customer Ledger
</Link>
 
<Link
  href="/owner-ledger"
  className={`block p-3 rounded-lg font-medium ${
    pathname === "/owner-ledger"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  🏢 Owner Ledger
</Link>

<Link
  href="/vehicle-ledger"
  className={`block p-3 rounded-lg font-medium ${
    pathname === "/vehicle-ledger"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  🚚 Vehicle Ledger
</Link>
 
<Link
  href="/payment-receipts"
  className={`block p-3 rounded-lg font-medium ${
    pathname === "/payment-receipts"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  💵 Payment Receipts
</Link>
 
<Link
  href="/cashbook"
  className={`block p-3 rounded-lg font-medium ${
    pathname === "/cashbook"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  💰 Cashbook
</Link>
 
<Link
  href="/workshop"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/workshop"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  🔧 Workshop
</Link>

         <Link
            href="/bookings"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/bookings"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📦 Bilty
          </Link>

          <Link
            href="/loading"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/loading"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            🚛 Loading
          </Link>

          <Link
            href="/packing"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/packing"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📦 Packing Slip
          </Link>
.
<Link
  href="/diesel"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/diesel"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  ⛽ Diesel
</Link>

<Link
  href="/petrol-pumps"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/petrol-pumps"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  ⛽ Petrol Pumps
</Link>

<Link
  href="/petrol-pump-payments"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/petrol-pump-payments"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  💳 Pump Payments
</Link>

<Link
  href="/brokers"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/brokers"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  🤝 Brokers
</Link>

<Link
  href="/employees"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/employees"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  👨‍💼 Employees
</Link>

<Link
  href="/employee-salary"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/employee-salary"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  💰 Employee Salary
</Link>

<Link
  href="/employee-ledger"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/employee-ledger"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  📒 Employee Ledger
</Link>

<Link
  href="/employee-loans"
  className={`block rounded-lg p-3 font-medium ${
    pathname === "/employee-loans"
      ? "border-2 border-black bg-blue-50 text-blue-600"
      : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
  }`}
>
  💳 Employee Loans
</Link>

          <Link
            href="/expenses"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/expenses"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            💰 Expenses
          </Link>
        </nav>
      </aside>

      <main className="flex-1 p-8">{children}</main>
    </div>
  );
}