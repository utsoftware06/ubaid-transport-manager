"use client";

import { useEffect, useMemo, useState } from "react";
import EmployeeForm from "@/components/employees/EmployeeForm";
import EmployeeCards from "@/components/employees/EmployeeCards";
import EmployeeTable from "@/components/employees/EmployeeTable";
import { supabase } from "@/lib/supabase/client";

export type EmployeeType =
  | "Driver"
  | "Munshi"
  | "Accountant"
  | "Loader"
  | "Office Staff"
  | "Helper"
  | "Cleaner"
  | "Security Guard"
  | "Mechanic"
  | "Other";

export type EmployeeStatus = "Active" | "Inactive";

export type DriverOption = {
  id: string;
  name: string;
};

export type EmployeeRow = {
  id: string;
  employeeName: string;
  employeeType: EmployeeType;
  phone: string;
  cnic: string;
  address: string;
  joiningDate: string;
  monthlySalary: number;
  driverId: string | null;
  driverName: string;
  status: EmployeeStatus;
  totalLoan: number;
  recoveredLoan: number;
  remainingLoan: number;
  totalSalaryGenerated: number;
  totalSalaryPaid: number;
  remainingSalary: number;
  createdAt: string;
};

export type EmployeeSummary = {
  totalEmployees: number;
  activeEmployees: number;
  inactiveEmployees: number;
  totalMonthlySalary: number;
  totalLoan: number;
  recoveredLoan: number;
  remainingLoan: number;
  remainingSalary: number;
};

type RelatedRecord<T> = T | T[] | null;

type DriverRelation = {
  name: string | null;
};

type EmployeeDatabaseRow = {
  id: string;
  employee_name: string | null;
  employee_type: string | null;
  phone: string | null;
  cnic: string | null;
  address: string | null;
  joining_date: string | null;
  monthly_salary: number | string | null;
  driver_id: string | null;
  status: string | null;
  created_at: string | null;
  drivers?: RelatedRecord<DriverRelation>;
};

type LoanDatabaseRow = {
  id: number;
  employee_id: string | null;
  loan_amount: number | string | null;
  recovered_amount: number | string | null;
  remaining_amount: number | string | null;
  status: string | null;
};

type SalaryRecordDatabaseRow = {
  id: number;
  employee_id: string | null;
  net_salary: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
};

const defaultEmployeeType: EmployeeType = "Office Staff";
const defaultStatus: EmployeeStatus = "Active";

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getSingleRelation<T>(relation: RelatedRecord<T> | undefined): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toEmployeeType(value: string | null): EmployeeType {
  if (
    value === "Driver" ||
    value === "Munshi" ||
    value === "Accountant" ||
    value === "Loader" ||
    value === "Office Staff" ||
    value === "Helper" ||
    value === "Cleaner" ||
    value === "Security Guard" ||
    value === "Mechanic" ||
    value === "Other"
  ) {
    return value;
  }

  return defaultEmployeeType;
}

function toEmployeeStatus(value: string | null): EmployeeStatus {
  if (value === "Inactive") return "Inactive";
  return "Active";
}

export default function Employees() {
  const [employeeName, setEmployeeName] = useState("");
  const [employeeType, setEmployeeType] =
    useState<EmployeeType>(defaultEmployeeType);
  const [phone, setPhone] = useState("");
  const [cnic, setCnic] = useState("");
  const [address, setAddress] = useState("");
  const [joiningDate, setJoiningDate] = useState("");
  const [monthlySalary, setMonthlySalary] = useState("");
  const [driverId, setDriverId] = useState("");
  const [status, setStatus] = useState<EmployeeStatus>(defaultStatus);

  const [employees, setEmployees] = useState<EmployeeDatabaseRow[]>([]);
  const [drivers, setDrivers] = useState<DriverOption[]>([]);
  const [loans, setLoans] = useState<LoanDatabaseRow[]>([]);
  const [salaryRecords, setSalaryRecords] = useState<
    SalaryRecordDatabaseRow[]
  >([]);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    loadInitialData();
  }, []);

  useEffect(() => {
    if (employeeType !== "Driver") {
      setDriverId("");
    }
  }, [employeeType]);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    await Promise.all([
      loadEmployees(),
      loadDrivers(),
      loadLoans(),
      loadSalaryRecords(),
    ]);

    setIsLoading(false);
  }

  async function loadEmployees() {
    const { data, error } = await supabase
      .from("employees")
      .select(
        `
        id,
        employee_name,
        employee_type,
        phone,
        cnic,
        address,
        joining_date,
        monthly_salary,
        driver_id,
        status,
        created_at,
        drivers(name)
      `
      )
      .order("employee_name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setEmployees([]);
      return;
    }

    setEmployees((data ?? []) as EmployeeDatabaseRow[]);
  }

  async function loadDrivers() {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .order("name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setDrivers([]);
      return;
    }

    setDrivers(
      (data ?? []).map((driver) => ({
        id: String(driver.id),
        name: driver.name ?? "-",
      }))
    );
  }

  async function loadLoans() {
    const { data, error } = await supabase
      .from("employee_loans")
      .select("id, employee_id, loan_amount, recovered_amount, remaining_amount, status");

    if (error) {
      setErrorMessage(error.message);
      setLoans([]);
      return;
    }

    setLoans((data ?? []) as LoanDatabaseRow[]);
  }

  async function loadSalaryRecords() {
    const { data, error } = await supabase
      .from("employee_salary_records")
      .select("id, employee_id, net_salary, paid_amount, remaining_amount, payment_status");

    if (error) {
      setErrorMessage(error.message);
      setSalaryRecords([]);
      return;
    }

    setSalaryRecords((data ?? []) as SalaryRecordDatabaseRow[]);
  }

  const rows = useMemo<EmployeeRow[]>(() => {
    return employees.map((employee) => {
      const driver = getSingleRelation(employee.drivers);
      const employeeLoans = loans.filter(
        (loan) => loan.employee_id === employee.id
      );
      const employeeSalaryRecords = salaryRecords.filter(
        (salaryRecord) => salaryRecord.employee_id === employee.id
      );

      const totalLoan = employeeLoans.reduce(
        (total, loan) => total + toNumber(loan.loan_amount),
        0
      );
      const recoveredLoan = employeeLoans.reduce(
        (total, loan) => total + toNumber(loan.recovered_amount),
        0
      );
      const remainingLoan = employeeLoans.reduce(
        (total, loan) => total + toNumber(loan.remaining_amount),
        0
      );
      const totalSalaryGenerated = employeeSalaryRecords.reduce(
        (total, salaryRecord) => total + toNumber(salaryRecord.net_salary),
        0
      );
      const totalSalaryPaid = employeeSalaryRecords.reduce(
        (total, salaryRecord) => total + toNumber(salaryRecord.paid_amount),
        0
      );
      const remainingSalary = employeeSalaryRecords.reduce(
        (total, salaryRecord) => total + toNumber(salaryRecord.remaining_amount),
        0
      );

      return {
        id: employee.id,
        employeeName: employee.employee_name ?? "-",
        employeeType: toEmployeeType(employee.employee_type),
        phone: employee.phone ?? "-",
        cnic: employee.cnic ?? "-",
        address: employee.address ?? "-",
        joiningDate: employee.joining_date ?? "",
        monthlySalary: toNumber(employee.monthly_salary),
        driverId: employee.driver_id,
        driverName: driver?.name ?? "-",
        status: toEmployeeStatus(employee.status),
        totalLoan,
        recoveredLoan,
        remainingLoan,
        totalSalaryGenerated,
        totalSalaryPaid,
        remainingSalary,
        createdAt: employee.created_at ?? "",
      };
    });
  }, [employees, loans, salaryRecords]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return rows;

    return rows.filter((row) =>
      [
        row.employeeName,
        row.employeeType,
        row.phone,
        row.cnic,
        row.address,
        row.driverName,
        row.status,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [rows, search]);

  const summary = useMemo<EmployeeSummary>(() => {
    return filteredRows.reduce(
      (total, row) => ({
        totalEmployees: total.totalEmployees + 1,
        activeEmployees:
          total.activeEmployees + (row.status === "Active" ? 1 : 0),
        inactiveEmployees:
          total.inactiveEmployees + (row.status === "Inactive" ? 1 : 0),
        totalMonthlySalary: total.totalMonthlySalary + row.monthlySalary,
        totalLoan: total.totalLoan + row.totalLoan,
        recoveredLoan: total.recoveredLoan + row.recoveredLoan,
        remainingLoan: total.remainingLoan + row.remainingLoan,
        remainingSalary: total.remainingSalary + row.remainingSalary,
      }),
      {
        totalEmployees: 0,
        activeEmployees: 0,
        inactiveEmployees: 0,
        totalMonthlySalary: 0,
        totalLoan: 0,
        recoveredLoan: 0,
        remainingLoan: 0,
        remainingSalary: 0,
      }
    );
  }, [filteredRows]);

  function resetForm() {
    setEmployeeName("");
    setEmployeeType(defaultEmployeeType);
    setPhone("");
    setCnic("");
    setAddress("");
    setJoiningDate("");
    setMonthlySalary("");
    setDriverId("");
    setStatus(defaultStatus);
    setEditingId(null);
  }

  function validateForm() {
    if (!employeeName.trim()) {
      alert("Employee Name is required.");
      return false;
    }

    if (!employeeType) {
      alert("Employee Type is required.");
      return false;
    }

    if (Number(monthlySalary || 0) < 0) {
      alert("Monthly Salary cannot be negative.");
      return false;
    }

    if (!status) {
      alert("Status is required.");
      return false;
    }

    if (employeeType === "Driver" && !driverId) {
      alert("Driver selection is required for Driver employee type.");
      return false;
    }

    if (employeeType === "Driver" && driverId) {
      const linkedEmployee = rows.find(
        (row) => row.driverId === driverId && row.id !== editingId
      );

      if (linkedEmployee) {
        alert(
          `This driver is already linked with employee ${linkedEmployee.employeeName}.`
        );
        return false;
      }
    }

    return true;
  }

  async function handleSave() {
    if (!validateForm()) return;

    setIsSaving(true);

    const payload = {
      employee_name: employeeName.trim(),
      employee_type: employeeType,
      phone: phone.trim(),
      cnic: cnic.trim(),
      address: address.trim(),
      joining_date: joiningDate || null,
      monthly_salary: Number(monthlySalary || 0),
      driver_id: employeeType === "Driver" ? driverId : null,
      status,
      updated_at: new Date().toISOString(),
    };

    const result = editingId
      ? await supabase.from("employees").update(payload).eq("id", editingId)
      : await supabase.from("employees").insert(payload);

    setIsSaving(false);

    if (result.error) {
      alert(result.error.message);
      return;
    }

    alert(editingId ? "Employee updated successfully!" : "Employee saved successfully!");
    resetForm();
    await loadInitialData();
  }

  function handleEdit(row: EmployeeRow) {
    setEditingId(row.id);
    setEmployeeName(row.employeeName === "-" ? "" : row.employeeName);
    setEmployeeType(row.employeeType);
    setPhone(row.phone === "-" ? "" : row.phone);
    setCnic(row.cnic === "-" ? "" : row.cnic);
    setAddress(row.address === "-" ? "" : row.address);
    setJoiningDate(row.joiningDate ?? "");
    setMonthlySalary(String(row.monthlySalary));
    setDriverId(row.driverId ?? "");
    setStatus(row.status);
  }

  async function handleDelete(row: EmployeeRow) {
    const employeeLoans = loans.filter((loan) => loan.employee_id === row.id);
    const employeeSalaryRecords = salaryRecords.filter(
      (salaryRecord) => salaryRecord.employee_id === row.id
    );

    if (employeeLoans.length > 0) {
      alert("This employee cannot be deleted because loan records are linked.");
      return;
    }

    if (employeeSalaryRecords.length > 0) {
      alert("This employee cannot be deleted because salary records are linked.");
      return;
    }

    const confirmed = window.confirm(`Delete employee ${row.employeeName}?`);

    if (!confirmed) return;

    setIsDeleting(true);

    const { error } = await supabase
      .from("employees")
      .delete()
      .eq("id", row.id);

    setIsDeleting(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (editingId === row.id) resetForm();

    alert("Employee deleted successfully!");
    await loadInitialData();
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Employee Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Manage drivers and adda staff, salaries, loans and employee records.
        </p>
      </div>

      <EmployeeCards summary={summary} />

      <EmployeeForm
        employeeName={employeeName}
        setEmployeeName={setEmployeeName}
        employeeType={employeeType}
        setEmployeeType={setEmployeeType}
        phone={phone}
        setPhone={setPhone}
        cnic={cnic}
        setCnic={setCnic}
        address={address}
        setAddress={setAddress}
        joiningDate={joiningDate}
        setJoiningDate={setJoiningDate}
        monthlySalary={monthlySalary}
        setMonthlySalary={setMonthlySalary}
        driverId={driverId}
        setDriverId={setDriverId}
        status={status}
        setStatus={setStatus}
        drivers={drivers}
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <EmployeeTable
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}