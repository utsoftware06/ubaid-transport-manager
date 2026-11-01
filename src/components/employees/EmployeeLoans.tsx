"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EmployeeLoanCards from "@/components/employees/EmployeeLoanCards";
import EmployeeLoanForm from "@/components/employees/EmployeeLoanForm";
import EmployeeLoanTable from "@/components/employees/EmployeeLoanTable";
import { USER_ROLES } from "@/config/navigation";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

export type EmployeeLoanStatus = "Active" | "Completed";
export type EmployeeLoanStatusFilter = EmployeeLoanStatus | "All";

export type EmployeeLoanPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer"
  | "Account";

export type EmployeeOption = {
  id: string;
  employeeName: string;
  employeeType: string;
};

export type EmployeeLoanRow = {
  id: number;
  employeeId: string;
  employeeName: string;
  employeeType: string;
  loanDate: string;
  loanAmount: number;
  monthlyInstallment: number;
  recoveredAmount: number;
  remainingAmount: number;
  status: EmployeeLoanStatus;
  paymentMethod: EmployeeLoanPaymentMethod;
  referenceNo: string;
  remarks: string;
  createdAt: string;
};

export type EmployeeLoanSummary = {
  totalLoans: number;
  totalLoanAmount: number;
  totalRecovered: number;
  totalRemaining: number;
  activeLoans: number;
  completedLoans: number;
};

type EmployeeDbRow = {
  id: string;
  employee_name: string | null;
  employee_type: string | null;
};

type EmployeeLoanDbRow = {
  id: number;
  employee_id: string;
  loan_date: string | null;
  loan_amount: number | string | null;
  monthly_installment: number | string | null;
  recovered_amount: number | string | null;
  remaining_amount: number | string | null;
  status: string | null;
  reference_no: string | null;
  remarks: string | null;
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

function normalizeStatus(value: string | null | undefined): EmployeeLoanStatus {
  return value === "Completed" ? "Completed" : "Active";
}

function employeeLoanSaveErrorMessage(message: string, fallback: string) {
  const normalized = message.toUpperCase();
  const messages: Array<[string, string]> = [
    ["INVALID_EMPLOYEE_LOAN_INPUT", "Review the loan date, amount, installment, and payment method."],
    ["EMPLOYEE_NOT_FOUND", "The selected employee could not be found. Refresh and try again."],
    ["EMPLOYEE_ADDA_UNASSIGNED", "The selected employee has no assigned Adda."],
    ["EMPLOYEE_ADDA_MISMATCH", "The selected employee belongs to a different Adda."],
    ["EMPLOYEE_LOAN_NOT_FOUND", "This loan no longer exists. Refresh and try again."],
    ["HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED", "This historical loan has no assigned Adda and cannot be edited."],
    ["EMPLOYEE_LOAN_ADDA_MISMATCH", "This loan belongs to a different Adda."],
    ["LOAN_AMOUNT_BELOW_RECOVERED_AMOUNT", "The loan amount cannot be less than the amount already recovered."],
    ["LOAN_EMPLOYEE_CHANGE_BLOCKED_BY_RECOVERY", "The employee cannot be changed after loan recovery history exists."],
    ["DUPLICATE_EMPLOYEE_LOAN_CASHBOOK_REFERENCE", "More than one Cashbook row is linked to this loan. Contact an administrator."],
    ["EMPLOYEE_LOAN_CASHBOOK_REFERENCE_ALREADY_EXISTS", "A Cashbook row already exists for this new loan. Contact an administrator."],
    ["EMPLOYEE_LOAN_CASHBOOK_ADDA_MISMATCH", "The linked Cashbook row belongs to a different Adda."],
  ];

  return messages.find(([marker]) => normalized.includes(marker))?.[1] ?? fallback;
}

function employeeLoanDeleteErrorMessage(
  message: string,
  fallback: string,
  linkedWarning: string
) {
  const normalized = message.toUpperCase();
  if (normalized.includes("EMPLOYEE_LOAN_DELETE_BLOCKED_BY_RECOVERY")) {
    return linkedWarning;
  }

  const messages: Array<[string, string]> = [
    ["EMPLOYEE_LOAN_NOT_FOUND", "This loan no longer exists. Refresh and try again."],
    ["HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED", "This historical loan has no assigned Adda and cannot be deleted."],
    ["EMPLOYEE_LOAN_ADDA_MISMATCH", "This loan belongs to a different Adda."],
    ["DUPLICATE_EMPLOYEE_LOAN_CASHBOOK_REFERENCE", "Multiple Cashbook rows are linked to this loan. Contact an administrator."],
    ["EMPLOYEE_LOAN_CASHBOOK_MISSING", "The required Cashbook row is missing, so the loan was not deleted."],
    ["EMPLOYEE_LOAN_CASHBOOK_ADDA_UNASSIGNED", "The linked Cashbook row has no assigned Adda, so the loan was not deleted."],
    ["EMPLOYEE_LOAN_CASHBOOK_ADDA_MISMATCH", "The linked Cashbook row belongs to a different Adda."],
  ];

  return messages.find(([marker]) => normalized.includes(marker))?.[1] ?? fallback;
}

export default function EmployeeLoans() {
  const { t, dir } = useLanguage();
  const [employeeId, setEmployeeId] = useState("");
  const [loanDate, setLoanDate] = useState("");
  const [loanAmount, setLoanAmount] = useState("");
  const [monthlyInstallment, setMonthlyInstallment] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<EmployeeLoanPaymentMethod>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");

  const [employees, setEmployees] = useState<EmployeeOption[]>([]);
  const [loans, setLoans] = useState<EmployeeLoanDbRow[]>([]);
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [isContextLoading, setIsContextLoading] = useState(true);
  const [contextError, setContextError] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] =
    useState<EmployeeLoanStatusFilter>("All");
  const [page, setPage] = useState(1);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);
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
        console.error("Unable to load Employee Loan tenant context:", error);
        setContextError(t("employeeLoans.messages.loadFailed"));
      } finally {
        if (isMounted) setIsContextLoading(false);
      }
    }

    void loadTenantContext();
    return () => {
      isMounted = false;
    };
  }, [t]);

  const selectedEmployee = useMemo(() => {
    return employees.find((employee) => employee.id === employeeId) ?? null;
  }, [employeeId, employees]);

  const editingLoan = useMemo(() => {
    if (!editingId) return null;
    return loans.find((loan) => loan.id === editingId) ?? null;
  }, [editingId, loans]);

  const existingRecoveredAmount = useMemo(() => {
    return toNumber(editingLoan?.recovered_amount);
  }, [editingLoan]);

  const rows = useMemo<EmployeeLoanRow[]>(() => {
    return loans.map((loan) => {
      const employee = employees.find((item) => item.id === loan.employee_id);
      const loanAmountValue = toNumber(loan.loan_amount);
      const recoveredAmountValue = toNumber(loan.recovered_amount);
      const remainingAmountFromDb = toNumber(loan.remaining_amount);
      const remainingAmountValue =
        remainingAmountFromDb > 0
          ? remainingAmountFromDb
          : Math.max(loanAmountValue - recoveredAmountValue, 0);

      return {
        id: loan.id,
        employeeId: loan.employee_id,
        employeeName: employee?.employeeName ?? t("employeeLoans.unknownEmployee"),
        employeeType: employee?.employeeType ?? "-",
        loanDate: loan.loan_date ?? "",
        loanAmount: loanAmountValue,
        monthlyInstallment: toNumber(loan.monthly_installment),
        recoveredAmount: recoveredAmountValue,
        remainingAmount: remainingAmountValue,
        status: normalizeStatus(loan.status),
        paymentMethod: "Cash",
        referenceNo: loan.reference_no ?? "",
        remarks: loan.remarks ?? "",
        createdAt: loan.created_at ?? "",
      };
    });
  }, [employees, loans, t]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return rows.filter((row) => {
      const searchableText = [
        row.employeeName,
        row.employeeType,
        row.status,
        row.loanDate,
        row.referenceNo,
        row.remarks,
        String(row.loanAmount),
        String(row.remainingAmount),
      ]
        .join(" ")
        .toLowerCase();

      return (
        (!keyword || searchableText.includes(keyword)) &&
        (statusFilter === "All" || row.status === statusFilter)
      );
    });
  }, [rows, search, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredRows.length / 10));
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const paginatedRows = useMemo(
    () => filteredRows.slice((currentPage - 1) * 10, currentPage * 10),
    [currentPage, filteredRows]
  );

  const summary = useMemo<EmployeeLoanSummary>(() => {
    return filteredRows.reduce(
      (total, row) => {
        total.totalLoans += 1;
        total.totalLoanAmount += row.loanAmount;
        total.totalRecovered += row.recoveredAmount;
        total.totalRemaining += row.remainingAmount;

        if (row.status === "Completed") {
          total.completedLoans += 1;
        } else {
          total.activeLoans += 1;
        }

        return total;
      },
      {
        totalLoans: 0,
        totalLoanAmount: 0,
        totalRecovered: 0,
        totalRemaining: 0,
        activeLoans: 0,
        completedLoans: 0,
      }
    );
  }, [filteredRows]);

  const loadInitialData = useCallback(async (addaId: string) => {
    const requestId = ++loadRequestIdRef.current;
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, loansResponse] = await Promise.all([
      supabase.rpc("get_employees", { p_adda_id: addaId }),
      supabase.rpc("get_employee_loans_for_adda", { p_adda_id: addaId }),
    ]);

    if (requestId !== loadRequestIdRef.current) return;

    if (employeesResponse.error) {
      console.error("Failed to load employee options:", employeesResponse.error);
      setErrorMessage(t("employeeLoans.messages.loadFailed"));
      setEmployees([]);
      setLoans([]);
      setIsLoading(false);
      return;
    }

    if (loansResponse.error) {
      console.error("Failed to load employee loans:", loansResponse.error);
      setErrorMessage(t("employeeLoans.messages.loadFailed"));
      setEmployees([]);
      setLoans([]);
      setIsLoading(false);
      return;
    }

    const employeeRows = (employeesResponse.data ?? []) as EmployeeDbRow[];
    const loanRows = (loansResponse.data ?? []) as EmployeeLoanDbRow[];

    setEmployees(
      employeeRows.map((employee) => ({
        id: employee.id,
        employeeName: employee.employee_name ?? "",
        employeeType: employee.employee_type ?? "",
      }))
    );

    setLoans(loanRows);
    setIsLoading(false);
  }, [t]);

  useEffect(() => {
    if (isContextLoading) return;

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (contextError || !addaId) {
      const clearTimer = window.setTimeout(() => {
        loadRequestIdRef.current += 1;
        setEmployees([]);
        setLoans([]);
        setErrorMessage(contextError);
        setIsLoading(false);
      }, 0);
      return () => window.clearTimeout(clearTimer);
    }

    const timer = window.setTimeout(() => {
      void loadInitialData(addaId);
    }, 0);

    return () => window.clearTimeout(timer);
  }, [contextError, isContextLoading, isSuperAdmin, loadInitialData, profileAddaId, selectedAddaId]);

  async function loadLoans(addaId: string) {
    const requestId = ++loadRequestIdRef.current;
    const { data, error } = await supabase.rpc(
      "get_employee_loans_for_adda",
      { p_adda_id: addaId }
    );

    if (requestId !== loadRequestIdRef.current) return;
    if (error) {
      console.error("Failed to reload employee loans:", error);
      setErrorMessage(t("employeeLoans.messages.loadFailed"));
      setLoans([]);
      return;
    }

    setLoans((data ?? []) as EmployeeLoanDbRow[]);
  }

  function handleAddaChange(value: string) {
    loadRequestIdRef.current += 1;
    setSelectedAddaId(value);
    setEmployees([]);
    setLoans([]);
    resetForm();
    setErrorMessage("");
    setIsLoading(Boolean(value));
  }

  const currentAddaId = isSuperAdmin ? selectedAddaId : profileAddaId;

  function resetForm() {
    setEmployeeId("");
    setLoanDate("");
    setLoanAmount("");
    setMonthlyInstallment("");
    setPaymentMethod("Cash");
    setReferenceNo("");
    setRemarks("");
    setEditingId(null);
  }

  function validateForm() {
    const loanValue = Number(loanAmount);
    const installmentValue = Number(monthlyInstallment || 0);

    if (!employeeId) {
      alert(t("employeeLoans.validation.selectEmployee"));
      return false;
    }

    if (!loanDate) {
      alert(t("employeeLoans.validation.dateRequired"));
      return false;
    }

    if (!loanAmount || !Number.isFinite(loanValue) || loanValue <= 0) {
      alert(t("employeeLoans.validation.amountPositive"));
      return false;
    }

    if (!Number.isFinite(installmentValue) || installmentValue < 0) {
      alert(t("employeeLoans.validation.installmentNonNegative"));
      return false;
    }

    if (installmentValue > loanValue) {
      alert(t("employeeLoans.validation.installmentExceedsLoan"));
      return false;
    }

    if (editingId && loanValue < existingRecoveredAmount) {
      alert(t("employeeLoans.validation.amountBelowRecovered"));
      return false;
    }

    if (!paymentMethod) {
      alert(t("employeeLoans.validation.paymentMethodRequired"));
      return false;
    }

    return true;
  }

  async function handleSaveLoan() {
    if (saveInProgressRef.current) return;
    if (!validateForm()) return;

    if (isContextLoading || contextError) {
      alert(contextError || t("employeeLoans.messages.loadFailed"));
      return;
    }

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (!addaId) {
      alert(isSuperAdmin ? t("drivers.selectAdda") : t("employeeLoans.messages.loadFailed"));
      return;
    }

    saveInProgressRef.current = true;
    setIsSaving(true);
    setErrorMessage("");

    const loanValue = Number(loanAmount);
    const installmentValue = Number(monthlyInstallment || 0);
    try {
      const { error } = await supabase.rpc("save_employee_loan", {
        p_employee_id: employeeId,
        p_loan_date: loanDate,
        p_loan_amount: loanValue,
        p_monthly_installment: installmentValue,
        p_payment_method: paymentMethod,
        p_reference_no: referenceNo.trim() || null,
        p_remarks: remarks.trim() || null,
        p_adda_id: addaId,
        p_id: editingId,
      });

      if (error) {
        console.error("Failed to save employee loan:", error);
        alert(
          employeeLoanSaveErrorMessage(
            error.message,
            editingId
              ? t("employeeLoans.messages.updateFailed")
              : t("employeeLoans.messages.saveFailed")
          )
        );
        return;
      }

      alert(
        editingId
          ? t("employeeLoans.messages.updated")
          : t("employeeLoans.messages.saved")
      );
      resetForm();
      await loadLoans(addaId);
    } catch (error) {
      console.error("Failed to save employee loan:", error);
      alert(
        editingId
          ? t("employeeLoans.messages.updateFailed")
          : t("employeeLoans.messages.saveFailed")
      );
    } finally {
      setIsSaving(false);
      saveInProgressRef.current = false;
    }
  }

  function handleEditLoan(row: EmployeeLoanRow) {
    setEditingId(row.id);
    setEmployeeId(row.employeeId);
    setLoanDate(row.loanDate);
    setLoanAmount(String(row.loanAmount || ""));
    setMonthlyInstallment(String(row.monthlyInstallment || ""));
    setPaymentMethod("Cash");
    setReferenceNo(row.referenceNo);
    setRemarks(row.remarks);
  }

  async function handleDeleteLoan(row: EmployeeLoanRow) {
    if (deleteInProgressRef.current) return;
    const confirmed = window.confirm(
      `${t("employeeLoans.messages.deleteConfirm")} ${row.employeeName}? ${t("employeeLoans.messages.deleteConfirmSuffix")}`
    );

    if (!confirmed) return;

    if (isContextLoading || contextError || !currentAddaId) {
      alert(
        contextError ||
          (isSuperAdmin
            ? t("drivers.selectAdda")
            : t("employeeLoans.messages.loadFailed"))
      );
      return;
    }

    const addaId = currentAddaId;

    deleteInProgressRef.current = true;
    setIsDeleting(true);
    setErrorMessage("");

    try {
      const { error } = await supabase.rpc("delete_employee_loan", {
        p_id: row.id,
        p_adda_id: addaId,
      });

      if (error) {
        console.error("Failed to delete employee loan:", error);
        alert(
          employeeLoanDeleteErrorMessage(
            error.message,
            t("employeeLoans.messages.deleteFailed"),
            t("employeeLoans.messages.deleteLinked")
          )
        );
        return;
      }

      if (editingId === row.id) resetForm();

      await loadLoans(addaId);
      alert(t("employeeLoans.messages.deleted"));
    } catch (error) {
      console.error("Failed to delete employee loan:", error);
      const message = error instanceof Error ? error.message : String(error);
      alert(
        employeeLoanDeleteErrorMessage(
          message,
          t("employeeLoans.messages.deleteFailed"),
          t("employeeLoans.messages.deleteLinked")
        )
      );
    } finally {
      setIsDeleting(false);
      deleteInProgressRef.current = false;
    }
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="payment" accent="cyan" title={t("employeeLoans.title")} description={t("employeeLoans.description")} />
      </header>

      {isSuperAdmin && !isContextLoading && (
        <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
          <label
            htmlFor="employee-loan-adda"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Adda
          </label>
          <select
            required
            id="employee-loan-adda"
            name="addaId"
            value={selectedAddaId}
            onChange={(event) => handleAddaChange(event.target.value)}
            disabled={isSaving}
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

      <EmployeeLoanCards summary={summary} />

      <EmployeeLoanForm
        recordId={editingId}
        employeeId={employeeId}
        setEmployeeId={setEmployeeId}
        loanDate={loanDate}
        setLoanDate={setLoanDate}
        loanAmount={loanAmount}
        setLoanAmount={setLoanAmount}
        monthlyInstallment={monthlyInstallment}
        setMonthlyInstallment={setMonthlyInstallment}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        referenceNo={referenceNo}
        setReferenceNo={setReferenceNo}
        remarks={remarks}
        setRemarks={setRemarks}
        employees={employees}
        selectedEmployee={selectedEmployee}
        existingRecoveredAmount={existingRecoveredAmount}
        onSave={handleSaveLoan}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <EmployeeLoanTable
        addaId={currentAddaId}
        rows={paginatedRows}
        reportRows={filteredRows}
        search={search}
        setSearch={(value) => {
          setSearch(value);
          setPage(1);
        }}
        statusFilter={statusFilter}
        setStatusFilter={(value) => {
          setStatusFilter(value);
          setPage(1);
        }}
        onResetFilters={() => {
          setSearch("");
          setStatusFilter("All");
          setPage(1);
        }}
        currentPage={currentPage}
        totalPages={totalPages}
        setPage={setPage}
        onEdit={handleEditLoan}
        onDelete={handleDeleteLoan}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
