"use client";

type Props = {
  brokerName: string;
  setBrokerName: (value: string) => void;
  contactPerson: string;
  setContactPerson: (value: string) => void;
  phone: string;
  setPhone: (value: string) => void;
  cnic: string;
  setCnic: (value: string) => void;
  address: string;
  setAddress: (value: string) => void;
  openingBalance: string;
  setOpeningBalance: (value: string) => void;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

export default function BrokerForm({
  brokerName,
  setBrokerName,
  contactPerson,
  setContactPerson,
  phone,
  setPhone,
  cnic,
  setCnic,
  address,
  setAddress,
  openingBalance,
  setOpeningBalance,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Broker" : "Add Broker"}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Maintain broker profile and opening balance.
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            Cancel Edit
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Broker Name
          </label>
          <input
            type="text"
            value={brokerName}
            onChange={(event) => setBrokerName(event.target.value)}
            placeholder="Broker name"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Contact Person
          </label>
          <input
            type="text"
            value={contactPerson}
            onChange={(event) => setContactPerson(event.target.value)}
            placeholder="Contact person"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Phone
          </label>
          <input
            type="text"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder="Phone"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            CNIC
          </label>
          <input
            type="text"
            value={cnic}
            onChange={(event) => setCnic(event.target.value)}
            placeholder="CNIC"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Opening Balance
          </label>
          <input
            type="number"
            value={openingBalance}
            onChange={(event) => setOpeningBalance(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Address
          </label>
          <input
            type="text"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            placeholder="Address"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-6 flex justify-end">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving ? "Saving..." : isEditing ? "Update Broker" : "Save Broker"}
        </button>
      </div>
    </div>
  );
}