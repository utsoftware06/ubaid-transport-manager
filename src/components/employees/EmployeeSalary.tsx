"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EmployeeSalaryCards from "@/components/employees/EmployeeSalaryCards";
import EmployeeSalaryForm from "@/components/employees/EmployeeSalaryForm";
import EmployeeSalarySlip from "@/components/employees/EmployeeSalarySlip";
import EmployeeSalaryTable from "@/components/employees/EmployeeSalaryTable";
import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { supabase } from "@/lib/supabase/client";

export type SalaryPaymentStatus = "Paid" | "Partial" | "Unpaid";

export type SalaryPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer"
  | "Account";

export type SalaryStatusFilter = SalaryPaymentStatus | "All";
export type SalaryMethodFilter = SalaryPaymentMethod | "All";

export type EmployeeSalaryOption = {
  id: string;
  employeeName: string;
  employeeType: string;
  monthlySalary: number;
  status: string;
  activeLoanId: number | null;
  activeLoanRemaining: number;
  monthlyInstallment: number;
};

export type EmployeeSalaryRow = {
  id: number;
  employeeId: string;
  employeeName: string;
  employeeType: string;
  salaryMonth: string;
  basicSalary: number;
  bonus: number;
  deduction: number;
  loanRecovery: number;
  advanceRecovery: number;
  netSalary: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: SalaryPaymentStatus;
  paymentMethod: SalaryPaymentMethod;
  referenceNo: string;
  remarks: string;
  createdAt: string;
};

export type EmployeeSalarySummary = {
  totalRecords: number;
  totalBasicSalary: number;
  totalBonus: number;
  totalDeduction: number;
  totalLoanRecovery: number;
  totalNetSalary: number;
  totalPaid: number;
  totalRemaining: number;
};

type EmployeeDbRow = {
  id: string;
  employee_name: string | null;
  employee_type: string | null;
  monthly_salary: number | string | null;
  status: string | null;
};

type EmployeeLoanDbRow = {
  id: number;
  employee_id: string;
  loan_amount: number | string | null;
  monthly_installment?: number | string | null;
  recovered_amount: number | string | null;
  remaining_amount: number | string | null;
  status: string | null;
};

type SalaryRecordDbRow = {
  id: number;
  employee_id: string;
  salary_month: string | null;
  basic_salary: number | string | null;
  bonus: number | string | null;
  deduction: number | string | null;
  loan_recovery: number | string | null;
  advance_recovery: number | string | null;
  net_salary: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  payment_method: string | null;
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
  const numberValue = Number(value ?? 0);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function normalizePaymentStatus(value: string | null): SalaryPaymentStatus {
  if (value === "Paid" || value === "Partial") return value;
  return "Unpaid";
}

function normalizePaymentMethod(value: string | null): SalaryPaymentMethod {
  if (
    value === "Bank" ||
    value === "Cheque" ||
    value === "Online Transfer" ||
    value === "Account"
  ) {
    return value;
  }

  return "Cash";
}

function getNetSalary(
  basicSalary: number,
  bonus: number,
  deduction: number,
  loanRecovery: number,
  advanceRecovery: number
) {
  return basicSalary + bonus - deduction - loanRecovery - advanceRecovery;
}

function employeeSalaryErrorMessage(message: string, fallback: string) {
  const normalized = message.toUpperCase();
  const errors: Array<[string, string]> = [
    ["AUTHENTICATION_REQUIRED", "Your session has expired. Sign in again."],
    ["EMPLOYEE_SALARY_AUTHORITATIVE_ADDA_UNRESOLVED", "The selected Adda could not be verified."],
    ["EMPLOYEE_ADDA_UNASSIGNED", "The selected employee has no assigned Adda."],
    ["EMPLOYEE_NOT_FOUND_OR_ADDA_MISMATCH", "The selected employee is unavailable in this Adda."],
    ["EMPLOYEE_NOT_ACTIVE", "Only active Employees can be selected for Salary."],
    ["EMPLOYEE_SALARY_MONTH_ALREADY_EXISTS", "A Salary record already exists for this Employee and month."],
    ["HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED", "This historical Salary has no assigned Adda and cannot be changed."],
    ["HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED", "This historical Loan has no assigned Adda and cannot be used for recovery."],
    ["EMPLOYEE_SALARY_LOAN_NOT_FOUND", "The selected Employee Loan could not be found."],
    ["EMPLOYEE_SALARY_LOAN_ADDA_OR_EMPLOYEE_MISMATCH", "The selected Employee Loan does not belong to this Employee and Adda."],
    ["EMPLOYEE_SALARY_LOAN_RECOVERY_EXCEEDS_AVAILABLE_AMOUNT", "Loan recovery exceeds the available Loan balance."],
    ["EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT", "Existing Salary recovery records are inconsistent. No changes were made."],
    ["EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT", "Existing Salary accounting records are inconsistent. No changes were made."],
    ["DUPLICATE_EMPLOYEE_SALARY_CASHBOOK_REFERENCE", "Multiple Cashbook rows are linked to this Salary. Contact an administrator."],
    ["EMPLOYEE_SALARY_NOT_FOUND", "This Salary record no longer exists."],
    ["EMPLOYEE_SALARY_ADDA_MISMATCH", "This Salary belongs to a different Adda."],
    ["EMPLOYEE_SALARY_CASHBOOK_EVIDENCE_INCONSISTENT", "The Salary Cashbook record is inconsistent. No changes were made."],
    ["EMPLOYEE_SALARY_PAID_EXCEEDS_NET", "Paid amount cannot exceed net Salary."],
    ["EMPLOYEE_SALARY_NET_CANNOT_BE_NEGATIVE", "Net Salary cannot be negative."],
    ["EMPLOYEE_SALARY_PAYMENT_METHOD_REQUIRED", "Select a payment method when entering a paid amount."],
  ];

  return errors.find(([marker]) => normalized.includes(marker))?.[1] ?? fallback;
}

export default function EmployeeSalary() {
  const { t, dir } = useLanguage();
  const [employeeId, setEmployeeId] = useState("");
  const [salaryMonth, setSalaryMonth] = useState("");
  const [basicSalary, setBasicSalary] = useState("");
  const [bonus, setBonus] = useState("");
  const [deduction, setDeduction] = useState("");
  const [loanRecovery, setLoanRecovery] = useState("");
  const [advanceRecovery, setAdvanceRecovery] = useState("");
  const [paidAmount, setPaidAmount] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<SalaryPaymentMethod>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");

  const [employees, setEmployees] = useState<EmployeeDbRow[]>([]);
  const [salaryRecords, setSalaryRecords] = useState<SalaryRecordDbRow[]>([]);
  const [loans, setLoans] = useState<EmployeeLoanDbRow[]>([]);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] =
    useState<SalaryStatusFilter>("All");
  const [methodFilter, setMethodFilter] =
    useState<SalaryMethodFilter>("All");
  const [page, setPage] = useState(1);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [selectedSlip, setSelectedSlip] = useState<EmployeeSalaryRow | null>(
    null
  );
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [isContextLoading, setIsContextLoading] = useState(true);
  const [contextError, setContextError] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);
  const loadRequestIdRef = useRef(0);

  const employeeOptions = useMemo<EmployeeSalaryOption[]>(() => {
    return employees.map((employee) => {
      const activeLoan = loans.find(
        (loan) =>
          loan.employee_id === employee.id &&
          loan.status === "Active" &&
          toNumber(loan.remaining_amount) > 0
      );

      return {
        id: employee.id,
        employeeName: employee.employee_name ?? "",
        employeeType: employee.employee_type ?? "",
        monthlySalary: toNumber(employee.monthly_salary),
        status: employee.status ?? "",
        activeLoanId: activeLoan?.id ?? null,
        activeLoanRemaining: toNumber(activeLoan?.remaining_amount),
        monthlyInstallment: toNumber(activeLoan?.monthly_installment),
      };
    });
  }, [employees, loans]);

  const activeEmployeeOptions = useMemo(() => {
    return employeeOptions.filter((employee) => employee.status === "Active");
  }, [employeeOptions]);

  const selectedEmployee = useMemo(() => {
    return employeeOptions.find((employee) => employee.id === employeeId) ?? null;
  }, [employeeId, employeeOptions]);

  const rows = useMemo<EmployeeSalaryRow[]>(() => {
    return salaryRecords.map((record) => {
      const employee = employeeOptions.find(
        (item) => item.id === record.employee_id
      );

      return {
        id: record.id,
        employeeId: record.employee_id,
        employeeName: employee?.employeeName ?? t("employeeSalary.unknownEmployee"),
        employeeType: employee?.employeeType ?? "-",
        salaryMonth: record.salary_month ?? "",
        basicSalary: toNumber(record.basic_salary),
        bonus: toNumber(record.bonus),
        deduction: toNumber(record.deduction),
        loanRecovery: toNumber(record.loan_recovery),
        advanceRecovery: toNumber(record.advance_recovery),
        netSalary: toNumber(record.net_salary),
        paidAmount: toNumber(record.paid_amount),
        remainingAmount: toNumber(record.remaining_amount),
        paymentStatus: normalizePaymentStatus(record.payment_status),
        paymentMethod: normalizePaymentMethod(record.payment_method),
        referenceNo: record.reference_no ?? "",
        remarks: record.remarks ?? "",
        createdAt: record.created_at ?? "",
      };
    });
  }, [employeeOptions, salaryRecords, t]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return rows.filter((row) => {
      const searchableText = [
        row.employeeName,
        row.employeeType,
        row.salaryMonth,
        row.paymentStatus,
        row.paymentMethod,
        row.referenceNo,
        row.remarks,
      ]
        .join(" ")
        .toLowerCase();

      const matchesSearch = !keyword || searchableText.includes(keyword);
      const matchesStatus =
        statusFilter === "All" || row.paymentStatus === statusFilter;
      const matchesMethod =
        methodFilter === "All" || row.paymentMethod === methodFilter;

      return matchesSearch && matchesStatus && matchesMethod;
    });
  }, [methodFilter, rows, search, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredRows.length / 10));
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const paginatedRows = useMemo(
    () => filteredRows.slice((currentPage - 1) * 10, currentPage * 10),
    [currentPage, filteredRows]
  );

  const summary = useMemo<EmployeeSalarySummary>(() => {
    return filteredRows.reduce(
      (total, row) => {
        total.totalRecords += 1;
        total.totalBasicSalary += row.basicSalary;
        total.totalBonus += row.bonus;
        total.totalDeduction += row.deduction;
        total.totalLoanRecovery += row.loanRecovery;
        total.totalNetSalary += row.netSalary;
        total.totalPaid += row.paidAmount;
        total.totalRemaining += row.remainingAmount;
        return total;
      },
      {
        totalRecords: 0,
        totalBasicSalary: 0,
        totalBonus: 0,
        totalDeduction: 0,
        totalLoanRecovery: 0,
        totalNetSalary: 0,
        totalPaid: 0,
        totalRemaining: 0,
      }
    );
  }, [filteredRows]);

  useEffect(() => {
    const syncTimer = window.setTimeout(() => {
      if (!employeeId || editingId) return;

      const employee = employeeOptions.find((item) => item.id === employeeId);

      if (!employee) return;

      setBasicSalary(String(employee.monthlySalary || ""));
      setLoanRecovery(
        String(
          Math.min(employee.monthlyInstallment, employee.activeLoanRemaining) || ""
        )
      );
    }, 0);

    return () => window.clearTimeout(syncTimer);
  }, [employeeId, employeeOptions, editingId]);

  const currentAddaId = isSuperAdmin ? selectedAddaId : profileAddaId;

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
        console.error("Unable to load Employee Salary tenant context:", error);
        setContextError(t("employeeSalary.messages.loadFailed"));
      } finally {
        if (isMounted) setIsContextLoading(false);
      }
    }

    void loadTenantContext();
    return () => {
      isMounted = false;
    };
  }, [t]);

  const loadInitialData = useCallback(async (addaId: string) => {
    const requestId = ++loadRequestIdRef.current;
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, loansResponse, salaryResponse] = await Promise.all([
      supabase.rpc("get_employees", { p_adda_id: addaId }),
      supabase.rpc("get_employee_loans_for_adda", { p_adda_id: addaId }),
      supabase.rpc("get_employee_salary_records_for_adda", {
        p_adda_id: addaId,
      }),
    ]);

    if (requestId !== loadRequestIdRef.current) return;

    if (employeesResponse.error || loansResponse.error || salaryResponse.error) {
      console.error("Unable to load salary data:", {
        employees: employeesResponse.error,
        loans: loansResponse.error,
        salaries: salaryResponse.error,
      });
      setEmployees([]);
      setLoans([]);
      setSalaryRecords([]);
      setErrorMessage(t("employeeSalary.messages.loadFailed"));
      setIsLoading(false);
      return;
    }

    setEmployees((employeesResponse.data ?? []) as EmployeeDbRow[]);
    setLoans(
      ((loansResponse.data ?? []) as EmployeeLoanDbRow[]).sort(
        (left, right) => left.id - right.id
      )
    );
    setSalaryRecords((salaryResponse.data ?? []) as SalaryRecordDbRow[]);
    setIsLoading(false);
  }, [t]);

  useEffect(() => {
    if (isContextLoading) return;

    if (contextError || !currentAddaId) {
      loadRequestIdRef.current += 1;
      const clearTimer = window.setTimeout(() => {
        setEmployees([]);
        setLoans([]);
        setSalaryRecords([]);
        setIsLoading(false);
      }, 0);

      return () => window.clearTimeout(clearTimer);
    }

    const timer = window.setTimeout(() => {
      void loadInitialData(currentAddaId);
    }, 0);

    return () => window.clearTimeout(timer);
  }, [contextError, currentAddaId, isContextLoading, loadInitialData]);

  async function reloadSalaryData(addaId: string | null = currentAddaId) {
    if (!addaId) return;

    const [loansResponse, salaryResponse] = await Promise.all([
      supabase.rpc("get_employee_loans_for_adda", { p_adda_id: addaId }),
      supabase.rpc("get_employee_salary_records_for_adda", {
        p_adda_id: addaId,
      }),
    ]);

    if (loansResponse.error || salaryResponse.error) {
      console.error("Unable to reload salary data:", {
        loans: loansResponse.error,
        salaries: salaryResponse.error,
      });
      setErrorMessage(t("employeeSalary.messages.loadFailed"));
      return;
    }

    setLoans(
      ((loansResponse.data ?? []) as EmployeeLoanDbRow[]).sort(
        (left, right) => left.id - right.id
      )
    );
    setSalaryRecords((salaryResponse.data ?? []) as SalaryRecordDbRow[]);
  }

  function handleAddaChange(value: string) {
    setSelectedAddaId(value);
    resetForm();
    setEmployees([]);
    setLoans([]);
    setSalaryRecords([]);
    setErrorMessage("");
  }

  function resetForm() {
    setEmployeeId("");
    setSalaryMonth("");
    setBasicSalary("");
    setBonus("");
    setDeduction("");
    setLoanRecovery("");
    setAdvanceRecovery("");
    setPaidAmount("");
    setPaymentMethod("Cash");
    setReferenceNo("");
    setRemarks("");
    setEditingId(null);
  }

  function validateForm() {
    const basic = Number(basicSalary || 0);
    const bonusValue = Number(bonus || 0);
    const deductionValue = Number(deduction || 0);
    const loanRecoveryValue = Number(loanRecovery || 0);
    const advanceRecoveryValue = Number(advanceRecovery || 0);
    const paidValue = Number(paidAmount || 0);
    const net = getNetSalary(
      basic,
      bonusValue,
      deductionValue,
      loanRecoveryValue,
      advanceRecoveryValue
    );

    if (!employeeId) {
      alert(t("employeeSalary.validation.selectEmployee"));
      return false;
    }

    if (!salaryMonth) {
      alert(t("employeeSalary.validation.monthRequired"));
      return false;
    }

    if (
      [basic, bonusValue, deductionValue].some(
        (value) => !Number.isFinite(value) || value < 0
      )
    ) {
      alert(t("employeeSalary.validation.salaryValuesNonNegative"));
      return false;
    }

    if (
      [loanRecoveryValue, advanceRecoveryValue].some(
        (value) => !Number.isFinite(value) || value < 0
      )
    ) {
      alert(t("employeeSalary.validation.recoveriesNonNegative"));
      return false;
    }

    if (!Number.isFinite(net) || net < 0) {
      alert(t("employeeSalary.validation.netSalaryNonNegative"));
      return false;
    }

    if (!Number.isFinite(paidValue) || paidValue < 0) {
      alert(t("employeeSalary.validation.paidNonNegative"));
      return false;
    }

    if (paidValue > net) {
      alert(t("employeeSalary.validation.paidExceedsNet"));
      return false;
    }

    if (paidValue > 0 && !paymentMethod) {
      alert(t("employeeSalary.validation.paymentMethodRequired"));
      return false;
    }

    const duplicate = salaryRecords.find(
      (record) =>
        record.employee_id === employeeId &&
        record.salary_month === salaryMonth &&
        record.id !== editingId
    );

    if (duplicate) {
      alert(t("employeeSalary.validation.duplicateRecord"));
      return false;
    }

    return true;
  }

  async function handleSaveSalary() {
    if (saveInProgressRef.current) return;
    if (!currentAddaId) {
      alert(isSuperAdmin ? t("drivers.selectAdda") : t("employeeSalary.messages.loadFailed"));
      return;
    }
    if (!validateForm()) return;

    const employee = selectedEmployee;

    if (!employee) {
      alert(t("employeeSalary.messages.employeeNotFound"));
      return;
    }

    saveInProgressRef.current = true;
    setIsSaving(true);
    setErrorMessage("");

    try {
      const loanRecoveryValue = Number(loanRecovery || 0);
      let loanId = loanRecoveryValue > 0 ? employee.activeLoanId : null;

      if (loanRecoveryValue > 0 && loanId === null && editingId !== null) {
        const { data, error } = await supabase.rpc(
          "get_employee_salary_recovery_for_adda",
          {
            p_salary_record_id: editingId,
            p_adda_id: currentAddaId,
          }
        );

        if (error) throw error;
        const recoveryRows = (data ?? []) as Array<{ loan_id: number | null }>;
        if (recoveryRows.length > 1) {
          throw new Error("EMPLOYEE_SALARY_RECOVERY_LOOKUP_AMBIGUOUS");
        }
        loanId = recoveryRows[0]?.loan_id ?? null;
      }

      if (loanRecoveryValue > 0 && loanId === null) {
        alert(
          employeeSalaryErrorMessage(
            "EMPLOYEE_SALARY_LOAN_NOT_FOUND",
            "Select an active Employee Loan for recovery."
          )
        );
        return;
      }

      const { error } = await supabase.rpc("save_employee_salary", {
        p_id: editingId,
        p_employee_id: employeeId,
        p_salary_month: salaryMonth,
        p_basic_salary: Number(basicSalary || 0),
        p_bonus: Number(bonus || 0),
        p_deduction: Number(deduction || 0),
        p_loan_recovery: loanRecoveryValue,
        p_advance_recovery: Number(advanceRecovery || 0),
        p_paid_amount: Number(paidAmount || 0),
        p_payment_method: paymentMethod,
        p_reference_no: referenceNo.trim() || null,
        p_remarks: remarks.trim() || null,
        p_adda_id: currentAddaId,
        p_loan_id: loanId,
      });

      if (error) {
        console.error("Unable to save salary record:", error);
        alert(
          employeeSalaryErrorMessage(
            error.message,
            editingId !== null
              ? t("employeeSalary.messages.updateFailed")
              : t("employeeSalary.messages.saveFailed")
          )
        );
        return;
      }

      await reloadSalaryData(currentAddaId);
      resetForm();
      alert(
        editingId !== null
          ? t("employeeSalary.messages.updated")
          : t("employeeSalary.messages.saved")
      );
    } catch (error) {
      console.error("Unable to save salary record:", error);
      const message =
        typeof error === "object" && error !== null && "message" in error
          ? String(error.message)
          : String(error);
      alert(
        employeeSalaryErrorMessage(
          message,
          editingId !== null
            ? t("employeeSalary.messages.updateFailed")
            : t("employeeSalary.messages.saveFailed")
        )
      );
    } finally {
      setIsSaving(false);
      saveInProgressRef.current = false;
    }
  }

  function handleEdit(row: EmployeeSalaryRow) {
    setEditingId(row.id);
    setEmployeeId(row.employeeId);
    setSalaryMonth(row.salaryMonth);
    setBasicSalary(String(row.basicSalary || ""));
    setBonus(String(row.bonus || ""));
    setDeduction(String(row.deduction || ""));
    setLoanRecovery(String(row.loanRecovery || ""));
    setAdvanceRecovery(String(row.advanceRecovery || ""));
    setPaidAmount(String(row.paidAmount || ""));
    setPaymentMethod(row.paymentMethod);
    setReferenceNo(row.referenceNo);
    setRemarks(row.remarks);
  }

  async function handleDelete(row: EmployeeSalaryRow) {
    if (deleteInProgressRef.current) return;
    const confirmed = window.confirm(
      `${t("employeeSalary.messages.deleteConfirm")} ${row.employeeName}?`
    );

    if (!confirmed) return;
    if (!currentAddaId) {
      alert(isSuperAdmin ? t("drivers.selectAdda") : t("employeeSalary.messages.loadFailed"));
      return;
    }

    deleteInProgressRef.current = true;
    setIsDeleting(true);
    setErrorMessage("");
    const addaId = currentAddaId;

    try {
      const { error } = await supabase.rpc("delete_employee_salary", {
        p_id: Number(row.id),
        p_adda_id: addaId,
      });

      if (error) {
        console.error("Unable to delete salary record:", error);
        alert(
          employeeSalaryErrorMessage(
            error.message,
            t("employeeSalary.messages.deleteFailed")
          )
        );
        return;
      }

      if (editingId === row.id) resetForm();

      await reloadSalaryData(addaId);
      alert(t("employeeSalary.messages.deleted"));
    } catch (error) {
      console.error("Unable to delete salary record:", error);
      const message =
        typeof error === "object" && error !== null && "message" in error
          ? String(error.message)
          : String(error);
      alert(
        employeeSalaryErrorMessage(
          message,
          t("employeeSalary.messages.deleteFailed")
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
        <ModulePageHeading icon="payment" accent="cyan" title={t("employeeSalary.title")} description={t("employeeSalary.description")} />
      </header>

      {isSuperAdmin && !isContextLoading && (
        <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
          <label
            htmlFor="employee-salary-adda"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Adda
          </label>
          <select
            required
            id="employee-salary-adda"
            name="addaId"
            value={selectedAddaId}
            onChange={(event) => handleAddaChange(event.target.value)}
            disabled={isSaving || isDeleting}
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

      {contextError && (
        <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-700">
          {contextError}
        </p>
      )}

      <EmployeeSalaryCards summary={summary} />

      <EmployeeSalaryForm
        employeeId={employeeId}
        setEmployeeId={setEmployeeId}
        salaryMonth={salaryMonth}
        setSalaryMonth={setSalaryMonth}
        basicSalary={basicSalary}
        setBasicSalary={setBasicSalary}
        bonus={bonus}
        setBonus={setBonus}
        deduction={deduction}
        setDeduction={setDeduction}
        loanRecovery={loanRecovery}
        setLoanRecovery={setLoanRecovery}
        advanceRecovery={advanceRecovery}
        setAdvanceRecovery={setAdvanceRecovery}
        paidAmount={paidAmount}
        setPaidAmount={setPaidAmount}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        referenceNo={referenceNo}
        setReferenceNo={setReferenceNo}
        remarks={remarks}
        setRemarks={setRemarks}
        employees={activeEmployeeOptions}
        selectedEmployee={selectedEmployee}
        onSave={handleSaveSalary}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <EmployeeSalaryTable
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
        methodFilter={methodFilter}
        setMethodFilter={(value) => {
          setMethodFilter(value);
          setPage(1);
        }}
        onResetFilters={() => {
          setSearch("");
          setStatusFilter("All");
          setMethodFilter("All");
          setPage(1);
        }}
        currentPage={currentPage}
        totalPages={totalPages}
        setPage={setPage}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onPrintSlip={setSelectedSlip}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={contextError || errorMessage}
      />

      {selectedSlip && (
        <EmployeeSalarySlip
          row={selectedSlip}
          addaId={currentAddaId}
          onClose={() => setSelectedSlip(null)}
        />
      )}
    </div>
  );
}
