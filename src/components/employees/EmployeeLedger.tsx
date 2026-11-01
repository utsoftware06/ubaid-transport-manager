"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EmployeeLedgerCards from "@/components/employees/EmployeeLedgerCards";
import EmployeeLedgerFilters from "@/components/employees/EmployeeLedgerFilters";
import EmployeeLedgerTable from "@/components/employees/EmployeeLedgerTable";
import { USER_ROLES } from "@/config/navigation";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

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

type EmployeeProfileContext = {
  role: string | null;
  adda_id: string | null;
  is_active: boolean | null;
};

type AddaOption = {
  id: string;
  name: string;
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
  const { t, dir } = useLanguage();
  const [employees, setEmployees] = useState<EmployeeLedgerEmployeeOption[]>([]);
  const [transactions, setTransactions] = useState<EmployeeTransactionDbRow[]>(
    []
  );
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [isContextLoading, setIsContextLoading] = useState(true);
  const [contextError, setContextError] = useState("");
  const [filters, setFilters] = useState<EmployeeLedgerFilterValues>({
    employeeId: "",
    fromDate: "",
    toDate: "",
    transactionType: "",
    search: "",
  });
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [page, setPage] = useState(1);
  const loadRequestIdRef = useRef(0);

  useEffect(() => {
    let isMounted = true;

    async function loadTenantContext() {
      setIsContextLoading(true);
      setContextError("");

      try {
        const { data: authData, error: authError } = await supabase.auth.getUser();
        if (authError || !authData.user) {
          throw authError ?? new Error("No authenticated user.");
        }

        const { data: profileData, error: profileError } = await supabase
          .from("profiles")
          .select("role, adda_id, is_active")
          .eq("id", authData.user.id)
          .maybeSingle();
        if (profileError) throw profileError;

        const profile = profileData as EmployeeProfileContext | null;
        if (
          !profile ||
          profile.is_active !== true ||
          (profile.role !== USER_ROLES.superAdmin &&
            profile.role !== USER_ROLES.addaAdmin)
        ) {
          throw new Error("An active Employee administrator profile is required.");
        }

        if (profile.role === USER_ROLES.superAdmin) {
          const { data: addaData, error: addaError } = await supabase
            .from("addas")
            .select("id, name")
            .order("name");
          if (addaError) throw addaError;
          if (!isMounted) return;

          setAddas((addaData ?? []) as AddaOption[]);
          setIsSuperAdmin(true);
          setProfileAddaId(null);
          setSelectedAddaId("");
        } else {
          if (!profile.adda_id) {
            throw new Error("The current profile has no assigned Adda.");
          }
          if (!isMounted) return;

          setIsSuperAdmin(false);
          setProfileAddaId(profile.adda_id);
          setSelectedAddaId("");
          setAddas([]);
        }
      } catch (error) {
        if (!isMounted) return;
        console.error("Unable to load Employee Ledger tenant context:", error);
        setContextError(t("employeeLedger.messages.loadFailed"));
      } finally {
        if (isMounted) setIsContextLoading(false);
      }
    }

    void loadTenantContext();
    return () => {
      isMounted = false;
    };
  }, [t]);

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
        employeeName: employee?.employeeName ?? t("employeeLedger.unknownEmployee"),
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
  }, [employeeLookup, transactions, t]);

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

  const totalPages = Math.max(1, Math.ceil(filteredRows.length / 10));
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const paginatedRows = useMemo(
    () => filteredRows.slice((currentPage - 1) * 10, currentPage * 10),
    [currentPage, filteredRows]
  );

  const loadLedgerData = useCallback(async (addaId: string) => {
    const requestId = ++loadRequestIdRef.current;
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, transactionsResponse] = await Promise.all([
      supabase.rpc("get_employees", { p_adda_id: addaId }),
      supabase.rpc("get_employee_transactions_for_adda", {
        p_adda_id: addaId,
      }),
    ]);

    if (requestId !== loadRequestIdRef.current) return;

    if (employeesResponse.error) {
      console.error("Failed to load employee ledger employees:", employeesResponse.error);
      setErrorMessage(t("employeeLedger.messages.loadFailed"));
      setEmployees([]);
      setTransactions([]);
      setIsLoading(false);
      return;
    }

    if (transactionsResponse.error) {
      console.error("Failed to load employee ledger transactions:", transactionsResponse.error);
      setErrorMessage(t("employeeLedger.messages.loadFailed"));
      setEmployees([]);
      setTransactions([]);
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
  }, [t]);

  useEffect(() => {
    if (isContextLoading) return;

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (contextError || !addaId) {
      loadRequestIdRef.current += 1;
      return;
    }

    const timer = window.setTimeout(() => {
      void loadLedgerData(addaId);
    }, 0);

    return () => window.clearTimeout(timer);
  }, [contextError, isContextLoading, isSuperAdmin, loadLedgerData, profileAddaId, selectedAddaId]);

  function handleAddaChange(value: string) {
    loadRequestIdRef.current += 1;
    setSelectedAddaId(value);
    setEmployees([]);
    setTransactions([]);
    handleResetFilters();
    setErrorMessage("");
    setIsLoading(Boolean(value));
  }

  function handleResetFilters() {
    setFilters({
      employeeId: "",
      fromDate: "",
      toDate: "",
      transactionType: "",
      search: "",
    });
    setPage(1);
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="employeeLedger" accent="cyan" title={t("employeeLedger.title")} description={t("employeeLedger.description")} />
      </header>

      {isSuperAdmin && !isContextLoading && (
        <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
          <label
            htmlFor="employee-ledger-adda"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Adda
          </label>
          <select
            id="employee-ledger-adda"
            name="addaId"
            value={selectedAddaId}
            onChange={(event) => handleAddaChange(event.target.value)}
            className="w-full max-w-md rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("drivers.selectAdda")}</option>
            {addas.map((adda) => (
              <option key={adda.id} value={adda.id}>
                {adda.name}
              </option>
            ))}
          </select>
        </div>
      )}

      <EmployeeLedgerCards summary={summary} />

      <EmployeeLedgerFilters
        filters={filters}
        setFilters={(value) => {
          setFilters(value);
          setPage(1);
        }}
        employees={employees}
        transactionTypes={transactionTypes}
        onReset={handleResetFilters}
      />

      <EmployeeLedgerTable
        addaId={isSuperAdmin ? selectedAddaId : profileAddaId}
        rows={paginatedRows}
        reportRows={filteredRows}
        isLoading={isLoading || isContextLoading}
        errorMessage={contextError || errorMessage}
        filters={filters}
        currentPage={currentPage}
        totalPages={totalPages}
        setPage={setPage}
      />
    </div>
  );
}
