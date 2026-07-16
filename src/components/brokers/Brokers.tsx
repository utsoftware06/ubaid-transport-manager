"use client";

import { useEffect, useMemo, useState } from "react";
import BrokerForm from "@/components/brokers/BrokerForm";
import BrokerCards from "@/components/brokers/BrokerCards";
import BrokerTransactionForm from "@/components/brokers/BrokerTransactionForm";
import BrokerTable from "@/components/brokers/BrokerTable";
import BrokerLedger from "@/components/brokers/BrokerLedger";
import { supabase } from "@/lib/supabase/client";

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

type RelatedRecord<T> = T | T[] | null;

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

type LoadingRelation = {
  loading_no: string | null;
  route: string | null;
};

type VehicleRelation = {
  vehicle_no: string | null;
};

type DriverRelation = {
  name: string | null;
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
  loadings?: RelatedRecord<LoadingRelation>;
  vehicles?: RelatedRecord<VehicleRelation>;
  drivers?: RelatedRecord<DriverRelation>;
};

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

function getSingleRelation<T>(relation: RelatedRecord<T> | undefined) {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
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

  useEffect(() => {
    loadInitialData();
  }, []);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    await Promise.all([
      loadBrokers(),
      loadTransactions(),
      loadLoadings(),
      loadVehicles(),
      loadDrivers(),
    ]);

    setIsLoading(false);
  }

  async function loadBrokers() {
    const { data, error } = await supabase
      .from("brokers")
      .select(
        "id, broker_name, contact_person, phone, cnic, address, opening_balance, created_at"
      )
      .order("broker_name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setBrokers([]);
      return;
    }

    setBrokers((data ?? []) as BrokerDatabaseRow[]);
  }

  async function loadTransactions() {
    const { data, error } = await supabase
      .from("broker_transactions")
      .select(
        `
        id,
        broker_id,
        transaction_date,
        transaction_type,
        amount,
        payment_method,
        reference_no,
        description,
        remarks,
        loading_id,
        vehicle_id,
        driver_id,
        reference_type,
        reference_id,
        created_at,
        loadings(loading_no, route),
        vehicles(vehicle_no),
        drivers(name)
      `
      )
      .order("transaction_date", { ascending: true })
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setTransactions([]);
      return;
    }

    const runningBalanceByBroker = new Map<string, number>();

    setTransactions(
      ((data ?? []) as BrokerTransactionDatabaseRow[]).map((transaction) => {
        const brokerId = transaction.broker_id ?? "";
        const type = toTransactionType(transaction.transaction_type);
        const value = toNumber(transaction.amount);
        const previousBalance = runningBalanceByBroker.get(brokerId) ?? 0;
        const runningBalance = previousBalance + getTransactionEffect(type, value);

        runningBalanceByBroker.set(brokerId, runningBalance);

        const loading = getSingleRelation(transaction.loadings);
        const vehicle = getSingleRelation(transaction.vehicles);
        const driver = getSingleRelation(transaction.drivers);

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
          loadingId:
            transaction.loading_id === null || transaction.loading_id === undefined
              ? null
              : Number(transaction.loading_id),
          loadingNo: loading?.loading_no ?? "-",
          vehicleId: transaction.vehicle_id ?? null,
          vehicleNo: vehicle?.vehicle_no ?? "-",
          driverId: transaction.driver_id ?? null,
          driverName: driver?.name ?? "-",
          referenceType: transaction.reference_type ?? null,
          referenceId: transaction.reference_id ?? null,
          createdAt: transaction.created_at ?? "",
          runningBalance,
        };
      })
    );
  }

  async function loadLoadings() {
    const { data, error } = await supabase
      .from("loadings")
      .select("id, loading_no, route")
      .order("id", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      setLoadings([]);
      return;
    }

    setLoadings(
      (data ?? []).map((loading) => ({
        id: Number(loading.id),
        loadingNo: loading.loading_no ?? "-",
        route: loading.route ?? "-",
      }))
    );
  }

  async function loadVehicles() {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no")
      .order("vehicle_no", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setVehicles([]);
      return;
    }

    setVehicles(
      (data ?? []).map((vehicle) => ({
        id: String(vehicle.id),
        vehicleNo: vehicle.vehicle_no ?? "-",
      }))
    );
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
        .filter((transaction) => transaction.transactionType === "Adjustment")
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
      alert("Broker name is required.");
      return false;
    }

    if (!Number.isFinite(Number(openingBalance || 0))) {
      alert("Opening balance must be a valid number.");
      return false;
    }

    return true;
  }

  function validateTransaction() {
    if (!selectedBrokerId) {
      alert("Please select a broker.");
      return false;
    }

    if (!transactionDate) {
      alert("Transaction date is required.");
      return false;
    }

    if (!transactionType) {
      alert("Transaction type is required.");
      return false;
    }

    if (!amount || Number(amount) <= 0) {
      alert("Amount must be greater than 0.");
      return false;
    }

    if (isCashbookTransaction(transactionType) && !paymentMethod) {
      alert("Payment method is required for payment transactions.");
      return false;
    }

    return true;
  }

  async function handleSaveBroker() {
    if (!validateBroker()) return;

    setIsSavingBroker(true);

    const payload = {
      broker_name: brokerName.trim(),
      contact_person: contactPerson.trim(),
      phone: phone.trim(),
      cnic: cnic.trim(),
      address: address.trim(),
      opening_balance: Number(openingBalance || 0),
      updated_at: new Date().toISOString(),
    };

    const result = editingBrokerId
      ? await supabase.from("brokers").update(payload).eq("id", editingBrokerId)
      : await supabase.from("brokers").insert(payload);

    setIsSavingBroker(false);

    if (result.error) {
      alert(result.error.message);
      return;
    }

    alert(editingBrokerId ? "Broker updated successfully!" : "Broker saved successfully!");
    resetBrokerForm();
    await loadBrokers();
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
    if (broker.transactions.length > 0) {
      alert("This broker cannot be deleted because transactions are linked with it.");
      return;
    }

    const confirmed = window.confirm(`Delete broker ${broker.brokerName}?`);
    if (!confirmed) return;

    setIsDeleting(true);

    const { error } = await supabase.from("brokers").delete().eq("id", broker.id);

    setIsDeleting(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (editingBrokerId === broker.id) resetBrokerForm();

    alert("Broker deleted successfully!");
    await loadBrokers();
  }

  async function deleteLinkedCashbookEntry(transactionId: number) {
    const { error } = await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "broker_transaction")
      .eq("reference_id", String(transactionId));

    if (error) throw new Error(error.message);
  }

  async function syncBrokerCashbookEntry(transactionId: number) {
    if (!isCashbookTransaction(transactionType)) {
      await deleteLinkedCashbookEntry(transactionId);
      return;
    }

    const broker = brokerRows.find((row) => row.id === selectedBrokerId);

    if (!broker) {
      throw new Error("Selected broker was not found for Cashbook sync.");
    }

    const cashbookPayload = {
      entry_date: transactionDate,
      entry_type:
        transactionType === "Payment From Broker" ? "Cash In" : "Cash Out",
      person_type: "Broker",
      person_name: broker.brokerName,
      vehicle_id: vehicleId || null,
      driver_id: driverId || null,
      loading_id: loadingId ? Number(loadingId) : null,
      payment_method: paymentMethod,
      amount: Number(amount),
      description:
        description.trim() ||
        `${transactionType} - ${broker.brokerName}`,
      reference_type: "broker_transaction",
      reference_id: String(transactionId),
    };

    const { data: existingEntry, error: checkError } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "broker_transaction")
      .eq("reference_id", String(transactionId))
      .maybeSingle();

    if (checkError) throw new Error(checkError.message);

    if (existingEntry) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(cashbookPayload)
        .eq("id", existingEntry.id);

      if (error) throw new Error(error.message);
      return;
    }

    const { error } = await supabase.from("cashbook_entries").insert(cashbookPayload);

    if (error) throw new Error(error.message);
  }

  async function handleSaveTransaction() {
    if (isSavingTransaction) return;
    if (!validateTransaction()) return;

    setIsSavingTransaction(true);

    const payload = {
      broker_id: selectedBrokerId,
      transaction_date: transactionDate,
      transaction_type: transactionType,
      amount: Number(amount),
      payment_method: paymentMethod,
      reference_no: referenceNo.trim(),
      description: description.trim(),
      remarks: remarks.trim(),
      loading_id: loadingId ? Number(loadingId) : null,
      vehicle_id: vehicleId || null,
      driver_id: driverId || null,
      reference_type: "manual",
      reference_id: null,
    };

    try {
      if (editingTransactionId) {
        const oldNeededCashbook = isCashbookTransaction(
          editingOriginalTransactionType
        );
        const newNeedsCashbook = isCashbookTransaction(transactionType);

        const { error } = await supabase
          .from("broker_transactions")
          .update(payload)
          .eq("id", editingTransactionId);

        if (error) throw new Error(error.message);

        if (oldNeededCashbook && !newNeedsCashbook) {
          await deleteLinkedCashbookEntry(editingTransactionId);
        } else {
          await syncBrokerCashbookEntry(editingTransactionId);
        }

        alert("Broker transaction updated successfully!");
        resetTransactionForm();
        await loadTransactions();
        return;
      }

      const { data, error } = await supabase
        .from("broker_transactions")
        .insert(payload)
        .select("id")
        .single();

      if (error) throw new Error(error.message);

      await syncBrokerCashbookEntry(Number(data.id));

      alert("Broker transaction saved successfully!");
      resetTransactionForm();
      await loadTransactions();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to save broker transaction.";
      alert(message);
    } finally {
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
  }

  async function handleDeleteTransaction(transaction: BrokerTransactionRow) {
    const confirmed = window.confirm("Delete this broker transaction?");
    if (!confirmed) return;

    setIsDeleting(true);

    try {
      await deleteLinkedCashbookEntry(transaction.id);

      const { error } = await supabase
        .from("broker_transactions")
        .delete()
        .eq("id", transaction.id);

      if (error) throw new Error(error.message);

      if (editingTransactionId === transaction.id) resetTransactionForm();

      alert("Broker transaction deleted successfully!");
      await loadTransactions();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to delete transaction.";
      alert(message);
    } finally {
      setIsDeleting(false);
    }
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">Broker Management</h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Manage brokers, payable balances, advances, payments and complete broker ledgers.
        </p>
      </div>

      <BrokerCards summary={summary} />

      <BrokerForm
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

      <BrokerTable
        rows={filteredBrokers}
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
          onClose={() => setSelectedLedgerBrokerId(null)}
          onEditTransaction={handleEditTransaction}
          onDeleteTransaction={handleDeleteTransaction}
          isDeleting={isDeleting}
        />
      )}
    </div>
  );
}