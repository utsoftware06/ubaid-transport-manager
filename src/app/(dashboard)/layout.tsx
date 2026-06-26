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
      {/* Sidebar */}
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
            href="/dashboard"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/dashboard"
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
            href="/bookings"
            className={`block p-3 rounded-lg font-medium ${
              pathname === "/bookings"
                ? "border-2 border-black bg-blue-50 text-blue-600"
                : "text-gray-800 hover:bg-blue-50 hover:text-blue-600"
            }`}
          >
            📦 Bookings
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

      {/* Page Content */}
      <main className="flex-1 p-8">
        {children}
      </main>
    </div>
  );
}