"use client";

import type { LoadingExpenseItem } from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";

type Props = {
  expenses: LoadingExpenseItem[];
  totalExpense: number;
};

export default function ExpenseBreakdown({ expenses, totalExpense }: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Expense Breakdown
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-700">
            Is loading ke tamam expenses ki detail.
          </p>
        </div>

        <div className="rounded-lg bg-red-50 px-4 py-3">
          <p className="text-sm font-semibold text-red-700">
            Total Expense
          </p>
          <p className="text-xl font-bold text-red-700">
            {formatAmount(totalExpense)}
          </p>
        </div>
      </div>

      {expenses.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">
            No expense record found.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full border-collapse text-sm text-gray-900">
            <thead>
              <tr className="bg-gray-100 text-gray-900">
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Expense Name
                </th>
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Amount
                </th>
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Remarks
                </th>
              </tr>
            </thead>

            <tbody className="bg-white text-gray-900">
              {expenses.map((expense) => (
                <tr
                  key={expense.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {expense.expenseName}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-bold text-gray-900">
                    {formatAmount(expense.amount)}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {expense.remarks}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}