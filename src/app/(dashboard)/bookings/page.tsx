"use client";

import { useEffect, useState, useRef } from "react";
import { useReactToPrint } from "react-to-print";
import { supabase } from "@/lib/supabase/client";
import BookingSlip from "@/components/bookings/BookingSlip";

export default function BookingsPage() {
  const [addaId, setAddaId] = useState("");
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

  const [addas, setAddas] = useState<any[]>([]);
  const [bookings, setBookings] = useState<any[]>([]);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [selectedBooking, setSelectedBooking] = useState<any | null>(null);
  const printRef = useRef<HTMLDivElement>(null);

const handlePrint = useReactToPrint({
  contentRef: printRef,
});

  async function loadAddas() {
    const { data } = await supabase
      .from("addas")
      .select("*")
      .order("name");

    if (data) {
      setAddas(data);
    }
  }

  async function loadBookings() {
    const { data } = await supabase
      .from("bookings")
      .select("*")
      .order("created_at", {
        ascending: false,
      });

    if (data) {
      setBookings(data);
    }
  }

  useEffect(() => {
    loadAddas();
    loadBookings();
  }, []);
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

  let error;

  if (editingId) {
    // UPDATE
    const result = await supabase
      .from("bookings")
      .update({
        adda_id: addaId,
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
        adda_id: addaId,
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
    alert(error.message);
    return;
  }

  alert(
    editingId
      ? "Booking updated successfully!"
      : "Booking saved successfully!"
  );

  setEditingId(null);

  setAddaId("");
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
}

  return (
    <main className="min-h-screen bg-slate-100 p-8">
      <div className="max-w-4xl mx-auto bg-white p-8 rounded-xl shadow-md">
        <h1 className="text-4xl font-bold text-center mb-8 text-gray-900">
          Create Bilty
        </h1>

        <form
          onSubmit={handleSaveBooking}
          className="space-y-4"
        >
          <select
            value={addaId}
            onChange={(e) =>
              setAddaId(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
            required
          >
            <option value="">
              Select Adda
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

          <input
            type="text"
            placeholder="Bilty Number"
            value={bookingNo}
            onChange={(e) =>
              setBookingNo(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
            required
          />

          <input
            type="date"
            value={bookingDate}
            onChange={(e) =>
              setBookingDate(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="Sender Name"
            value={senderName}
            onChange={(e) =>
              setSenderName(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="Sender Phone"
            value={senderPhone}
            onChange={(e) =>
              setSenderPhone(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="Receiver Name"
            value={receiverName}
            onChange={(e) =>
              setReceiverName(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="Receiver Phone"
            value={receiverPhone}
            onChange={(e) =>
              setReceiverPhone(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="From City"
            value={fromCity}
            onChange={(e) =>
              setFromCity(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="To City"
            value={toCity}
            onChange={(e) =>
              setToCity(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="text"
            placeholder="Goods Name"
            value={goodsName}
            onChange={(e) =>
              setGoodsName(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="number"
            placeholder="Quantity"
            value={quantity}
            onChange={(e) =>
              setQuantity(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="number"
            placeholder="Weight"
            value={weight}
            onChange={(e) =>
              setWeight(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <input
            type="number"
            placeholder="Freight"
            value={freight}
            onChange={(e) =>
              setFreight(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          />

          <select
            value={status}
            onChange={(e) =>
              setStatus(e.target.value)
            }
            className="w-full border p-3 rounded-lg text-gray-700"
          >
            <option>Booked</option>
            <option>In Transit</option>
            <option>Delivered</option>
          </select>

         <button
  type="submit"
  className={`w-full p-3 rounded-lg text-white ${
    editingId
      ? "bg-yellow-600 hover:bg-yellow-700"
      : "bg-blue-600 hover:bg-blue-700"
  }`}
>
  {editingId ? "Update Bilty" : "Save Bilty"}
</button>
        </form>

        <div className="mt-10">
          <h2 className="text-2xl font-bold mb-4 text-gray-900">
            Bilty List
          </h2>
        <input
  type="text"
  placeholder="Search Bilty No, Sender or Receiver"
  value={search}
  onChange={(e) => setSearch(e.target.value)}
  className="w-full border p-3 rounded-lg mb-6 text-gray-700 placeholder:text-gray-500"
/>
          {bookings.length === 0 ? (
            <p className="text-gray-600">
              No bookings found.
            </p>
          ) : (
            <div className="space-y-4">
              {filteredBookings.map((booking) => (
                <div
                  key={booking.id}
                  className="border rounded-lg p-4"
                >
                  <h3 className="text-xl font-semibold text-gray-900">
                    {booking.booking_no}
                  </h3>

                  <p className="text-gray-700">
                    Sender:{" "}
                    {booking.sender_name}
                  </p>

                  <p className="text-gray-700">
                    Receiver:{" "}
                    {booking.receiver_name}
                  </p>

                  <p className="text-gray-700">
                    Route:{" "}
                    {booking.from_city} →{" "}
                    {booking.to_city}
                  </p>

                  <p className="text-gray-700">
                    Freight:{" "}
                    {booking.freight}
                  </p>

                  <p className="text-gray-700">
                    Status: {booking.status}
                  </p>
                  <div className="mt-4">
  <button
    onClick={() => {
      setEditingId(booking.id);

      setAddaId(booking.adda_id ?? "");
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
    ✏ Edit
  </button>
 <button
 onClick={() => {
  setSelectedBooking(booking);

  setTimeout(() => {
    handlePrint();
  }, 100);
}}
  className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg"
>
  🖨 Print
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
    </main>
  );
}