import { forwardRef } from "react";
type BookingSlipProps = {
  booking: any;
};

const BookingSlip = forwardRef<HTMLDivElement, BookingSlipProps>(
  ({ booking }, ref) => {
  if (!booking) return null;

  return (
    <div
  ref={ref}
  id="booking-slip"
  className="bg-white text-black p-8"
>
      <div className="border-2 border-black p-6">
        <h1 className="text-3xl font-bold text-center">
          UT Software
        </h1>

        <p className="text-center mb-6">
          Bilty Receipt
        </p>

        <hr className="my-4" />

        <div className="grid grid-cols-2 gap-4">

          <p>
            <strong>Bilty No:</strong>{" "}
            {booking.booking_no}
          </p>

          <p>
            <strong>Date:</strong>{" "}
            {booking.booking_date}
          </p>

          <p>
            <strong>Sender:</strong>{" "}
            {booking.sender_name}
          </p>

          <p>
            <strong>Receiver:</strong>{" "}
            {booking.receiver_name}
          </p>

          <p>
            <strong>From:</strong>{" "}
            {booking.from_city}
          </p>

          <p>
            <strong>To:</strong>{" "}
            {booking.to_city}
          </p>

          <p>
            <strong>Goods:</strong>{" "}
            {booking.goods_name}
          </p>

          <p>
            <strong>Weight:</strong>{" "}
            {booking.weight}
          </p>

          <p>
            <strong>Quantity:</strong>{" "}
            {booking.quantity}
          </p>

          <p>
            <strong>Freight:</strong>{" "}
            Rs. {booking.freight}
          </p>

        </div>

        <div className="mt-16 flex justify-between">

          <div>
            ___________________
            <br />
            Sender Signature
          </div>

          <div>
            ___________________
            <br />
            Receiver Signature
          </div>

        </div>

      </div>
    </div>
    );
});

export default BookingSlip;