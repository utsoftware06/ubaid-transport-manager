"use client";

import { useEffect, useMemo, useState } from "react";
import EmployeeLedgerCards from "@/components/employees/EmployeeLedgerCards";
import EmployeeLedgerFilters from "@/components/employees/EmployeeLedgerFilters";
import EmployeeLedgerTable from "@/components/employees/EmployeeLedgerTable";
import { supabase } from "@/lib/supabase/client";

export type EmployeeLedgerFilterValues = {
  employeeId: string;
  fromDate: string;
  toDate: string;
  transactionType: string;
  search: string;
};

export type EmployeeLedgerEmployeeOption = {
  id: string;
  employeeName: string;
  employeeType: string;
};

export type EmployeeLedgerTransactionRow = {
  id: number;
  employeeId: string;
  employeeName: string;
  employeeType: string;
  transactionDate: string;
  transactionType: string;
  description: string;
  amount: number;
  debit: number;
  credit: number;
  runningBalance: number;
  paymentMethod: string;
  referenceNo: string;
  remarks: string;
  salaryRecordId: number | null;
  loanId: number | null;
  createdAt: string;
};

export type EmployeeLedgerSummary = {
  totalEmployees: number;
  totalTransactions: number;
  totalDebit: number;
  totalCredit: number;
  companyPayable: number;
  employeeReceivable: number;
};

type EmployeeDbRow = {
  id: string;
  employee_name: string | null;
  employee_type: string | null;
};

type EmployeeTransactionDbRow = {
  id: number;
  employee_id: string;
  transaction_date: string | null;
  transaction_type: string | null;
  amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  description: string | null;
  remarks: string | null;
  salary_record_id: number | null;
  loan_id: number | null;
  created_at: string | null;
};

export function formatAmount(value: number) {
  return `Rs. ${Math.round(Number(value || 0)).toLocaleString("en-PK")}`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function getTransactionEffect(transactionType: string, amount: number) {
 if (
  transactionType === "Salary Generated" ||
  transactionType === "Advance Recovery" ||
  transactionType === "Adjustment Debit"
) {
  return amount;
}

 if (
  transactionType === "Salary Paid" ||
  transactionType === "Employee Loan" ||
  transactionType === "Loan Recovery" ||
  transactionType === "Advance Salary" ||
  transactionType === "Adjustment Credit"
) {
  return -amount;
}
  return 0;
}

function getDebitCredit(transactionType: string, amount: number) {
  const effect = getTransactionEffect(transactionType, amount);

  if (effect > 0) {
    return {
      debit: amount,
      credit: 0,
    };
  }

  if (effect < 0) {
    return {
      debit: 0,
      credit: amount,
    };
  }

  return {
    debit: 0,
    credit: 0,
  };
}

function sortTransactionsForLedger(
  transactions: EmployeeTransactionDbRow[]
): EmployeeTransactionDbRow[] {
  return [...transactions].sort((first, second) => {
    const employeeCompare = first.employee_id.localeCompare(second.employee_id);

    if (employeeCompare !== 0) return employeeCompare;

    const firstDate = first.transaction_date ?? "";
    const secondDate = second.transaction_date ?? "";
    const dateCompare = firstDate.localeCompare(secondDate);

    if (dateCompare !== 0) return dateCompare;

    const firstCreatedAt = first.created_at ?? "";
    const secondCreatedAt = second.created_at ?? "";
    const createdAtCompare = firstCreatedAt.localeCompare(secondCreatedAt);

    if (createdAtCompare !== 0) return createdAtCompare;

    return first.id - second.id;
  });
}

export default function EmployeeLedger() {
  const [employees, setEmployees] = useState<EmployeeLedgerEmployeeOption[]>([]);
  const [transactions, setTransactions] = useState<EmployeeTransactionDbRow[]>(
    []
  );
  const [filters, setFilters] = useState<EmployeeLedgerFilterValues>({
    employeeId: "",
    fromDate: "",
    toDate: "",
    transactionType: "",
    search: "",
  });
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  const employeeLookup = useMemo(() => {
    return new Map(employees.map((employee) => [employee.id, employee]));
  }, [employees]);

  const rows = useMemo<EmployeeLedgerTransactionRow[]>(() => {
    const runningBalanceByEmployee = new Map<string, number>();
    const sortedTransactions = sortTransactionsForLedger(transactions);

    return sortedTransactions.map((transaction) => {
      const employee = employeeLookup.get(transaction.employee_id);
      const amount = toNumber(transaction.amount);
      const transactionType = transaction.transaction_type ?? "";
      const effect = getTransactionEffect(transactionType, amount);
      const previousBalance =
        runningBalanceByEmployee.get(transaction.employee_id) ?? 0;
      const runningBalance = previousBalance + effect;
      const debitCredit = getDebitCredit(transactionType, amount);

      runningBalanceByEmployee.set(transaction.employee_id, runningBalance);

      return {
        id: transaction.id,
        employeeId: transaction.employee_id,
        employeeName: employee?.employeeName ?? "Unknown Employee",
        employeeType: employee?.employeeType ?? "-",
        transactionDate: transaction.transaction_date ?? "",
        transactionType,
        description: transaction.description ?? "",
        amount,
        debit: debitCredit.debit,
        credit: debitCredit.credit,
        runningBalance,
        paymentMethod: transaction.payment_method ?? "",
        referenceNo: transaction.reference_no ?? "",
        remarks: transaction.remarks ?? "",
        salaryRecordId: transaction.salary_record_id,
        loanId: transaction.loan_id,
        createdAt: transaction.created_at ?? "",
      };
    });
  }, [employeeLookup, transactions]);

  const filteredRows = useMemo(() => {
    const keyword = filters.search.trim().toLowerCase();

    return rows.filter((row) => {
      if (filters.employeeId && row.employeeId !== filters.employeeId) {
        return false;
      }

      if (filters.fromDate && row.transactionDate < filters.fromDate) {
        return false;
      }

      if (filters.toDate && row.transactionDate > filters.toDate) {
        return false;
      }

      if (
        filters.transactionType &&
        row.transactionType !== filters.transactionType
      ) {
        return false;
      }

      if (!keyword) return true;

      const searchableText = [
        row.employeeName,
        row.employeeType,
        row.transactionType,
        row.description,
        row.referenceNo,
        row.remarks,
        row.paymentMethod,
        String(row.amount),
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [filters, rows]);

  const transactionTypes = useMemo(() => {
    return Array.from(
      new Set(rows.map((row) => row.transactionType).filter(Boolean))
    ).sort((first, second) => first.localeCompare(second));
  }, [rows]);

  const summary = useMemo<EmployeeLedgerSummary>(() => {
    const employeeIds = new Set(filteredRows.map((row) => row.employeeId));
    const totalDebit = filteredRows.reduce((total, row) => total + row.debit, 0);
    const totalCredit = filteredRows.reduce(
      (total, row) => total + row.credit,
      0
    );
    const finalBalanceByEmployee = new Map<string, number>();

    filteredRows.forEach((row) => {
      finalBalanceByEmployee.set(row.employeeId, row.runningBalance);
    });

    let companyPayable = 0;
    let employeeReceivable = 0;

    finalBalanceByEmployee.forEach((balance) => {
      if (balance > 0) companyPayable += balance;
      if (balance < 0) employeeReceivable += Math.abs(balance);
    });

    return {
      totalEmployees: employeeIds.size,
      totalTransactions: filteredRows.length,
      totalDebit,
      totalCredit,
      companyPayable,
      employeeReceivable,
    };
  }, [filteredRows]);

  useEffect(() => {
    loadLedgerData();
  }, []);

  async function loadLedgerData() {
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, transactionsResponse] = await Promise.all([
      supabase
        .from("employees")
        .select("id, employee_name, employee_type")
        .order("employee_name", { ascending: true }),
      supabase
        .from("employee_transactions")
        .select(
          "id, employee_id, transaction_date, transaction_type, amount, payment_method, reference_no, description, remarks, salary_record_id, loan_id, created_at"
        )
        .order("employee_id", { ascending: true })
        .order("transaction_date", { ascending: true })
        .order("created_at", { ascending: true })
        .order("id", { ascending: true }),
    ]);

    if (employeesResponse.error) {
      setErrorMessage(employeesResponse.error.message);
      setIsLoading(false);
      return;
    }

    if (transactionsResponse.error) {
      setErrorMessage(transactionsResponse.error.message);
      setIsLoading(false);
      return;
    }

    const employeeRows = (employeesResponse.data ?? []) as EmployeeDbRow[];
    const transactionRows = (transactionsResponse.data ??
      []) as EmployeeTransactionDbRow[];

    setEmployees(
      employeeRows.map((employee) => ({
        id: employee.id,
        employeeName: employee.employee_name ?? "",
        employeeType: employee.employee_type ?? "",
      }))
    );
    setTransactions(transactionRows);
    setIsLoading(false);
  }

  function handleResetFilters() {
    setFilters({
      employeeId: "",
      fromDate: "",
      toDate: "",
      transactionType: "",
      search: "",
    });
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">Employee Ledger</h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Review employee salary, loan, recovery and adjustment transactions
          with running balances.
        </p>
      </div>

      <EmployeeLedgerCards summary={summary} />

      <EmployeeLedgerFilters
        filters={filters}
        setFilters={setFilters}
        employees={employees}
        transactionTypes={transactionTypes}
        onReset={handleResetFilters}
      />

      <EmployeeLedgerTable
        rows={filteredRows}
        isLoading={isLoading}
        errorMessage={errorMessage}
        filters={filters}
      />
    </div>
  );
}