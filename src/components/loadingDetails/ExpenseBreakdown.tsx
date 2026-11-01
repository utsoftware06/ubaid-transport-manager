"use client";

import type { LoadingExpenseItem } from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  expenses: LoadingExpenseItem[];
  totalExpense: number;
};

export default function ExpenseBreakdown({ expenses, totalExpense }: Props) {
  const { t, dir } = useLanguage();
  return (
    <section dir={dir} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <div className="mb-5 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-extrabold text-slate-900">
            {t("loadings.details.expenseBreakdown")}
          </h2>
          <p className="mt-1 text-sm font-medium text-slate-600">
            {t("loadings.details.expenseDescription")}
          </p>
        </div>

        <div className="rounded-xl border border-red-100 bg-red-50 px-3 py-2.5">
          <p className="text-sm font-semibold text-red-700">
            {t("loadings.details.totalExpense")}
          </p>
          <p className="text-xl font-bold text-red-700" dir="ltr">
            {formatAmount(totalExpense)}
          </p>
        </div>
      </div>

      {expenses.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">
            {t("loadings.details.noExpenses")}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-slate-200">
          <table className="min-w-full border-collapse text-sm text-slate-800">
            <thead>
              <tr className="bg-slate-50 text-slate-700">
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("loadings.details.expenseName")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("loadings.details.amount")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("common.remarks")}
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-slate-100 bg-white text-slate-800">
              {expenses.map((expense) => (
                <tr
                  key={expense.id}
                  className="bg-white text-slate-800 transition-colors hover:bg-blue-50/40"
                >
                  <td className="px-4 py-2.5 font-semibold text-slate-900">
                    {expense.expenseName}
                  </td>

                  <td className="px-4 py-2.5 font-bold text-slate-900" dir="ltr">
                    {formatAmount(expense.amount)}
                  </td>

                  <td className="px-4 py-2.5 font-semibold text-slate-900">
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
