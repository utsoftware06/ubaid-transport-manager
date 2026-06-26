import { supabase } from "@/lib/supabase/client";
import { Booking } from "@/components/bookings/types";

export async function loadBookings() {
  const { data, error } = await supabase
    .from("bookings")
    .select("*")
    .order("created_at", {
      ascending: false,
    });

  if (error) throw error;

  return data as Booking[];
}

export async function loadAddas() {
  const { data, error } = await supabase
    .from("addas")
    .select("*")
    .order("name");

  if (error) throw error;

  return data;
}

export async function createBooking(
  booking: Omit<Booking, "id" | "created_at">
) {
  const { error } = await supabase
    .from("bookings")
    .insert(booking);

  if (error) throw error;
}

export async function updateBooking(
  id: string,
  booking: Partial<Booking>
) {
  const { error } = await supabase
    .from("bookings")
    .update(booking)
    .eq("id", id);

  if (error) throw error;
}

export async function deleteBooking(id: string) {
  const { error } = await supabase
    .from("bookings")
    .delete()
    .eq("id", id);

  if (error) throw error;
}