import { forwardRef } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import type { Booking } from "./types";
import { usePrintAddaName } from "@/lib/print/usePrintAddaName";

type BookingSlipProps = {
  booking: Booking | null;
};

const BookingSlip = forwardRef<HTMLDivElement, BookingSlipProps>(
  ({ booking }, ref) => {
  const { t, dir, language } = useLanguage();
  const addaName = usePrintAddaName(booking?.adda_id, language === "ur" ? "ur" : "en");
  if (!booking) return null;

  return (
    <div
  ref={ref}
  id="booking-slip"
  dir={dir}
  lang={language}
  className="bg-white text-black p-8"
>
      <div className="border-2 border-black p-6">
        <h1 className="text-3xl font-bold text-center">
          {addaName}
        </h1>

        <p className="text-center mb-6">
          {t("bookings.receipt.title")}
        </p>

        <hr className="my-4" />

        <div className="grid grid-cols-2 gap-4">

          <p>
            <strong>{t("bookings.receipt.biltyNo")}:</strong>{" "}
            <span dir="ltr">{booking.booking_no}</span>
          </p>

          <p>
            <strong>{t("common.date")}:</strong>{" "}
            <span dir="ltr">{booking.booking_date}</span>
          </p>

          <p>
            <strong>{t("bookings.party")}:</strong>{" "}
            {booking.parties?.name ?? booking.sender_name}
          </p>

          <p>
            <strong>{t("bookings.sender")}:</strong>{" "}
            {booking.sender_name}
          </p>

          <p>
            <strong>{t("bookings.receiver")}:</strong>{" "}
            {booking.receiver_name}
          </p>

          <p>
            <strong>{t("bookings.from")}:</strong>{" "}
            {booking.from_city}
          </p>

          <p>
            <strong>{t("bookings.to")}:</strong>{" "}
            {booking.to_city}
          </p>

          <p>
            <strong>{t("bookings.goods")}:</strong>{" "}
            {booking.goods_name}
          </p>

          <p>
            <strong>{t("common.weight")}:</strong>{" "}
            <span dir="ltr">{booking.weight}</span>
          </p>

          <p>
            <strong>{t("common.quantity")}:</strong>{" "}
            <span dir="ltr">{booking.quantity}</span>
          </p>

          <p>
            <strong>{t("common.freight")}:</strong>{" "}
            <span dir="ltr">Rs. {booking.freight}</span>
          </p>

        </div>

        <div className="mt-16 flex justify-between">

          <div>
            ___________________
            <br />
            {t("bookings.receipt.senderSignature")}
          </div>

          <div>
            ___________________
            <br />
            {t("bookings.receipt.receiverSignature")}
          </div>

        </div>

      </div>
    </div>
    );
});

BookingSlip.displayName = "BookingSlip";

export default BookingSlip;
