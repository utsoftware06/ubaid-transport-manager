"use client";

import { useEffect, useMemo, useState } from "react";
import EmployeeSalaryCards from "@/components/employees/EmployeeSalaryCards";
import EmployeeSalaryForm from "@/components/employees/EmployeeSalaryForm";
import EmployeeSalarySlip from "@/components/employees/EmployeeSalarySlip";
import EmployeeSalaryTable from "@/components/employees/EmployeeSalaryTable";
import { supabase } from "@/lib/supabase/client";

export type SalaryPaymentStatus = "Paid" | "Partial" | "Unpaid";

export type SalaryPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer"
  | "Account";

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
  monthly_installment: number | string | null;
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

type EmployeeTransactionLookup = {
  id: number;
  loan_id: number | null;
  amount: number | string | null;
};

type CashbookLookup = {
  id: number | string;
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

function calculatePaymentStatus(
  paidAmount: number,
  netSalary: number
): SalaryPaymentStatus {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= netSalary) return "Paid";
  return "Partial";
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

export default function EmployeeSalary() {
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
  const [editingId, setEditingId] = useState<number | null>(null);
  const [selectedSlip, setSelectedSlip] = useState<EmployeeSalaryRow | null>(
    null
  );
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  const employeeOptions = useMemo<EmployeeSalaryOption[]>(() => {
    return employees.map((employee) => {
      const activeLoan = loans.find(
        (loan) =>
          loan.employee_id === employee.id &&
          loan.status !== "Completed" &&
          toNumber(loan.remaining_amount) > 0
      );

      return {
        id: employee.id,
        employeeName: employee.employee_name ?? "",
        employeeType: employee.employee_type ?? "",
        monthlySalary: toNumber(employee.monthly_salary),
        status: employee.status ?? "Active",
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
        employeeName: employee?.employeeName ?? "Unknown Employee",
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
  }, [employeeOptions, salaryRecords]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return rows;

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

      return searchableText.includes(keyword);
    });
  }, [rows, search]);

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
    loadInitialData();
  }, []);

  useEffect(() => {
    if (!employeeId || editingId) return;

    const employee = employeeOptions.find((item) => item.id === employeeId);

    if (!employee) return;

    setBasicSalary(String(employee.monthlySalary || ""));
    setLoanRecovery(
      String(
        Math.min(employee.monthlyInstallment, employee.activeLoanRemaining) || ""
      )
    );
  }, [employeeId, employeeOptions, editingId]);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    const [employeesResponse, loansResponse, salaryResponse] = await Promise.all([
      supabase
        .from("employees")
        .select("id, employee_name, employee_type, monthly_salary, status")
        .order("employee_name", { ascending: true }),
      supabase
        .from("employee_loans")
        .select(
          "id, employee_id, loan_amount, monthly_installment, recovered_amount, remaining_amount, status"
        )
        .order("id", { ascending: true }),
      supabase
        .from("employee_salary_records")
        .select(
          "id, employee_id, salary_month, basic_salary, bonus, deduction, loan_recovery, advance_recovery, net_salary, paid_amount, remaining_amount, payment_status, payment_method, reference_no, remarks, created_at"
        )
        .order("salary_month", { ascending: false })
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

    if (salaryResponse.error) {
      setErrorMessage(salaryResponse.error.message);
      setIsLoading(false);
      return;
    }

    setEmployees((employeesResponse.data ?? []) as EmployeeDbRow[]);
    setLoans((loansResponse.data ?? []) as EmployeeLoanDbRow[]);
    setSalaryRecords((salaryResponse.data ?? []) as SalaryRecordDbRow[]);
    setIsLoading(false);
  }

  async function reloadSalaryData() {
    const [loansResponse, salaryResponse] = await Promise.all([
      supabase
        .from("employee_loans")
        .select(
          "id, employee_id, loan_amount, monthly_installment, recovered_amount, remaining_amount, status"
        )
        .order("id", { ascending: true }),
      supabase
        .from("employee_salary_records")
        .select(
          "id, employee_id, salary_month, basic_salary, bonus, deduction, loan_recovery, advance_recovery, net_salary, paid_amount, remaining_amount, payment_status, payment_method, reference_no, remarks, created_at"
        )
        .order("salary_month", { ascending: false })
        .order("id", { ascending: false }),
    ]);

    if (loansResponse.error) {
      setErrorMessage(loansResponse.error.message);
      return;
    }

    if (salaryResponse.error) {
      setErrorMessage(salaryResponse.error.message);
      return;
    }

    setLoans((loansResponse.data ?? []) as EmployeeLoanDbRow[]);
    setSalaryRecords((salaryResponse.data ?? []) as SalaryRecordDbRow[]);
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
      alert("Please select an employee.");
      return false;
    }

    if (!salaryMonth) {
      alert("Salary Month is required.");
      return false;
    }

    if (basic < 0 || bonusValue < 0 || deductionValue < 0) {
      alert("Basic salary, bonus and deduction cannot be negative.");
      return false;
    }

    if (loanRecoveryValue < 0 || advanceRecoveryValue < 0) {
      alert("Loan recovery and advance recovery cannot be negative.");
      return false;
    }

    if (net < 0) {
      alert("Net salary cannot be negative.");
      return false;
    }

    if (paidValue < 0) {
      alert("Paid amount cannot be negative.");
      return false;
    }

    if (paidValue > net) {
      alert("Paid amount cannot be greater than net salary.");
      return false;
    }

    if (paidValue > 0 && !paymentMethod) {
      alert("Payment method is required when paid amount is greater than zero.");
      return false;
    }

    const duplicate = salaryRecords.find(
      (record) =>
        record.employee_id === employeeId &&
        record.salary_month === salaryMonth &&
        record.id !== editingId
    );

    if (duplicate) {
      alert("Salary record already exists for this employee and salary month.");
      return false;
    }

    return true;
  }

  async function upsertEmployeeTransaction(params: {
    salaryRecordId: number;
    employeeIdValue: string;
    transactionDate: string;
    transactionType: string;
    amountValue: number;
    paymentMethodValue: SalaryPaymentMethod | null;
    referenceNoValue: string;
    descriptionValue: string;
    remarksValue: string;
    referenceType: string;
    loanIdValue?: number | null;
  }) {
    await supabase
      .from("employee_transactions")
      .delete()
      .eq("reference_type", params.referenceType)
      .eq("reference_id", String(params.salaryRecordId));

    if (params.amountValue <= 0) return "";

    const { error } = await supabase.from("employee_transactions").insert({
      employee_id: params.employeeIdValue,
      transaction_date: params.transactionDate,
      transaction_type: params.transactionType,
      amount: params.amountValue,
      payment_method: params.paymentMethodValue,
      reference_no: params.referenceNoValue || null,
      description: params.descriptionValue,
      remarks: params.remarksValue || null,
      salary_record_id: params.salaryRecordId,
      loan_id: params.loanIdValue ?? null,
      reference_type: params.referenceType,
      reference_id: String(params.salaryRecordId),
    });

    return error?.message ?? "";
  }

  async function syncSalaryCashbook(params: {
    salaryRecordId: number;
    employee: EmployeeSalaryOption;
    salaryMonthValue: string;
    paidValue: number;
    paymentMethodValue: SalaryPaymentMethod;
  }) {
    const { data, error: lookupError } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "employee_salary")
      .eq("reference_id", String(params.salaryRecordId))
      .maybeSingle();

    if (lookupError) return lookupError.message;

    const existing = data as CashbookLookup | null;

    if (params.paidValue <= 0) {
      if (existing?.id) {
        const { error } = await supabase
          .from("cashbook_entries")
          .delete()
          .eq("id", existing.id);

        return error?.message ?? "";
      }

      return "";
    }

    const payload = {
      entry_date: params.salaryMonthValue,
      entry_type: "Cash Out",
      person_type: params.employee.employeeType === "Driver" ? "Driver" : "Other",
      person_name: params.employee.employeeName,
      vehicle_id: null,
      driver_id: null,
      loading_id: null,
      payment_method: params.paymentMethodValue,
      amount: params.paidValue,
      description: `Salary payment to ${params.employee.employeeName} for ${params.salaryMonthValue}`,
      reference_type: "employee_salary",
      reference_id: String(params.salaryRecordId),
    };

    if (existing?.id) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(payload)
        .eq("id", existing.id);

      return error?.message ?? "";
    }

    const { error } = await supabase.from("cashbook_entries").insert(payload);
    return error?.message ?? "";
  }

  async function reverseOldLoanRecovery(salaryRecordId: number) {
    const { data, error } = await supabase
      .from("employee_transactions")
      .select("id, loan_id, amount")
      .eq("reference_type", "salary_loan_recovery")
      .eq("reference_id", String(salaryRecordId))
      .maybeSingle();

    if (error) return error.message;

    const transaction = data as EmployeeTransactionLookup | null;

    if (!transaction?.loan_id) return "";

    const oldAmount = toNumber(transaction.amount);
    const oldLoan = loans.find((loan) => loan.id === transaction.loan_id);

    if (!oldLoan) return "";

    const recovered = Math.max(toNumber(oldLoan.recovered_amount) - oldAmount, 0);
    const remaining = toNumber(oldLoan.remaining_amount) + oldAmount;

    const { error: updateError } = await supabase
      .from("employee_loans")
      .update({
        recovered_amount: recovered,
        remaining_amount: remaining,
        status: remaining <= 0 ? "Completed" : "Active",
      })
      .eq("id", oldLoan.id);

    if (updateError) return updateError.message;

    const { error: deleteError } = await supabase
      .from("employee_transactions")
      .delete()
      .eq("id", transaction.id);

    return deleteError?.message ?? "";
  }

  async function applyLoanRecovery(params: {
    salaryRecordId: number;
    employee: EmployeeSalaryOption;
    recoveryAmount: number;
    salaryMonthValue: string;
    referenceNoValue: string;
    remarksValue: string;
  }) {
    if (params.recoveryAmount <= 0) return "";

    if (!params.employee.activeLoanId) {
      return "No active employee loan found for loan recovery.";
    }

    const loan = loans.find((item) => item.id === params.employee.activeLoanId);

    if (!loan) {
      return "Selected active loan was not found.";
    }

    if (params.recoveryAmount > toNumber(loan.remaining_amount)) {
      return "Loan recovery cannot exceed active loan remaining amount.";
    }

    const recovered = toNumber(loan.recovered_amount) + params.recoveryAmount;
    const remaining = Math.max(toNumber(loan.remaining_amount) - params.recoveryAmount, 0);

    const { error } = await supabase
      .from("employee_loans")
      .update({
        recovered_amount: recovered,
        remaining_amount: remaining,
        status: remaining <= 0 ? "Completed" : "Active",
      })
      .eq("id", loan.id);

    if (error) return error.message;

    return upsertEmployeeTransaction({
      salaryRecordId: params.salaryRecordId,
      employeeIdValue: params.employee.id,
      transactionDate: params.salaryMonthValue,
      transactionType: "Loan Recovery",
      amountValue: params.recoveryAmount,
      paymentMethodValue: null,
      referenceNoValue: params.referenceNoValue,
      descriptionValue: `Loan recovery from salary of ${params.employee.employeeName}`,
      remarksValue: params.remarksValue,
      referenceType: "salary_loan_recovery",
      loanIdValue: loan.id,
    });
  }

  async function handleSaveSalary() {
    if (!validateForm()) return;

    const employee = selectedEmployee;

    if (!employee) {
      alert("Selected employee was not found.");
      return;
    }

    setIsSaving(true);
    setErrorMessage("");

    const basic = Number(basicSalary || 0);
    const bonusValue = Number(bonus || 0);
    const deductionValue = Number(deduction || 0);
    const loanRecoveryValue = Number(loanRecovery || 0);
    const advanceRecoveryValue = Number(advanceRecovery || 0);
    const net = getNetSalary(
      basic,
      bonusValue,
      deductionValue,
      loanRecoveryValue,
      advanceRecoveryValue
    );
    const paid = Number(paidAmount || 0);
    const remaining = Math.max(net - paid, 0);
    const paymentStatus = calculatePaymentStatus(paid, net);
    const now = new Date().toISOString();

    if (editingId) {
      const reverseError = await reverseOldLoanRecovery(editingId);

      if (reverseError) {
        setIsSaving(false);
        alert(reverseError);
        return;
      }

      const { error } = await supabase
        .from("employee_salary_records")
        .update({
          employee_id: employeeId,
          salary_month: salaryMonth,
          basic_salary: basic,
          bonus: bonusValue,
          deduction: deductionValue,
          loan_recovery: loanRecoveryValue,
          advance_recovery: advanceRecoveryValue,
          net_salary: net,
          paid_amount: paid,
          remaining_amount: remaining,
          payment_status: paymentStatus,
          payment_method: paid > 0 ? paymentMethod : null,
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

      const loanError = await applyLoanRecovery({
        salaryRecordId: editingId,
        employee,
        recoveryAmount: loanRecoveryValue,
        salaryMonthValue: salaryMonth,
        referenceNoValue: referenceNo,
        remarksValue: remarks,
      });

      const generatedError = await upsertEmployeeTransaction({
        salaryRecordId: editingId,
        employeeIdValue: employee.id,
        transactionDate: salaryMonth,
        transactionType: "Salary Generated",
       amountValue: basic + bonusValue - deductionValue,
        paymentMethodValue: null,
        referenceNoValue: referenceNo,
        descriptionValue: `Salary generated for ${employee.employeeName}`,
        remarksValue: remarks,
        referenceType: "employee_salary_generated",
      });

      const paidError = await upsertEmployeeTransaction({
        salaryRecordId: editingId,
        employeeIdValue: employee.id,
        transactionDate: salaryMonth,
        transactionType: "Salary Paid",
        amountValue: paid,
        paymentMethodValue: paymentMethod,
        referenceNoValue: referenceNo,
        descriptionValue: `Salary paid to ${employee.employeeName}`,
        remarksValue: remarks,
        referenceType: "employee_salary_paid",
      });

      const cashbookError = await syncSalaryCashbook({
        salaryRecordId: editingId,
        employee,
        salaryMonthValue: salaryMonth,
        paidValue: paid,
        paymentMethodValue: paymentMethod,
      });

      const syncError = loanError || generatedError || paidError || cashbookError;

      if (syncError) {
        alert(`Salary updated, but sync failed: ${syncError}`);
      } else {
        alert("Salary updated successfully!");
      }

      await reloadSalaryData();
      resetForm();
      setIsSaving(false);
      return;
    }

    const { data, error } = await supabase
      .from("employee_salary_records")
      .insert({
        employee_id: employeeId,
        salary_month: salaryMonth,
        basic_salary: basic,
        bonus: bonusValue,
        deduction: deductionValue,
        loan_recovery: loanRecoveryValue,
        advance_recovery: advanceRecoveryValue,
        net_salary: net,
        paid_amount: paid,
        remaining_amount: remaining,
        payment_status: paymentStatus,
        payment_method: paid > 0 ? paymentMethod : null,
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

    const salaryRecord = data as { id: number };

    const loanError = await applyLoanRecovery({
      salaryRecordId: salaryRecord.id,
      employee,
      recoveryAmount: loanRecoveryValue,
      salaryMonthValue: salaryMonth,
      referenceNoValue: referenceNo,
      remarksValue: remarks,
    });

    const generatedError = await upsertEmployeeTransaction({
      salaryRecordId: salaryRecord.id,
      employeeIdValue: employee.id,
      transactionDate: salaryMonth,
      transactionType: "Salary Generated",
     amountValue: basic + bonusValue - deductionValue,
      paymentMethodValue: null,
      referenceNoValue: referenceNo,
      descriptionValue: `Salary generated for ${employee.employeeName}`,
      remarksValue: remarks,
      referenceType: "employee_salary_generated",
    });

    const paidError = await upsertEmployeeTransaction({
      salaryRecordId: salaryRecord.id,
      employeeIdValue: employee.id,
      transactionDate: salaryMonth,
      transactionType: "Salary Paid",
      amountValue: paid,
      paymentMethodValue: paymentMethod,
      referenceNoValue: referenceNo,
      descriptionValue: `Salary paid to ${employee.employeeName}`,
      remarksValue: remarks,
      referenceType: "employee_salary_paid",
    });

    const cashbookError = await syncSalaryCashbook({
      salaryRecordId: salaryRecord.id,
      employee,
      salaryMonthValue: salaryMonth,
      paidValue: paid,
      paymentMethodValue: paymentMethod,
    });

    const syncError = loanError || generatedError || paidError || cashbookError;

    if (syncError) {
      alert(`Salary saved, but sync failed: ${syncError}`);
    } else {
      alert("Salary saved successfully!");
    }

    await reloadSalaryData();
    resetForm();
    setIsSaving(false);
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
    const confirmed = window.confirm(
      `Delete salary record for ${row.employeeName}?`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    const reverseError = await reverseOldLoanRecovery(row.id);

    if (reverseError) {
      setIsDeleting(false);
      alert(reverseError);
      return;
    }

    await supabase
      .from("employee_transactions")
      .delete()
      .eq("salary_record_id", row.id);

    await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "employee_salary")
      .eq("reference_id", String(row.id));

    const { error } = await supabase
      .from("employee_salary_records")
      .delete()
      .eq("id", row.id);

    if (error) {
      setIsDeleting(false);
      alert(error.message);
      return;
    }

    if (editingId === row.id) resetForm();

    await reloadSalaryData();
    alert("Salary record deleted successfully!");
    setIsDeleting(false);
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Employee Salary Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Generate salaries, recover loans, record payments and print salary
          slips.
        </p>
      </div>

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
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onPrintSlip={setSelectedSlip}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />

      {selectedSlip && (
        <EmployeeSalarySlip
          row={selectedSlip}
          onClose={() => setSelectedSlip(null)}
        />
      )}
    </div>
  );
}