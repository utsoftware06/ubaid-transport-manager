"use client";

import { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import EmployeeForm from "@/components/employees/EmployeeForm";
import EmployeeCards from "@/components/employees/EmployeeCards";
import EmployeeDetails from "@/components/employees/EmployeeDetails";
import EmployeeTable from "@/components/employees/EmployeeTable";
import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
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
  updated_at: string | null;
  adda_id: string | null;
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

type EmployeeProfileContext = {
  role: string | null;
  adda_id: string | null;
  is_active: boolean | null;
};

type AddaOption = {
  id: string;
  name: string;
};

const defaultEmployeeType: EmployeeType = "Office Staff";
const defaultStatus: EmployeeStatus = "Active";
const employeePageSize = 10;

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
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

function employeeSaveErrorMessage(message: string, fallback: string) {
  const normalized = message.toUpperCase();
  if (normalized.includes("HISTORICAL_EMPLOYEE_ADDA_UNASSIGNED")) {
    return "This historical employee has no assigned Adda and cannot be edited.";
  }
  if (normalized.includes("EMPLOYEE_DRIVER_ADDA_MISMATCH")) {
    return "The selected Driver belongs to a different Adda.";
  }
  if (normalized.includes("EMPLOYEE_DRIVER_ALREADY_LINKED")) {
    return "This Driver is already linked to another employee.";
  }
  if (normalized.includes("EMPLOYEE_ACCOUNTING_IDENTITY_CHANGE_BLOCKED")) {
    return "Employee type or Driver cannot be changed after loan, salary, or transaction history exists.";
  }
  if (normalized.includes("EMPLOYEE_DRIVER_ADDA_UNASSIGNED")) {
    return "The selected Driver has no assigned Adda.";
  }
  if (normalized.includes("EMPLOYEE_DRIVER_NOT_FOUND")) {
    return "The selected Driver could not be found. Refresh the list and try again.";
  }
  if (normalized.includes("EMPLOYEE_ADDA_MISMATCH")) {
    return "This employee belongs to a different Adda.";
  }
  if (normalized.includes("EMPLOYEE_ADDA_UNRESOLVED")) {
    return "Select a valid Adda and try again.";
  }
  return fallback;
}

function employeeDeleteErrorMessage(message: string, fallback: string) {
  const normalized = message.toUpperCase();
  if (normalized.includes("EMPLOYEE_NOT_FOUND")) {
    return "This employee no longer exists. Refresh the list and try again.";
  }
  if (normalized.includes("HISTORICAL_EMPLOYEE_ADDA_UNASSIGNED")) {
    return "This historical employee has no assigned Adda and cannot be deleted.";
  }
  if (normalized.includes("EMPLOYEE_ADDA_MISMATCH")) {
    return "This employee belongs to a different Adda.";
  }
  if (normalized.includes("EMPLOYEE_HAS_ACCOUNTING_HISTORY")) {
    return "This employee cannot be deleted because loan, salary, or transaction records are linked.";
  }
  return fallback;
}

export default function Employees() {
  const { t, dir } = useLanguage();
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
  const [driversAddaId, setDriversAddaId] = useState<string | null>(null);
  const [loans, setLoans] = useState<LoanDatabaseRow[]>([]);
  const [salaryRecords, setSalaryRecords] = useState<
    SalaryRecordDatabaseRow[]
  >([]);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [viewingEmployee, setViewingEmployee] = useState<EmployeeRow | null>(
    null
  );
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState<EmployeeType | "All">("All");
  const [statusFilter, setStatusFilter] = useState<EmployeeStatus | "All">(
    "All"
  );
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [isSaveContextLoading, setIsSaveContextLoading] = useState(true);
  const [saveContextError, setSaveContextError] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);
  const loadRequestIdRef = useRef(0);

  useEffect(() => {
    let isMounted = true;

    async function loadSaveContext() {
      setIsSaveContextLoading(true);
      setSaveContextError("");
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
        console.error("Unable to load Employee save context:", error);
        setSaveContextError(t("employees.messages.loadFailed"));
      } finally {
        if (isMounted) setIsSaveContextLoading(false);
      }
    }

    void loadSaveContext();
    return () => {
      isMounted = false;
    };
  }, [t]);

  async function loadEmployees(addaId: string, requestId: number) {
    const { data, error } = await supabase.rpc("get_employees", {
      p_adda_id: addaId,
    });

    if (requestId !== loadRequestIdRef.current) return;
    if (error) {
      console.error("Unable to load employees:", error);
      setErrorMessage(t("employees.messages.loadFailed"));
      setEmployees([]);
      return;
    }

    setEmployees((data ?? []) as EmployeeDatabaseRow[]);
  }

  async function loadDrivers(addaId: string, requestId: number) {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .eq("adda_id", addaId)
      .order("name", { ascending: true });

    if (requestId !== loadRequestIdRef.current) return;
    if (error) {
      console.error("Unable to load employee drivers:", error);
      setErrorMessage(t("employees.messages.loadFailed"));
      setDrivers([]);
      setDriversAddaId(null);
      return;
    }

    setDrivers(
      (data ?? []).map((driver) => ({
        id: String(driver.id),
        name: driver.name ?? "-",
      }))
    );
    setDriversAddaId(addaId);
  }

  async function loadLoans(addaId: string, requestId: number) {
    const { data, error } = await supabase.rpc(
      "get_employee_loans_for_adda",
      { p_adda_id: addaId }
    );

    if (requestId !== loadRequestIdRef.current) return;
    if (error) {
      console.error("Unable to load employee loan summaries:", error);
      setErrorMessage(t("employees.messages.loadFailed"));
      setLoans([]);
      return;
    }

    setLoans((data ?? []) as LoanDatabaseRow[]);
  }

  async function loadSalaryRecords(addaId: string, requestId: number) {
    const { data, error } = await supabase.rpc(
      "get_employee_salary_records_for_adda",
      { p_adda_id: addaId }
    );

    if (requestId !== loadRequestIdRef.current) return;
    if (error) {
      console.error("Unable to load employee salary summaries:", error);
      setErrorMessage(t("employees.messages.loadFailed"));
      setSalaryRecords([]);
      return;
    }

    setSalaryRecords((data ?? []) as SalaryRecordDatabaseRow[]);
  }

  async function loadInitialData(addaId: string) {
    const requestId = ++loadRequestIdRef.current;
    setIsLoading(true);
    setErrorMessage("");

    try {
      await Promise.all([
        loadEmployees(addaId, requestId),
        loadDrivers(addaId, requestId),
        loadLoans(addaId, requestId),
        loadSalaryRecords(addaId, requestId),
      ]);
    } catch (error) {
      if (requestId === loadRequestIdRef.current) {
        console.error("Unable to load employee data:", error);
        setErrorMessage(t("employees.messages.loadFailed"));
      }
    } finally {
      if (requestId === loadRequestIdRef.current) setIsLoading(false);
    }
  }

  const loadInitialDataEvent = useEffectEvent(loadInitialData);

  useEffect(() => {
    if (isSaveContextLoading) return;

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (saveContextError || !addaId) {
      const message = saveContextError;
      const clearTimer = window.setTimeout(() => {
        loadRequestIdRef.current += 1;
        setEmployees([]);
        setDrivers([]);
        setDriversAddaId(null);
        setLoans([]);
        setSalaryRecords([]);
        setErrorMessage(message);
        setIsLoading(false);
      }, 0);
      return () => window.clearTimeout(clearTimer);
    }

    const loadTimer = window.setTimeout(() => {
      void loadInitialDataEvent(addaId);
    }, 0);

    return () => window.clearTimeout(loadTimer);
  }, [isSaveContextLoading, saveContextError, isSuperAdmin, profileAddaId, selectedAddaId]);

  const currentAddaId = isSuperAdmin ? selectedAddaId : profileAddaId;
  const currentDrivers = useMemo(
    () => (driversAddaId === currentAddaId ? drivers : []),
    [driversAddaId, currentAddaId, drivers]
  );

  const rows = useMemo<EmployeeRow[]>(() => {
    return employees
      .filter((employee) => employee.adda_id === currentAddaId)
      .map((employee) => {
        const driver = currentDrivers.find(
          (option) => option.id === employee.driver_id
        );
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
  }, [employees, currentAddaId, currentDrivers, loans, salaryRecords]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return rows.filter((row) => {
      const matchesSearch =
        !keyword ||
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
          .includes(keyword);
      const matchesType =
        typeFilter === "All" || row.employeeType === typeFilter;
      const matchesStatus =
        statusFilter === "All" || row.status === statusFilter;

      return matchesSearch && matchesType && matchesStatus;
    });
  }, [rows, search, statusFilter, typeFilter]);

  const totalPages = Math.max(
    1,
    Math.ceil(filteredRows.length / employeePageSize)
  );
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const paginatedRows = useMemo(
    () =>
      filteredRows.slice(
        (currentPage - 1) * employeePageSize,
        currentPage * employeePageSize
      ),
    [currentPage, filteredRows]
  );

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

  function handleEmployeeAddaChange(value: string) {
    loadRequestIdRef.current += 1;
    setSelectedAddaId(value);
    setEmployees([]);
    setDrivers([]);
    setDriversAddaId(null);
    setIsLoading(Boolean(value));
  }

  function handleEmployeeTypeChange(value: EmployeeType) {
    setEmployeeType(value);
    if (value !== "Driver") {
      setDriverId("");
    }
  }

  function handleSearchChange(value: string) {
    setSearch(value);
    setPage(1);
  }

  function handleTypeFilterChange(value: EmployeeType | "All") {
    setTypeFilter(value);
    setPage(1);
  }

  function handleStatusFilterChange(value: EmployeeStatus | "All") {
    setStatusFilter(value);
    setPage(1);
  }

  function resetFilters() {
    setSearch("");
    setTypeFilter("All");
    setStatusFilter("All");
    setPage(1);
  }

  function validateForm() {
    if (!employeeName.trim()) {
      alert(t("employees.validation.nameRequired"));
      return false;
    }

    if (!employeeType) {
      alert(t("employees.validation.typeRequired"));
      return false;
    }

    const salaryValue = Number(monthlySalary || 0);
    if (!Number.isFinite(salaryValue) || salaryValue < 0) {
      alert(t("employees.validation.salaryNonNegative"));
      return false;
    }

    if (!status) {
      alert(t("employees.validation.statusRequired"));
      return false;
    }

    if (employeeType === "Driver" && !driverId) {
      alert(t("employees.validation.driverRequired"));
      return false;
    }

    if (employeeType === "Driver" && driverId) {
      const linkedEmployee = rows.find(
        (row) => row.driverId === driverId && row.id !== editingId
      );

      if (linkedEmployee) {
        alert(
          `${t("employees.validation.driverAlreadyLinked")} ${linkedEmployee.employeeName}.`
        );
        return false;
      }
    }

    return true;
  }

  async function handleSave() {
    if (saveInProgressRef.current) return;
    if (!validateForm()) return;

    if (isSaveContextLoading || saveContextError) {
      alert(saveContextError || t("employees.messages.loadFailed"));
      return;
    }

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (!addaId) {
      alert(isSuperAdmin ? t("drivers.selectAdda") : t("employees.messages.loadFailed"));
      return;
    }

    saveInProgressRef.current = true;
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
    };

    try {
      const { error } = await supabase.rpc("save_employee", {
        p_employee_name: payload.employee_name,
        p_employee_type: payload.employee_type,
        p_phone: payload.phone,
        p_cnic: payload.cnic,
        p_address: payload.address,
        p_joining_date: payload.joining_date,
        p_monthly_salary: payload.monthly_salary,
        p_driver_id: payload.driver_id,
        p_status: payload.status,
        p_adda_id: addaId,
        p_id: editingId,
      });

      if (error) {
        console.error("Unable to save employee:", error);
        alert(employeeSaveErrorMessage(error.message, t("employees.messages.saveFailed")));
        return;
      }

      alert(
        editingId
          ? t("employees.messages.updated")
          : t("employees.messages.saved")
      );
      resetForm();
      await loadInitialData(addaId);
    } catch (error) {
      console.error("Unable to save employee:", error);
      alert(t("employees.messages.saveFailed"));
    } finally {
      saveInProgressRef.current = false;
      setIsSaving(false);
    }
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
    if (deleteInProgressRef.current) return;

    const employeeLoans = loans.filter((loan) => loan.employee_id === row.id);
    const employeeSalaryRecords = salaryRecords.filter(
      (salaryRecord) => salaryRecord.employee_id === row.id
    );

    if (employeeLoans.length > 0) {
      alert(t("employees.messages.deleteLoanLinked"));
      return;
    }

    if (employeeSalaryRecords.length > 0) {
      alert(t("employees.messages.deleteSalaryLinked"));
      return;
    }

    const confirmed = window.confirm(
      `${t("employees.messages.deleteConfirm")} ${row.employeeName}?`
    );

    if (!confirmed) return;

    if (isSaveContextLoading || saveContextError) {
      alert(saveContextError || t("employees.messages.loadFailed"));
      return;
    }

    const addaId = isSuperAdmin ? selectedAddaId : profileAddaId;
    if (!addaId) {
      alert(isSuperAdmin ? t("drivers.selectAdda") : t("employees.messages.loadFailed"));
      return;
    }

    deleteInProgressRef.current = true;
    setIsDeleting(true);

    try {
      const { error } = await supabase.rpc("delete_employee", {
        p_id: row.id,
        p_adda_id: addaId,
      });

      if (error) {
        console.error("Unable to delete employee:", error);
        alert(employeeDeleteErrorMessage(error.message, t("employees.messages.deleteFailed")));
        return;
      }

      if (editingId === row.id) resetForm();

      alert(t("employees.messages.deleted"));
      await loadInitialData(addaId);
    } catch (error) {
      console.error("Unable to delete employee:", error);
      const message = error instanceof Error ? error.message : String(error);
      alert(employeeDeleteErrorMessage(message, t("employees.messages.deleteFailed")));
    } finally {
      deleteInProgressRef.current = false;
      setIsDeleting(false);
    }
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="employee" accent="cyan" title={t("employees.title")} description={t("employees.description")} />
      </header>

      <EmployeeCards summary={summary} />

      <EmployeeForm
        contextKey={editingId ?? `new:${selectedAddaId}`}
        employeeName={employeeName}
        setEmployeeName={setEmployeeName}
        employeeType={employeeType}
        setEmployeeType={handleEmployeeTypeChange}
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
        addaId={selectedAddaId}
        setAddaId={handleEmployeeAddaChange}
        addas={addas}
        isSuperAdmin={isSuperAdmin}
        isSaveContextLoading={isSaveContextLoading}
        isSaveDisabled={Boolean(saveContextError)}
        drivers={drivers}
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      {saveContextError && (
        <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-700">
          {saveContextError}
        </p>
      )}

      <EmployeeTable
        addaId={currentAddaId}
        rows={paginatedRows}
        reportRows={filteredRows}
        search={search}
        setSearch={handleSearchChange}
        typeFilter={typeFilter}
        setTypeFilter={handleTypeFilterChange}
        statusFilter={statusFilter}
        setStatusFilter={handleStatusFilterChange}
        onResetFilters={resetFilters}
        onView={setViewingEmployee}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
        currentPage={currentPage}
        totalPages={totalPages}
        setPage={setPage}
      />

      <EmployeeDetails
        employee={viewingEmployee}
        onClose={() => setViewingEmployee(null)}
      />
    </div>
  );
}
