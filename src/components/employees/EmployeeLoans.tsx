"use client";

import { useEffect, useMemo, useState } from "react";
import EmployeeLoanCards from "@/components/employees/EmployeeLoanCards";
import EmployeeLoanForm from "@/components/employees/EmployeeLoanForm";
import EmployeeLoanTable from "@/components/employees/EmployeeLoanTable";
import { supabase } from "@/lib/supabase/client";

export type EmployeeLoanStatus = "Active" | "Completed";

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

type CashbookEntryLookup = {
  id: number | string;
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

export default function EmployeeLoans() {
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
  const [search, setSearch] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

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
        employeeName: employee?.employeeName ?? "Unknown Employee",
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
  }, [employees, loans]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return rows;

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

      return searchableText.includes(keyword);
    });
  }, [rows, search]);

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

  useEffect(() => {
    loadInitialData();
  }, []);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, loansResponse] = await Promise.all([
      supabase
        .from("employees")
        .select("id, employee_name, employee_type")
        .order("employee_name", { ascending: true }),
      supabase
        .from("employee_loans")
        .select(
          `
          id,
          employee_id,
          loan_date,
          loan_amount,
          monthly_installment,
          recovered_amount,
          remaining_amount,
          status,
          reference_no,
          remarks,
          created_at
        `
        )
        .order("id", { ascending: false }),
    ]);

    if (employeesResponse.error) {
      setErrorMessage(employeesResponse.error.message);
      setIsLoading(false);
      return;
    }

    if (loansResponse.error) {
      setErrorMessage(loansResponse.error.message);
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
  }

  async function loadLoans() {
    const { data, error } = await supabase
      .from("employee_loans")
      .select(
        `
        id,
        employee_id,
        loan_date,
        loan_amount,
        monthly_installment,
        recovered_amount,
        remaining_amount,
        status,
        reference_no,
        remarks,
        created_at
      `
      )
      .order("id", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      return;
    }

    setLoans((data ?? []) as EmployeeLoanDbRow[]);
  }

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
      alert("Please select an employee.");
      return false;
    }

    if (!loanDate) {
      alert("Loan Date is required.");
      return false;
    }

    if (!loanAmount || !Number.isFinite(loanValue) || loanValue <= 0) {
      alert("Loan Amount must be greater than zero.");
      return false;
    }

    if (!Number.isFinite(installmentValue) || installmentValue < 0) {
      alert("Monthly Installment cannot be negative.");
      return false;
    }

    if (installmentValue > loanValue) {
      alert("Monthly Installment cannot be greater than Loan Amount.");
      return false;
    }

    if (!paymentMethod) {
      alert("Payment Method is required.");
      return false;
    }

    return true;
  }

  async function syncLoanCashbookEntry(loanId: number, amountValue: number) {
    const employee = employees.find((item) => item.id === employeeId);

    if (!employee) {
      return "Selected employee was not found for Cashbook sync.";
    }

    const { data: existingCashbookEntry, error: lookupError } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "employee_loan")
      .eq("reference_id", String(loanId))
      .maybeSingle();

    if (lookupError) {
      return lookupError.message;
    }

    const cashbookPayload = {
      entry_date: loanDate,
      entry_type: "Cash Out",
      person_type: employee.employeeType === "Driver" ? "Driver" : "Other",
      person_name: employee.employeeName,
      vehicle_id: null,
      driver_id: null,
      loading_id: null,
      payment_method: paymentMethod,
      amount: amountValue,
      description: `Employee loan paid to ${employee.employeeName}`,
      reference_type: "employee_loan",
      reference_id: String(loanId),
    };

    const existingEntry = existingCashbookEntry as CashbookEntryLookup | null;

    if (existingEntry?.id) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(cashbookPayload)
        .eq("id", existingEntry.id);

      return error?.message ?? "";
    }

    const { error } = await supabase
      .from("cashbook_entries")
      .insert(cashbookPayload);

    return error?.message ?? "";
  }

  async function handleSaveLoan() {
    if (!validateForm()) return;

    setIsSaving(true);
    setErrorMessage("");

    const loanValue = Number(loanAmount);
    const installmentValue = Number(monthlyInstallment || 0);
    const now = new Date().toISOString();

    if (editingId) {
      const existingLoan = loans.find((loan) => loan.id === editingId);

      if (!existingLoan) {
        alert("Selected loan record was not found.");
        setIsSaving(false);
        return;
      }

      const recoveredValue = toNumber(existingLoan.recovered_amount);
      const remainingValue = Math.max(loanValue - recoveredValue, 0);
      const statusValue: EmployeeLoanStatus =
        remainingValue <= 0 ? "Completed" : "Active";

      const { error } = await supabase
        .from("employee_loans")
        .update({
          employee_id: employeeId,
          loan_date: loanDate,
          loan_amount: loanValue,
          monthly_installment: installmentValue,
          remaining_amount: remainingValue,
          status: statusValue,
          reference_no: referenceNo.trim() || null,
          remarks: remarks.trim() || null,
          updated_at: now,
        })
        .eq("id", editingId);

      if (error) {
        setIsSaving(false);
        alert(error.message);
        return;
      }

      const cashbookError = await syncLoanCashbookEntry(editingId, loanValue);

      if (cashbookError) {
        alert(`Loan updated, but Cashbook sync failed: ${cashbookError}`);
      } else {
        alert("Employee loan updated successfully!");
      }

      await loadLoans();
      resetForm();
      setIsSaving(false);
      return;
    }

    const { data, error } = await supabase
      .from("employee_loans")
      .insert({
        employee_id: employeeId,
        loan_date: loanDate,
        loan_amount: loanValue,
        monthly_installment: installmentValue,
        recovered_amount: 0,
        remaining_amount: loanValue,
        status: "Active",
        reference_no: referenceNo.trim() || null,
        remarks: remarks.trim() || null,
        updated_at: now,
      })
      .select("id")
      .single();

    if (error) {
      setIsSaving(false);
      alert(error.message);
      return;
    }

    const insertedLoan = data as { id: number };
    const cashbookError = await syncLoanCashbookEntry(
      insertedLoan.id,
      loanValue
    );

    if (cashbookError) {
      alert(`Loan saved, but Cashbook sync failed: ${cashbookError}`);
    } else {
      alert("Employee loan saved successfully!");
    }

    await loadLoans();
    resetForm();
    setIsSaving(false);
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
    const confirmed = window.confirm(
      `Delete loan record for ${row.employeeName}? This will also remove the linked Cashbook entry.`
    );

    if (!confirmed) return;

    setIsDeleting(true);
    setErrorMessage("");

    const { error: cashbookError } = await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "employee_loan")
      .eq("reference_id", String(row.id));

    if (cashbookError) {
      setIsDeleting(false);
      alert(cashbookError.message);
      return;
    }

    const { error } = await supabase
      .from("employee_loans")
      .delete()
      .eq("id", row.id);

    if (error) {
      setIsDeleting(false);
      alert(error.message);
      return;
    }

    if (editingId === row.id) {
      resetForm();
    }

    await loadLoans();
    alert("Employee loan deleted successfully!");
    setIsDeleting(false);
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">
            Employee Loan Management
          </h1>
          <p className="mt-2 text-base font-medium text-gray-900">
            Manage employee loans, monthly installments, balances and Cashbook
            entries.
          </p>
        </div>
      </div>

      <EmployeeLoanCards summary={summary} />

      <EmployeeLoanForm
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
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        onEdit={handleEditLoan}
        onDelete={handleDeleteLoan}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}