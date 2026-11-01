"use client";

import type {
  LoadingDetailsData,
  LoadingExpenseItem,
} from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

type Props = {
  loading: LoadingDetailsData;
  expenses: LoadingExpenseItem[];
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

export default function LoadingPrint({
  loading,
  expenses,
  totalIncome,
  totalExpense,
  netProfit,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("loading", loading.addaId, language === "ur" ? "ur" : "en");
  function handlePrintLegacy() {
    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input);
    const itemsRows = loading.items
      .map(
        (item) => `
          <tr>
            <td>${value(item.itemName)}</td>
            <td class="technical">${value(item.quantity || "-")}</td>
            <td class="technical">${value(item.weight || "-")}</td>
            <td>${value(item.unit)}</td>
            <td>${value(item.remarks)}</td>
          </tr>
        `
      )
      .join("");

    const expenseRows = expenses
      .map(
        (expense) => `
          <tr>
            <td>${value(expense.expenseName)}</td>
            <td class="technical">${value(formatAmount(expense.amount))}</td>
            <td>${value(expense.remarks)}</td>
          </tr>
        `
      )
      .join("");

    const printWindow = window.open("", "_blank", "width=1000,height=800");
    if (!printWindow) {
      alert(t("loadings.messages.allowPopups"));
      return;
    }

    const htmlLanguage = value(language);
    const htmlDirection = value(dir);

    void writeAddaBrandedPrintDocument(printWindow, `
      <!DOCTYPE html>
      <html lang="${htmlLanguage}" dir="${htmlDirection}">
        <head>
          <title>${label("loadings.details.title")}</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 30px; color: #111827; direction: ${htmlDirection}; text-align: start; }
            h1, h2 { text-align: center; margin: 0; }
            h2 { margin-top: 8px; margin-bottom: 20px; }
            h3 { margin-top: 25px; margin-bottom: 10px; color: #111827; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 20px; }
            .box { border: 1px solid #d1d5db; padding: 12px; border-radius: 8px; }
            .box p { margin: 0; font-size: 12px; font-weight: 700; color: #374151; }
            .box h4 { margin: 6px 0 0; font-size: 16px; color: #111827; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 10px; }
            th, td { border: 1px solid #d1d5db; padding: 9px; text-align: start; font-weight: 600; color: #111827; }
            th { background: #2563eb; color: white; }
            .summary { margin-top: 22px; }
            .technical { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>

        <body>
          <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
          <h2>${label("loadings.details.title")}</h2>

          <div class="grid">
            <div class="box"><p>${label("common.loadingNo")}</p><h4 class="technical">${value(loading.loadingNo)}</h4></div>
            <div class="box"><p>${label("common.date")}</p><h4 class="technical">${value(loading.loadingDate)}</h4></div>
            <div class="box"><p>${label("common.route")}</p><h4>${value(loading.route)}</h4></div>
            <div class="box"><p>${label("common.vehicle")}</p><h4 class="technical">${value(loading.vehicleNo)}</h4></div>
            <div class="box"><p>${label("common.owner")}</p><h4>${value(loading.ownerName)}</h4></div>
            <div class="box"><p>${label("common.driver")}</p><h4>${value(loading.driverName)}</h4></div>
            <div class="box"><p>${label("common.party")}</p><h4>${value(loading.partyName)}</h4></div>
            <div class="box"><p>${label("common.freight")}</p><h4 class="technical">${value(formatAmount(loading.freight))}</h4></div>
            <div class="box"><p>${label("common.profit")}</p><h4 class="technical">${value(formatAmount(netProfit))}</h4></div>
          </div>

          <h3>${label("loadings.details.itemsTitle")}</h3>
          <table>
            <thead>
              <tr>
                <th>${label("common.item")}</th>
                <th>${label("common.quantity")}</th>
                <th>${label("common.weight")}</th>
                <th>${label("common.unit")}</th>
                <th>${label("common.remarks")}</th>
              </tr>
            </thead>
            <tbody>
              ${
                itemsRows ||
                `<tr><td colspan="5">${label("loadings.details.noItems")}</td></tr>`
              }
            </tbody>
          </table>

          <h3>${label("loadings.details.expenseBreakdown")}</h3>
          <table>
            <thead>
              <tr>
                <th>${label("loadings.details.expenseName")}</th>
                <th>${label("common.amount")}</th>
                <th>${label("common.remarks")}</th>
              </tr>
            </thead>
            <tbody>
              ${
                expenseRows ||
                `<tr><td colspan="3">${label("loadings.details.noExpenses")}</td></tr>`
              }
            </tbody>
          </table>

          <div class="summary">
            <table>
              <thead>
                <tr>
                  <th>${label("loadings.details.totalIncome")}</th>
                  <th>${label("loadings.details.totalExpense")}</th>
                  <th>${label("reports.summary.netProfit")}</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td class="technical">${value(formatAmount(totalIncome))}</td>
                  <td class="technical">${value(formatAmount(totalExpense))}</td>
                  <td class="technical">${value(formatAmount(netProfit))}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <script>
            window.onload = function () {
              window.print();
              window.onafterprint = function () {
                window.close();
              };
            };
          </script>
        </body>
      </html>
    `, loading.addaId, language === "ur" ? "ur" : "en");
  }

  function handlePrint() {
    const presentation: ModulePrintPresentation = {
      documentType: "loading",
      title: printLabel("loadings.details.title"),
      documentNo: printValue(loading.loadingNo),
      documentDate: printValue(loading.loadingDate),
      fields: [
        { label: printLabel("common.route"), value: printValue(loading.route) },
        { label: printLabel("common.vehicle"), value: printValue(loading.vehicleNo) },
        { label: printLabel("common.owner"), value: printValue(loading.ownerName) },
        { label: printLabel("common.driver"), value: printValue(loading.driverName) },
        { label: printLabel("common.party"), value: printValue(loading.partyName) },
        { label: printLabel("common.freight"), value: printValue(formatAmount(loading.freight)) },
      ],
      tables: [
        {
          title: printLabel("loadings.details.itemsTitle"),
          columns: [printLabel("common.item"), printLabel("common.quantity"), printLabel("common.weight"), printLabel("common.unit"), printLabel("common.remarks")],
          rows: loading.items.map((item) => [printValue(item.itemName), printValue(item.quantity), printValue(item.weight), printValue(item.unit), printValue(item.remarks)]),
        },
        {
          title: printLabel("loadings.details.expenseBreakdown"),
          columns: [printLabel("loadings.details.expenseName"), printLabel("common.amount"), printLabel("common.remarks")],
          rows: expenses.map((expense) => [printValue(expense.expenseName), printValue(formatAmount(expense.amount)), printValue(expense.remarks)]),
        },
      ],
      totals: [
        { label: printLabel("loadings.details.totalIncome"), value: printValue(formatAmount(totalIncome)) },
        { label: printLabel("loadings.details.totalExpense"), value: printValue(formatAmount(totalExpense)) },
        { label: printLabel("reports.summary.netProfit"), value: printValue(formatAmount(netProfit)) },
      ],
    };
    modulePrint.openPresentation(presentation, handlePrintLegacy, loading.addaId);
  }

  return (
    <>
    <button
      type="button"
      onClick={handlePrint}
      className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white shadow-sm hover:bg-blue-700"
    >
      {t("loadings.details.print")}
    </button>
    {modulePrint.dialog}
    </>
  );
}
