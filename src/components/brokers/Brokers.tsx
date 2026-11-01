"use client";
import { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import BrokerForm from "@/components/brokers/BrokerForm";
import BrokerCards from "@/components/brokers/BrokerCards";
import LoadingBrokeragePanel from "@/components/brokers/LoadingBrokeragePanel";
import OurAddaBrokeragePanel from "@/components/brokers/OurAddaBrokeragePanel";
import BrokerTransactionForm from "@/components/brokers/BrokerTransactionForm";
import BrokerTable from "@/components/brokers/BrokerTable";
import BrokerLedger from "@/components/brokers/BrokerLedger";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
export type BrokerBalanceStatus = "Payable" | "Advance" | "Settled";
export type BrokerTransactionType =
  | "Broker Payable"
  | "Payment To Broker"
  | "Payment From Broker"
  | "Advance To Broker"
  | "Adjustment";
export type BrokerPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer"
  | "Account";
export type LoadingOption = {
  id: number;
  loadingNo: string;
  route: string;
};
export type VehicleOption = {
  id: string;
  vehicleNo: string;
};
export type DriverOption = {
  id: string;
  name: string;
};
export type BrokerTransactionRow = {
  id: number;
  brokerId: string;
  transactionDate: string;
  transactionType: BrokerTransactionType;
  amount: number;
  paymentMethod: BrokerPaymentMethod;
  referenceNo: string;
  description: string;
  remarks: string;
  loadingId: number | null;
  loadingNo: string;
  vehicleId: string | null;
  vehicleNo: string;
  driverId: string | null;
  driverName: string;
  referenceType: string | null;
  referenceId: string | null;
  createdAt: string;
  runningBalance: number;
};
export type BrokerRow = {
  id: string;
  brokerName: string;
  contactPerson: string;
  phone: string;
  cnic: string;
  address: string;
  openingBalance: number;
  totalPayable: number;
  paymentToBroker: number;
  paymentFromBroker: number;
  advanceToBroker: number;
  adjustmentAmount: number;
  currentBalance: number;
  payableAmount: number;
  advanceAmount: number;
  balanceStatus: BrokerBalanceStatus;
  createdAt: string;
  transactions: BrokerTransactionRow[];
};
export type BrokerSummary = {
  totalBrokers: number;
  totalOpeningBalance: number;
  totalPayable: number;
  totalAdvance: number;
  totalPaymentsToBrokers: number;
  totalReceivedFromBrokers: number;
};
type BrokerDatabaseRow = {
  id: string;
  broker_name: string | null;
  contact_person: string | null;
  phone: string | null;
  cnic: string | null;
  address: string | null;
  opening_balance: number | string | null;
  created_at: string | null;
};

type BrokerTransactionDatabaseRow = {
  id: number;
  broker_id: string | null;
  transaction_date: string | null;
  transaction_type: string | null;
  amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  description: string | null;
  remarks: string | null;
  loading_id: number | string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  reference_type: string | null;
  reference_id: string | null;
  created_at: string | null;
};

type AddaOption = { id: string; label: string };

const defaultPaymentMethod: BrokerPaymentMethod = "Cash";
export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}
export function getTransactionEffect(
  transactionType: BrokerTransactionType,
  amount: number
) {
  if (transactionType === "Broker Payable") return amount;
  if (transactionType === "Payment From Broker") return amount;
  if (transactionType === "Payment To Broker") return -amount;
  if (transactionType === "Advance To Broker") return -amount;
  return amount;
}
export function getBrokerStatus(balance: number): BrokerBalanceStatus {
  if (balance > 0) return "Payable";
  if (balance < 0) return "Advance";
  return "Settled";
}
export function isCashbookTransaction(type: BrokerTransactionType) {
  return (
    type === "Payment To Broker" ||
    type === "Payment From Broker" ||
    type === "Advance To Broker"
  );
}
function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}
function toTransactionType(value: string | null): BrokerTransactionType {
  if (
    value === "Broker Payable" ||
    value === "Payment To Broker" ||
    value === "Payment From Broker" ||
    value === "Advance To Broker" ||
    value === "Adjustment"
  ) {
    return value;
  }
  return "Broker Payable";
}
function toPaymentMethod(value: string | null): BrokerPaymentMethod {
  if (
    value === "Cash" ||
    value === "Bank" ||
    value === "Cheque" ||
    value === "Online Transfer" ||
    value === "Account"
  ) {
    return value;
  }
  return "Cash";
}
export default function Brokers() {
  const { t, dir } = useLanguage();
  const [currentAddaId, setCurrentAddaId] = useState("");
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [loadingAccountRefreshKey, setLoadingAccountRefreshKey] = useState(0);
  const [addaOptions, setAddaOptions] = useState<AddaOption[]>([]);
  const loadRequestRef = useRef(0);
  const [brokerName, setBrokerName] = useState("");
  const [contactPerson, setContactPerson] = useState("");
  const [phone, setPhone] = useState("");
  const [cnic, setCnic] = useState("");
  const [address, setAddress] = useState("");
  const [openingBalance, setOpeningBalance] = useState("");
  const [editingBrokerId, setEditingBrokerId] = useState<string | null>(null);
  const [selectedBrokerId, setSelectedBrokerId] = useState("");
  const [transactionDate, setTransactionDate] = useState("");
  const [transactionType, setTransactionType] =
    useState<BrokerTransactionType>("Broker Payable");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<BrokerPaymentMethod>(defaultPaymentMethod);
  const [referenceNo, setReferenceNo] = useState("");
  const [description, setDescription] = useState("");
  const [remarks, setRemarks] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [driverId, setDriverId] = useState("");
  const [editingTransactionId, setEditingTransactionId] = useState<number | null>(
    null
  );
  const [editingOriginalTransactionType, setEditingOriginalTransactionType] =
    useState<BrokerTransactionType>("Broker Payable");
  const [editingOriginalAmount, setEditingOriginalAmount] = useState(0);
  const [brokers, setBrokers] = useState<BrokerDatabaseRow[]>([]);
  const [transactions, setTransactions] = useState<BrokerTransactionRow[]>([]);
  const [loadings, setLoadings] = useState<LoadingOption[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [drivers, setDrivers] = useState<DriverOption[]>([]);
  const [search, setSearch] = useState("");
  const [selectedLedgerBrokerId, setSelectedLedgerBrokerId] = useState<
    string | null
  >(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSavingBroker, setIsSavingBroker] = useState(false);
  const [isSavingTransaction, setIsSavingTransaction] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const brokerSaveLockRef = useRef(false);
  const transactionSaveLockRef = useRef(false);
  const deleteLockRef = useRef(false);
  const transactionFormRef = useRef<HTMLDivElement | null>(null);
  const loadInitialDataEvent = useEffectEvent(loadInitialData);
  useEffect(() => {
    void loadInitialDataEvent();
  }, []);
  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        throw authError ?? new Error("No authenticated user.");
      }
      const [{ data: profile, error: profileError }, { data: superAdmin, error: roleError }] =
        await Promise.all([
          supabase.from("profiles").select("adda_id").eq("id", authData.user.id).maybeSingle(),
          supabase.rpc("is_super_admin"),
        ]);
      if (profileError) throw profileError;
      if (roleError) throw roleError;
      const superUser = superAdmin === true;
      setIsSuperAdmin(superUser);

      if (superUser) {
        // Names vary between deployments: read existing Adda rows and use an ID fallback.
        // The resolver, not this dropdown, authorizes every requested Adda.
        const { data: addaData, error: addaError } = await supabase.from("addas").select("*");
        if (addaError) throw addaError;
        const choices: AddaOption[] = ((addaData ?? []) as Record<string, unknown>[])
          .filter((row) => typeof row.id === "string")
          .map((row) => ({
            id: String(row.id),
            label: String(row.adda_name ?? row.name ?? row.title ?? row.id),
          }))
          .sort((a, b) => a.label.localeCompare(b.label));
        setAddaOptions(choices);
        const preferred = String(profile?.adda_id ?? "");
        const firstAdda = choices.some((option) => option.id === preferred) ? preferred : "";
        setCurrentAddaId(firstAdda);
        if (firstAdda) await loadForAdda(firstAdda);
        else setIsLoading(false);
      } else {
        if (!profile?.adda_id) throw new Error("No Adda assigned to the current user.");
        const addaId = String(profile.adda_id);
        setCurrentAddaId(addaId);
        await loadForAdda(addaId);
      }
    } catch (error) {
      console.error("Unable to load Broker Adda:", error);
      setErrorMessage(t("brokers.messages.loadFailed"));
      setIsLoading(false);
    }
  }

  async function loadForAdda(addaId: string) {
    const requestId = ++loadRequestRef.current;
    resetBrokerForm();
    resetTransactionForm();
    setSelectedLedgerBrokerId(null);
    setSearch("");
    setBrokers([]);
    setTransactions([]);
    setLoadings([]);
    setVehicles([]);
    setDrivers([]);
    setErrorMessage("");
    if (!addaId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      const [loadingOptions, vehicleOptions, driverOptions] = await Promise.all([
        loadLoadings(addaId),
        loadVehicles(addaId),
        loadDrivers(addaId),
      ]);
      if (requestId !== loadRequestRef.current) return;
      setLoadings(loadingOptions);
      setVehicles(vehicleOptions);
      setDrivers(driverOptions);
      const [brokerData, transactionData] = await Promise.all([
        fetchBrokers(addaId),
        fetchTransactions(addaId, loadingOptions, vehicleOptions, driverOptions),
      ]);
      if (requestId !== loadRequestRef.current) return;
      setBrokers(brokerData);
      setTransactions(transactionData);
    } catch (error) {
      if (requestId !== loadRequestRef.current) return;
      console.error("Unable to load Adda-specific Broker data:", error);
      setErrorMessage(t("brokers.messages.loadFailed"));
    } finally {
      if (requestId === loadRequestRef.current) setIsLoading(false);
    }
  }

  async function fetchBrokers(addaId: string): Promise<BrokerDatabaseRow[]> {
    const { data, error } = await supabase.rpc("get_brokers_for_adda", { p_adda_id: addaId });
    if (error) throw error;
    return (data ?? []) as BrokerDatabaseRow[];
  }

  async function loadBrokers() {
    if (!currentAddaId) return;
    try {
      setBrokers(await fetchBrokers(currentAddaId));
    } catch (error) {
      console.error("Unable to load Brokers:", error);
      setErrorMessage(t("brokers.messages.loadFailed"));
    }
  }

  async function fetchTransactions(
    addaId: string,
    loadingOptions: LoadingOption[],
    vehicleOptions: VehicleOption[],
    driverOptions: DriverOption[]
  ): Promise<BrokerTransactionRow[]> {
    // The RPC returns broker_transactions rows, not PostgREST-joined relations.
    const { data, error } = await supabase.rpc("get_broker_transactions_for_adda", {
      p_adda_id: addaId,
    });
    if (error) throw error;
    const ordered = [...((data ?? []) as BrokerTransactionDatabaseRow[])].sort((a, b) =>
      String(a.transaction_date ?? "").localeCompare(String(b.transaction_date ?? "")) ||
      String(a.created_at ?? "").localeCompare(String(b.created_at ?? "")) ||
      Number(a.id) - Number(b.id)
    );
    const loadingMap = new Map(loadingOptions.map((item) => [item.id, item]));
    const vehicleMap = new Map(vehicleOptions.map((item) => [item.id, item]));
    const driverMap = new Map(driverOptions.map((item) => [item.id, item]));
    const runningBalanceByBroker = new Map<string, number>();
    return ordered.map((transaction) => {
      const brokerId = transaction.broker_id ?? "";
      const type = toTransactionType(transaction.transaction_type);
      const value = toNumber(transaction.amount);
      const runningBalance =
        (runningBalanceByBroker.get(brokerId) ?? 0) + getTransactionEffect(type, value);
      runningBalanceByBroker.set(brokerId, runningBalance);
      const loadingNo = transaction.loading_id == null ? null : Number(transaction.loading_id);
      return {
        id: transaction.id,
        brokerId,
        transactionDate: transaction.transaction_date ?? "",
        transactionType: type,
        amount: value,
        paymentMethod: toPaymentMethod(transaction.payment_method),
        referenceNo: transaction.reference_no ?? "-",
        description: transaction.description ?? "-",
        remarks: transaction.remarks ?? "-",
        loadingId: loadingNo,
        loadingNo: loadingNo == null ? "-" : loadingMap.get(loadingNo)?.loadingNo ?? "-",
        vehicleId: transaction.vehicle_id ?? null,
        vehicleNo: transaction.vehicle_id
          ? vehicleMap.get(transaction.vehicle_id)?.vehicleNo ?? "-"
          : "-",
        driverId: transaction.driver_id ?? null,
        driverName: transaction.driver_id
          ? driverMap.get(transaction.driver_id)?.name ?? "-"
          : "-",
        referenceType: transaction.reference_type ?? null,
        referenceId: transaction.reference_id ?? null,
        createdAt: transaction.created_at ?? "",
        runningBalance,
      };
    });
  }

  async function loadTransactions() {
    if (!currentAddaId) return;
    try {
      setTransactions(await fetchTransactions(currentAddaId, loadings, vehicles, drivers));
    } catch (error) {
      console.error("Unable to load Broker transactions:", error);
      setErrorMessage(t("brokers.messages.loadFailed"));
    }
  }

  async function loadLoadings(addaId: string): Promise<LoadingOption[]> {
    // Loading ownership follows its booking's authoritative Adda.
    const { data, error } = await supabase
      .from("loadings")
      .select("id, loading_no, route, bookings!inner(adda_id)")
      .eq("bookings.adda_id", addaId)
      .order("id", { ascending: false });
    if (error) throw error;
    return (data ?? []).map((loading) => ({
      id: Number(loading.id),
      loadingNo: loading.loading_no ?? "-",
      route: loading.route ?? "-",
    }));
  }

  async function loadVehicles(addaId: string): Promise<VehicleOption[]> {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no")
      .eq("adda_id", addaId)
      .order("vehicle_no", { ascending: true });
    if (error) throw error;
    return (data ?? []).map((vehicle) => ({
      id: String(vehicle.id),
      vehicleNo: vehicle.vehicle_no ?? "-",
    }));
  }

  async function loadDrivers(addaId: string): Promise<DriverOption[]> {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .eq("adda_id", addaId)
      .order("name", { ascending: true });
    if (error) throw error;
    return (data ?? []).map((driver) => ({
      id: String(driver.id),
      name: driver.name ?? "-",
    }));
  }

  const brokerRows = useMemo<BrokerRow[]>(() => {
    return brokers.map((broker) => {
      const brokerTransactions = transactions.filter(
        (transaction) => transaction.brokerId === broker.id
      );
      const opening = toNumber(broker.opening_balance);
      const totalPayable = brokerTransactions
        .filter((transaction) => transaction.transactionType === "Broker Payable")
        .reduce((total, transaction) => total + transaction.amount, 0);
      const paymentFromBroker = brokerTransactions
        .filter(
          (transaction) => transaction.transactionType === "Payment From Broker"
        )
        .reduce((total, transaction) => total + transaction.amount, 0);
      const paymentToBroker = brokerTransactions
        .filter((transaction) => transaction.transactionType === "Payment To Broker")
        .reduce((total, transaction) => total + transaction.amount, 0);
      const advanceToBroker = brokerTransactions
        .filter(
          (transaction) => transaction.transactionType === "Advance To Broker"
        )
        .reduce((total, transaction) => total + transaction.amount, 0);
      const adjustmentAmount = brokerTransactions
        .filter(
          (transaction) => transaction.transactionType === "Adjustment"
        )
        .reduce(
          (total, transaction) =>
            total +
            getTransactionEffect(transaction.transactionType, transaction.amount),
          0
        );
      let runningBalance = opening;
      const transactionsWithOpening = brokerTransactions.map((transaction) => {
        runningBalance += getTransactionEffect(
          transaction.transactionType,
          transaction.amount
        );
        return {
          ...transaction,
          runningBalance,
        };
      });
      const currentBalance =
        opening +
        totalPayable +
        paymentFromBroker -
        paymentToBroker -
        advanceToBroker +
        adjustmentAmount;
      return {
        id: broker.id,
        brokerName: broker.broker_name ?? "-",
        contactPerson: broker.contact_person ?? "-",
        phone: broker.phone ?? "-",
        cnic: broker.cnic ?? "-",
        address: broker.address ?? "-",
        openingBalance: opening,
        totalPayable,
        paymentToBroker,
        paymentFromBroker,
        advanceToBroker,
        adjustmentAmount,
        currentBalance,
        payableAmount: currentBalance > 0 ? currentBalance : 0,
        advanceAmount: currentBalance < 0 ? Math.abs(currentBalance) : 0,
        balanceStatus: getBrokerStatus(currentBalance),
        createdAt: broker.created_at ?? "",
        transactions: transactionsWithOpening,
      };
    });
  }, [brokers, transactions]);
  const filteredBrokers = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return brokerRows;
    return brokerRows.filter((broker) =>
      [
        broker.brokerName,
        broker.contactPerson,
        broker.phone,
        broker.cnic,
        broker.address,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [brokerRows, search]);
  const selectedBroker = useMemo(() => {
    return brokerRows.find((broker) => broker.id === selectedBrokerId) ?? null;
  }, [brokerRows, selectedBrokerId]);
  const selectedLedgerBroker = useMemo(() => {
    return (
      brokerRows.find((broker) => broker.id === selectedLedgerBrokerId) ?? null
    );
  }, [brokerRows, selectedLedgerBrokerId]);
  const summary = useMemo<BrokerSummary>(() => {
    return filteredBrokers.reduce(
      (total, broker) => ({
        totalBrokers: total.totalBrokers + 1,
        totalOpeningBalance: total.totalOpeningBalance + broker.openingBalance,
        totalPayable: total.totalPayable + broker.payableAmount,
        totalAdvance: total.totalAdvance + broker.advanceAmount,
        totalPaymentsToBrokers:
          total.totalPaymentsToBrokers + broker.paymentToBroker + broker.advanceToBroker,
        totalReceivedFromBrokers:
          total.totalReceivedFromBrokers + broker.paymentFromBroker,
      }),
      {
        totalBrokers: 0,
        totalOpeningBalance: 0,
        totalPayable: 0,
        totalAdvance: 0,
        totalPaymentsToBrokers: 0,
        totalReceivedFromBrokers: 0,
      }
    );
  }, [filteredBrokers]);
  function resetBrokerForm() {
    setBrokerName("");
    setContactPerson("");
    setPhone("");
    setCnic("");
    setAddress("");
    setOpeningBalance("");
    setEditingBrokerId(null);
  }
  function resetTransactionForm() {
    setSelectedBrokerId("");
    setTransactionDate("");
    setTransactionType("Broker Payable");
    setAmount("");
    setPaymentMethod(defaultPaymentMethod);
    setReferenceNo("");
    setDescription("");
    setRemarks("");
    setLoadingId("");
    setVehicleId("");
    setDriverId("");
    setEditingTransactionId(null);
    setEditingOriginalTransactionType("Broker Payable");
    setEditingOriginalAmount(0);
  }
  function validateBroker() {
    if (!brokerName.trim()) {
      alert(t("brokers.validation.nameRequired"));
      return false;
    }
    if (!Number.isFinite(Number(openingBalance || 0))) {
      alert(t("brokers.validation.openingBalanceInvalid"));
      return false;
    }
    return true;
  }
  function validateTransaction() {
    if (!selectedBrokerId) {
      alert(t("brokers.validation.selectBroker"));
      return false;
    }
    if (!transactionDate) {
      alert(t("brokers.validation.transactionDateRequired"));
      return false;
    }
    if (!transactionType) {
      alert(t("brokers.validation.transactionTypeRequired"));
      return false;
    }
    if (!amount || !Number.isFinite(Number(amount)) || Number(amount) <= 0) {
      alert(t("brokers.validation.amountPositive"));
      return false;
    }
    if (isCashbookTransaction(transactionType) && !paymentMethod) {
      alert(t("brokers.validation.paymentMethodRequired"));
      return false;
    }
    return true;
  }
  async function handleSaveBroker() {
    if (brokerSaveLockRef.current) return;
    if (!validateBroker()) return;
    brokerSaveLockRef.current = true;
    setIsSavingBroker(true);
    try {
      if (!currentAddaId) throw new Error("No Adda selected.");
      // The server resolves and enforces the authoritative Adda.
      // No direct browser INSERT/UPDATE on the Broker master.
      const { error } = await supabase.rpc("save_broker", {
        p_id: editingBrokerId,
        p_adda_id: currentAddaId,
        p_broker_name: brokerName.trim(),
        p_contact_person: contactPerson.trim(),
        p_phone: phone.trim(),
        p_cnic: cnic.trim(),
        p_address: address.trim(),
        p_opening_balance: Number(openingBalance || 0),
      });
      if (error) {
        console.error("Unable to save broker:", error);
        alert(t("brokers.messages.saveFailed"));
        return;
      }
      alert(editingBrokerId ? t("brokers.messages.updated") : t("brokers.messages.saved"));
      resetBrokerForm();
      await loadBrokers();
    } catch (error) {
      console.error("Unexpected error while saving broker:", error);
      alert(t("brokers.messages.saveFailed"));
    } finally {
      brokerSaveLockRef.current = false;
      setIsSavingBroker(false);
    }
  }
  function handleEditBroker(broker: BrokerRow) {
    setEditingBrokerId(broker.id);
    setBrokerName(broker.brokerName === "-" ? "" : broker.brokerName);
    setContactPerson(broker.contactPerson === "-" ? "" : broker.contactPerson);
    setPhone(broker.phone === "-" ? "" : broker.phone);
    setCnic(broker.cnic === "-" ? "" : broker.cnic);
    setAddress(broker.address === "-" ? "" : broker.address);
    setOpeningBalance(String(broker.openingBalance));
  }
  async function handleDeleteBroker(broker: BrokerRow) {
    if (deleteLockRef.current) return;
    if (broker.transactions.length > 0) {
      alert(t("brokers.messages.deleteLinked"));
      return;
    }
    const confirmed = window.confirm(`${t("brokers.deleteConfirm")} ${broker.brokerName}?`);
    if (!confirmed) return;
    deleteLockRef.current = true;
    setIsDeleting(true);
    try {
      if (!currentAddaId) throw new Error("No Adda selected.");
      // The server verifies ownership and checks linked transactions atomically.
      const { error } = await supabase.rpc("delete_broker", {
        p_id: broker.id,
        p_adda_id: currentAddaId,
      });
      if (error) {
        console.error("Unable to delete broker:", error);
        alert(error.code === "23503" ? t("brokers.messages.deleteLinked") : t("brokers.messages.deleteFailed"));
        return;
      }
      if (editingBrokerId === broker.id) resetBrokerForm();
      alert(t("brokers.messages.deleted"));
      await loadBrokers();
    } catch (error) {
      console.error("Unable to delete broker:", error);
      alert(t("brokers.messages.deleteFailed"));
    } finally {
      deleteLockRef.current = false;
      setIsDeleting(false);
    }
  }
  async function handleSaveTransaction() {
    if (transactionSaveLockRef.current) return;
    if (!validateTransaction()) return;
    const transactionId = editingTransactionId;
    transactionSaveLockRef.current = true;
    setIsSavingTransaction(true);
    try {
      if (!currentAddaId) throw new Error("No Adda assigned to the current user.");
      const { error } = await supabase.rpc("save_broker_transaction", {
        p_id: transactionId === null ? null : transactionId,
        p_adda_id: currentAddaId,
        p_broker_id: selectedBrokerId,
        p_transaction_date: transactionDate,
        p_transaction_type: transactionType,
        p_amount: Number(amount),
        p_payment_method: paymentMethod,
        p_reference_no: referenceNo.trim() || null,
        p_description: description.trim() || null,
        p_remarks: remarks.trim() || null,
        p_loading_id: loadingId ? Number(loadingId) : null,
        p_vehicle_id: vehicleId || null,
        p_driver_id: driverId || null,
      });
      if (error) throw new Error(error.message);
      resetTransactionForm();
      setSelectedLedgerBrokerId(null);
      await loadTransactions();
      alert(
        t(
          transactionId !== null
            ? "brokers.messages.transactionUpdated"
            : "brokers.messages.transactionSaved"
        )
      );
    } catch (error) {
      console.error("Unable to save broker transaction:", error);
      alert(t("brokers.messages.transactionSaveFailed"));
    } finally {
      transactionSaveLockRef.current = false;
      setIsSavingTransaction(false);
    }
  }
  function handleEditTransaction(transaction: BrokerTransactionRow) {
    setEditingTransactionId(transaction.id);
    setEditingOriginalTransactionType(transaction.transactionType);
    setEditingOriginalAmount(transaction.amount);
    setSelectedBrokerId(transaction.brokerId);
    setTransactionDate(transaction.transactionDate);
    setTransactionType(transaction.transactionType);
    setAmount(String(transaction.amount));
    setPaymentMethod(transaction.paymentMethod);
    setReferenceNo(transaction.referenceNo === "-" ? "" : transaction.referenceNo);
    setDescription(transaction.description === "-" ? "" : transaction.description);
    setRemarks(transaction.remarks === "-" ? "" : transaction.remarks);
    setLoadingId(transaction.loadingId ? String(transaction.loadingId) : "");
    setVehicleId(transaction.vehicleId ?? "");
    setDriverId(transaction.driverId ?? "");
    setSelectedLedgerBrokerId(null);
    window.requestAnimationFrame(() => {
      transactionFormRef.current?.scrollIntoView({
        behavior: "smooth",
        block: "start",
      });
    });
  }
  async function handleDeleteTransaction(transaction: BrokerTransactionRow) {
    if (deleteLockRef.current) return;
    const confirmed = window.confirm(t("brokers.transactionDeleteConfirm"));
    if (!confirmed) return;
    deleteLockRef.current = true;
    setIsDeleting(true);
    try {
      if (!currentAddaId) throw new Error("No Adda assigned to the current user.");
      const { error } = await supabase.rpc("delete_broker_transaction", {
        p_id: transaction.id,
        p_adda_id: currentAddaId,
      });
      if (error) throw new Error(error.message);
      if (editingTransactionId === transaction.id) resetTransactionForm();
      alert(t("brokers.messages.transactionDeleted"));
      await loadTransactions();
    } catch (error) {
      console.error("Unable to delete broker transaction:", error);
      alert(t("brokers.messages.transactionDeleteFailed"));
    } finally {
      deleteLockRef.current = false;
      setIsDeleting(false);
    }
  }
  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="broker" accent="coral" title={t("brokers.title")} description={t("brokers.description")} />
      </header>
      {isSuperAdmin && (
        <div className="rounded-xl bg-white p-4 shadow-md">
          <label htmlFor="broker-adda" className="mb-2 block text-sm font-semibold text-gray-900">
            Select Adda (Super Admin)
          </label>
          <select
            id="broker-adda"
            value={currentAddaId}
            disabled={isLoading || isSavingBroker || isSavingTransaction || isDeleting}
            onChange={(event) => {
              const nextAdda = event.target.value;
              setCurrentAddaId(nextAdda);
              void loadForAdda(nextAdda);
            }}
            className="w-full rounded-lg border border-gray-300 bg-white p-2 text-gray-900 md:max-w-md"
          >
            <option value="">Select an Adda</option>
            {addaOptions.map((option) => (
              <option key={option.id} value={option.id}>{option.label}</option>
            ))}
          </select>
          {addaOptions.length === 0 && (
            <p className="mt-2 text-sm text-red-700">No accessible Addas found.</p>
          )}
        </div>
      )}
      {currentAddaId && <BrokerCards summary={summary} />}
      {currentAddaId && <OurAddaBrokeragePanel key={`our-margin-${currentAddaId}`} addaId={currentAddaId} refreshKey={loadingAccountRefreshKey} />}
      {currentAddaId && <LoadingBrokeragePanel key={currentAddaId} addaId={currentAddaId} onUpdated={() => setLoadingAccountRefreshKey((value) => value + 1)} />}
      {currentAddaId && (
        <>
        <BrokerForm
          contextKey={`${currentAddaId}:${editingBrokerId ?? "new"}`}
          brokerName={brokerName}
          setBrokerName={setBrokerName}
          contactPerson={contactPerson}
          setContactPerson={setContactPerson}
          phone={phone}
          setPhone={setPhone}
          cnic={cnic}
          setCnic={setCnic}
          address={address}
          setAddress={setAddress}
          openingBalance={openingBalance}
          setOpeningBalance={setOpeningBalance}
          onSave={handleSaveBroker}
          isSaving={isSavingBroker}
          isEditing={Boolean(editingBrokerId)}
          onCancelEdit={resetBrokerForm}
        />
        <div ref={transactionFormRef}>
          <BrokerTransactionForm
            selectedBrokerId={selectedBrokerId}
            setSelectedBrokerId={setSelectedBrokerId}
            transactionDate={transactionDate}
            setTransactionDate={setTransactionDate}
            transactionType={transactionType}
            setTransactionType={setTransactionType}
            amount={amount}
            setAmount={setAmount}
            paymentMethod={paymentMethod}
            setPaymentMethod={setPaymentMethod}
            referenceNo={referenceNo}
            setReferenceNo={setReferenceNo}
            description={description}
            setDescription={setDescription}
            remarks={remarks}
            setRemarks={setRemarks}
            loadingId={loadingId}
            setLoadingId={setLoadingId}
            vehicleId={vehicleId}
            setVehicleId={setVehicleId}
            driverId={driverId}
            setDriverId={setDriverId}
            brokers={brokerRows}
            selectedBroker={selectedBroker}
            loadings={loadings}
            vehicles={vehicles}
            drivers={drivers}
            editingOriginalTransactionType={editingOriginalTransactionType}
            editingOriginalAmount={editingOriginalAmount}
            onSave={handleSaveTransaction}
            isSaving={isSavingTransaction}
            isEditing={Boolean(editingTransactionId)}
            onCancelEdit={resetTransactionForm}
          />
        </div>
        <BrokerTable
          rows={filteredBrokers}
          addaId={currentAddaId}
          search={search}
          setSearch={setSearch}
          onEdit={handleEditBroker}
          onDelete={handleDeleteBroker}
          onViewLedger={(broker) => setSelectedLedgerBrokerId(broker.id)}
          isDeleting={isDeleting}
          isLoading={isLoading}
          errorMessage={errorMessage}
        />
        {selectedLedgerBroker && (
          <BrokerLedger
            broker={selectedLedgerBroker}
            addaId={currentAddaId}
            onClose={() => setSelectedLedgerBrokerId(null)}
            onEditTransaction={handleEditTransaction}
            onDeleteTransaction={handleDeleteTransaction}
            isDeleting={isDeleting}
          />
        )}
        </>
      )}
    </div>
  );
}
