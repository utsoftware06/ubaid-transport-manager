"use client";

import { useCallback, useEffect, useMemo, useState, useRef } from "react";
import { useReactToPrint } from "react-to-print";
import { supabase } from "@/lib/supabase/client";
import BookingSlip from "@/components/bookings/BookingSlip";
import type {
  Adda,
  Booking,
  BookingParty,
} from "@/components/bookings/types";
import { useLanguage } from "@/contexts/LanguageContext";
import { USER_ROLES } from "@/config/navigation";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { waitForPrintImages } from "@/lib/print/printAssets";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type ProfileRow = {
  role: string | null;
  adda_id: string | null;
};

function singleRelation<T>(relation: T | T[] | null | undefined): T | null {
  return Array.isArray(relation) ? relation[0] ?? null : relation ?? null;
}

export default function BookingsPage() {
  const { t, dir, language } = useLanguage();
  const [addaId, setAddaId] = useState("");
  const [partyId, setPartyId] = useState("");
  const [partySearch, setPartySearch] = useState("");
  const [bookingNo, setBookingNo] = useState("");
  const [search, setSearch] = useState("");
  const [bookingDate, setBookingDate] = useState("");
  const [senderName, setSenderName] = useState("");
  const [senderPhone, setSenderPhone] = useState("");
  const [receiverName, setReceiverName] = useState("");
  const [receiverPhone, setReceiverPhone] = useState("");
  const [fromCity, setFromCity] = useState("");
  const [toCity, setToCity] = useState("");
  const [goodsName, setGoodsName] = useState("");
  const [quantity, setQuantity] = useState("");
  const [weight, setWeight] = useState("");
  const [freight, setFreight] = useState("");
  const [status, setStatus] = useState("Booked");

  const [addas, setAddas] = useState<Adda[]>([]);
  const [parties, setParties] = useState<BookingParty[]>([]);
  const [profileAddaId, setProfileAddaId] = useState<string | null>(null);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);
  const printRef = useRef<HTMLDivElement>(null);
  const saveInProgressRef = useRef(false);
  const [isSaving, setIsSaving] = useState(false);
  const modulePrint = useModuleTransportPrint("bilty", selectedBooking?.adda_id ?? null, language === "ur" ? "ur" : "en");

const handlePrint = useReactToPrint({
  contentRef: printRef,
  onBeforePrint: () => waitForPrintImages(printRef.current),
});

  function printBookingSlip(booking: Booking) {
    const statusKey = booking.status === "In Transit" ? "bookings.status.inTransit" : booking.status === "Delivered" ? "bookings.status.delivered" : "bookings.status.booked";
    const presentation: ModulePrintPresentation = {
      documentType: "bilty",
      title: printLabel("bookings.receipt.title"),
      documentNo: printValue(booking.booking_no),
      documentDate: printValue(booking.booking_date),
      fields: [
        { label: printLabel("bookings.senderName"), value: printValue(booking.sender_name) },
        { label: printLabel("bookings.senderPhone"), value: printValue(booking.sender_phone) },
        { label: printLabel("bookings.receiverName"), value: printValue(booking.receiver_name) },
        { label: printLabel("bookings.receiverPhone"), value: printValue(booking.receiver_phone) },
        { label: printLabel("bookings.fromCity"), value: printValue(booking.from_city) },
        { label: printLabel("bookings.toCity"), value: printValue(booking.to_city) },
        { label: printLabel("bookings.party"), value: printValue(booking.parties?.name) },
        { label: printLabel("common.status"), value: printLabel(statusKey) },
      ],
      tables: [{
        title: printLabel("bookings.goods"),
        columns: [printLabel("bookings.goodsName"), printLabel("common.quantity"), printLabel("common.weight"), printLabel("common.freight")],
        rows: [[printValue(booking.goods_name), printValue(booking.quantity), printValue(booking.weight), printValue(booking.freight)]],
      }],
    };
    modulePrint.openPresentation(presentation, () => {
      setSelectedBooking(booking);
      window.setTimeout(() => handlePrint(), 0);
    }, booking.adda_id);
  }

  const loadAddas = useCallback(async () => {
    const { data, error } = await supabase
      .from("addas")
      .select("*")
      .order("name");

    if (error) {
      console.error("Unable to load addas for bookings:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) {
      setAddas(data);
    }
  }, [t]);

  const loadProfile = useCallback(async () => {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) {
      throw authError ?? new Error("Authenticated booking user is unavailable");
    }
    const { data, error } = await supabase
      .from("profiles")
      .select("role, adda_id")
      .eq("id", authData.user.id)
      .single();
    if (error) throw error;
    const profile = data as ProfileRow;
    const superAdmin = profile.role === USER_ROLES.superAdmin;
    if (!superAdmin && !profile.adda_id) {
      throw new Error("Authenticated booking user has no Adda");
    }
    setIsSuperAdmin(superAdmin);
    setProfileAddaId(profile.adda_id);
    if (profile.adda_id) setAddaId(profile.adda_id);
  }, []);

  const loadParties = useCallback(async () => {
    const { data, error } = await supabase
      .from("parties")
      .select("id, adda_id, name, phone, city")
      .eq("is_active", true)
      .order("name");
    if (error) throw error;
    setParties((data ?? []) as BookingParty[]);
  }, []);

  const loadBookings = useCallback(async () => {
    const { data, error } = await supabase
      .from("bookings")
      .select("*, parties(name)")
      .order("created_at", {
        ascending: false,
      });

    if (error) {
      console.error("Unable to load bookings:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) {
      setBookings(
        data.map((booking) => ({
          ...booking,
          parties: singleRelation(booking.parties),
        })) as Booking[]
      );
    }
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void (async () => {
        try {
          await loadProfile();
          await Promise.all([loadAddas(), loadParties(), loadBookings()]);
        } catch (error) {
          console.error("Unable to load Booking Party context:", error);
          alert(t("common.messages.loadFailed"));
        }
      })();
    }, 0);

    return () => window.clearTimeout(timer);
  }, [loadAddas, loadBookings, loadParties, loadProfile, t]);

  const availableParties = useMemo(() => {
    const keyword = partySearch.trim().toLocaleLowerCase();
    return parties.filter(
      (party) =>
        party.adda_id === addaId &&
        (!keyword ||
          [party.name, party.phone, party.city]
            .filter(Boolean)
            .join(" ")
            .toLocaleLowerCase()
            .includes(keyword))
    );
  }, [addaId, parties, partySearch]);
const filteredBookings = bookings.filter(
  (booking) =>
    booking.booking_no
      ?.toLowerCase()
      .includes(search.toLowerCase()) ||
    booking.sender_name
      ?.toLowerCase()
      .includes(search.toLowerCase()) ||
    booking.receiver_name
      ?.toLowerCase()
      .includes(search.toLowerCase())
);
 async function handleSaveBooking(
  e: React.FormEvent<HTMLFormElement>
) {
  e.preventDefault();
  if (saveInProgressRef.current) return;

  const effectiveAddaId = profileAddaId ?? addaId;
  if (!effectiveAddaId) {
    alert(t("bookings.validation.addaRequired"));
    return;
  }
  if (!isSuperAdmin && effectiveAddaId !== profileAddaId) {
    alert(t("bookings.validation.partyAddaMismatch"));
    return;
  }
  const selectedParty = partyId
    ? parties.find((party) => party.id === partyId)
    : null;
  const retainingLegacyParty =
    Boolean(editingId) &&
    partyId ===
      (bookings.find((booking) => booking.id === editingId)?.party_id ?? "");
  if (
    partyId &&
    ((!selectedParty && !retainingLegacyParty) ||
      (selectedParty && selectedParty.adda_id !== effectiveAddaId))
  ) {
    alert(t("bookings.validation.partyAddaMismatch"));
    return;
  }

  let error;
  saveInProgressRef.current = true;
  setIsSaving(true);

  try {
  if (partyId && !retainingLegacyParty) {
    const { data: verifiedParty, error: partyError } = await supabase
      .from("parties")
      .select("id")
      .eq("id", partyId)
      .eq("adda_id", effectiveAddaId)
      .eq("is_active", true)
      .maybeSingle();
    if (partyError || !verifiedParty) {
      if (partyError) {
        console.error("Unable to verify selected Booking Party:", partyError);
      }
      alert(t("bookings.validation.partyAddaMismatch"));
      return;
    }
  }

  if (editingId) {
    // UPDATE
    const result = await supabase
      .from("bookings")
      .update({
        adda_id: effectiveAddaId,
        party_id: partyId || null,
        booking_no: bookingNo,
        booking_date: bookingDate,
        sender_name: senderName,
        sender_phone: senderPhone,
        receiver_name: receiverName,
        receiver_phone: receiverPhone,
        from_city: fromCity,
        to_city: toCity,
        goods_name: goodsName,
        quantity: Number(quantity),
        weight: Number(weight),
        freight: Number(freight),
        status,
      })
      .eq("id", editingId);

    error = result.error;
  } else {
    // INSERT
    const result = await supabase
      .from("bookings")
      .insert({
        adda_id: effectiveAddaId,
        party_id: partyId || null,
        booking_no: bookingNo,
        booking_date: bookingDate,
        sender_name: senderName,
        sender_phone: senderPhone,
        receiver_name: receiverName,
        receiver_phone: receiverPhone,
        from_city: fromCity,
        to_city: toCity,
        goods_name: goodsName,
        quantity: Number(quantity),
        weight: Number(weight),
        freight: Number(freight),
        status,
      });

    error = result.error;
  }

  if (error) {
    console.error("Unable to save booking:", error);
    alert(t("common.messages.saveFailed"));
    return;
  }

  alert(
    editingId
      ? t("bookings.messages.updatedSuccessfully")
      : t("bookings.messages.savedSuccessfully")
  );

  setEditingId(null);

  setAddaId("");
  if (profileAddaId) setAddaId(profileAddaId);
  setPartyId("");
  setPartySearch("");
  setBookingNo("");
  setBookingDate("");
  setSenderName("");
  setSenderPhone("");
  setReceiverName("");
  setReceiverPhone("");
  setFromCity("");
  setToCity("");
  setGoodsName("");
  setQuantity("");
  setWeight("");
  setFreight("");
  setStatus("Booked");

  await loadBookings();
  } finally {
    saveInProgressRef.current = false;
    setIsSaving(false);
  }
}

  return (
    <main dir={dir} className="ut-module-page space-y-5">
      <div className="mx-auto w-full max-w-4xl space-y-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
        <ModulePageHeading icon="package" accent="purple" title={t("bookings.createBilty")} />








        <form
          onSubmit={handleSaveBooking}
          className="space-y-4"
        >
          <select
            value={addaId}
            onChange={(e) => {
              setAddaId(e.target.value);
              setPartyId("");
              setPartySearch("");
            }}
            disabled={!isSuperAdmin}
            aria-label={t("bookings.selectAdda")}
            className="w-full rounded-lg border border-slate-300 bg-white p-3 font-medium text-slate-900 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-700"
            required
          >
            <option value="">
              {t("bookings.selectAdda")}
            </option>

            {addas.map((adda) => (
              <option
                key={adda.id}
                value={adda.id}
              >
                {adda.name}
              </option>
            ))}
          </select>


          <div className="rounded-xl border border-slate-200 bg-white p-4">
            <label htmlFor="booking-party-search" className="mb-2 block font-bold text-slate-900">
              {t("bookings.party")}
            </label>
            <VoiceTypingField fieldLabel={t("bookings.searchParty")} mode="text"><input
              id="booking-party-search"
              type="search"
              value={partySearch}
              onChange={(event) => setPartySearch(event.target.value)}
              placeholder={t("bookings.searchParty")}
              className="mb-3 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium text-slate-900 placeholder:text-slate-500"
            /></VoiceTypingField>
            <select
              id="booking-party"
              aria-label={t("bookings.selectParty")}
              value={partyId}
              onChange={(event) => setPartyId(event.target.value)}
              disabled={!addaId || availableParties.length === 0}
              className="w-full rounded-lg border border-slate-300 bg-white p-3 font-medium text-slate-900 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-700"
            >
              <option value="">{t("bookings.selectParty")}</option>
              {editingId &&
                partyId &&
                !availableParties.some((party) => party.id === partyId) && (
                  <option value={partyId}>
                    {bookings.find((booking) => booking.id === editingId)?.parties?.name ??
                      t("bookings.inactiveParty")}
                  </option>
                )}
              {availableParties.map((party) => (
                <option key={party.id} value={party.id}>
                  {party.name}
                  {party.city ? ` — ${party.city}` : ""}
                </option>
              ))}
            </select>
            {addaId && availableParties.length === 0 && (
              <p role="status" className="mt-2 font-semibold text-slate-700">
                {t("bookings.noActiveParties")}
              </p>
            )}
          </div>


          <VoiceTypingField fieldLabel={t("bookings.biltyNumber")} mode="identifier"><input
            type="text"
            placeholder={t("bookings.biltyNumber")}
            dir="ltr"
            value={bookingNo}
            onChange={(e) =>
              setBookingNo(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            required
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.date")} mode="date"><input
            type="date"
            dir="ltr"
            value={bookingDate}
            onChange={(e) =>
              setBookingDate(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.senderName")} value={senderName} onValueChange={setSenderName} contextKey={`${addaId}:${editingId ?? "new"}`}>
            <input
              type="text"
              placeholder={t("bookings.senderName")}
              value={senderName}
              onChange={(e) => setSenderName(e.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.senderPhone")} mode="phone"><input
            type="text"
            placeholder={t("bookings.senderPhone")}
            dir="ltr"
            value={senderPhone}
            onChange={(e) =>
              setSenderPhone(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.receiverName")} value={receiverName} onValueChange={setReceiverName} contextKey={`${addaId}:${editingId ?? "new"}`}>
            <input
              type="text"
              placeholder={t("bookings.receiverName")}
              value={receiverName}
              onChange={(e) => setReceiverName(e.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.receiverPhone")} mode="phone"><input
            type="text"
            placeholder={t("bookings.receiverPhone")}
            dir="ltr"
            value={receiverPhone}
            onChange={(e) =>
              setReceiverPhone(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.fromCity")} value={fromCity} onValueChange={setFromCity} contextKey={`${addaId}:${editingId ?? "new"}`}>
            <input
              type="text"
              placeholder={t("bookings.fromCity")}
              value={fromCity}
              onChange={(e) => setFromCity(e.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.toCity")} value={toCity} onValueChange={setToCity} contextKey={`${addaId}:${editingId ?? "new"}`}>
            <input
              type="text"
              placeholder={t("bookings.toCity")}
              value={toCity}
              onChange={(e) => setToCity(e.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </VoiceTypingField>

          <VoiceTypingField fieldLabel={t("bookings.goodsName")} value={goodsName} onValueChange={setGoodsName} contextKey={`${addaId}:${editingId ?? "new"}`}>
            <input
              type="text"
              placeholder={t("bookings.goodsName")}
              value={goodsName}
              onChange={(e) => setGoodsName(e.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </VoiceTypingField>

          <VoiceTypingField fieldLabel={t("common.quantity")} mode="number"><input
            type="number"
            dir="ltr"
            placeholder={t("common.quantity")}
            value={quantity}
            onChange={(e) =>
              setQuantity(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("common.weight")} mode="number"><input
            type="number"
            dir="ltr"
            placeholder={t("common.weight")}
            value={weight}
            onChange={(e) =>
              setWeight(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <VoiceTypingField fieldLabel={t("common.freight")} mode="amount"><input
            type="number"
            dir="ltr"
            placeholder={t("common.freight")}
            value={freight}
            onChange={(e) =>
              setFreight(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          /></VoiceTypingField>

          <select
            value={status}
            onChange={(e) =>
              setStatus(e.target.value)
            }
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          >
            <option value="Booked">{t("bookings.status.booked")}</option>
            <option value="In Transit">{t("bookings.status.inTransit")}</option>
            <option value="Delivered">{t("bookings.status.delivered")}</option>
          </select>

          <button
            type="submit"
            disabled={isSaving}
            className={`w-full p-3 rounded-lg text-white ${
              editingId
                ? "bg-yellow-600 hover:bg-yellow-700"
                : "bg-blue-600 hover:bg-blue-700"
            }`}
          >
            {isSaving
              ? t("common.states.saving")
              : editingId
                ? t("bookings.updateBilty")
                : t("bookings.saveBilty")}
          </button>
        </form>


        <div className="mt-10">
          <h2 className="text-2xl font-bold mb-4 text-gray-900">
            {t("bookings.list")}
          </h2>
        <VoiceTypingField fieldLabel={t("bookings.searchPlaceholder")} mode="text"><input
  type="text"
  placeholder={t("bookings.searchPlaceholder")}
  value={search}
  onChange={(e) => setSearch(e.target.value)}
  className="mb-5 w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm font-medium text-slate-900 placeholder:text-slate-500 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
/></VoiceTypingField>
          {bookings.length === 0 ? (
            <p className="text-gray-600">
              {t("bookings.empty")}
            </p>
          ) : (
            <div className="space-y-4">
              {filteredBookings.map((booking) => (
                <div
                  key={booking.id}
                  className="rounded-xl border border-slate-200 bg-white p-4 transition-colors hover:border-blue-200 hover:bg-slate-50/60"
                >
                  <h3 className="text-xl font-semibold text-gray-900">
                    <span dir="ltr">{booking.booking_no}</span>
                  </h3>

                  <p className="text-gray-700">
                    {t("bookings.party")}:{" "}
                    {booking.parties?.name ?? t("bookings.legacyParty")}
                  </p>

                  <p className="text-gray-700">
                    {t("bookings.sender")}:{" "}
                    {booking.sender_name}
                  </p>

                  <p className="text-gray-700">
                    {t("bookings.receiver")}:{" "}
                    {booking.receiver_name}
                  </p>

                  <p className="text-gray-700">
                    {t("common.route")}:{" "}
                    {booking.from_city} {dir === "rtl" ? "←" : "→"}{" "}
                    {booking.to_city}
                  </p>

                  <p className="text-gray-700">
                    {t("common.freight")}:{" "}
                    <span dir="ltr">{booking.freight}</span>
                  </p>

                  <p className="text-gray-700">
                    {t("common.status")}: {t(`bookings.status.${booking.status === "In Transit" ? "inTransit" : booking.status.toLowerCase()}`)}
                  </p>
                  <div className="mt-4">
  <button
    onClick={() => {
      setEditingId(booking.id);

      setAddaId(booking.adda_id ?? "");
      setPartyId(booking.party_id ?? "");
      setPartySearch("");
      setBookingNo(booking.booking_no ?? "");
      setBookingDate(booking.booking_date ?? "");
      setSenderName(booking.sender_name ?? "");
      setSenderPhone(booking.sender_phone ?? "");
      setReceiverName(booking.receiver_name ?? "");
      setReceiverPhone(booking.receiver_phone ?? "");
      setFromCity(booking.from_city ?? "");
      setToCity(booking.to_city ?? "");
      setGoodsName(booking.goods_name ?? "");
      setQuantity(String(booking.quantity ?? ""));
      setWeight(String(booking.weight ?? ""));
      setFreight(String(booking.freight ?? ""));
      setStatus(booking.status ?? "Booked");

      window.scrollTo({
        top: 0,
        behavior: "smooth",
      });
    }}
    className="bg-yellow-500 hover:bg-yellow-600 text-white px-4 py-2 rounded-lg"
  >
    {t("common.actions.edit")}
  </button>
 <button
 onClick={() => printBookingSlip(booking)}
  className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg"
>
  {t("common.actions.print")}
</button>
</div>
                </div>
              ))}
            </div>
          )}
        </div>

      </div>
           <BookingSlip
  ref={printRef}
  booking={selectedBooking}
/>
{modulePrint.dialog}
    </main>
  );
}
