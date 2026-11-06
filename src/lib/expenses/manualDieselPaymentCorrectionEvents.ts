const CORRECTION_EVENT = "ut:manual-diesel-payment-corrected";
const CORRECTION_CHANNEL = "ut-manual-diesel-payment-corrections";

export function publishManualDieselPaymentCorrection() {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new Event(CORRECTION_EVENT));
  if (typeof BroadcastChannel === "undefined") return;
  try {
    const channel = new BroadcastChannel(CORRECTION_CHANNEL);
    channel.postMessage({ type: "refresh" });
    channel.close();
  } catch {
    // Same-tab refresh remains available when BroadcastChannel is unsupported.
  }
}

export function subscribeToManualDieselPaymentCorrections(callback: () => void) {
  if (typeof window === "undefined") return () => undefined;
  const handleSameTab = () => callback();
  window.addEventListener(CORRECTION_EVENT, handleSameTab);
  let channel: BroadcastChannel | null = null;
  if (typeof BroadcastChannel !== "undefined") {
    try {
      channel = new BroadcastChannel(CORRECTION_CHANNEL);
      channel.addEventListener("message", handleSameTab);
    } catch {
      channel = null;
    }
  }
  return () => {
    window.removeEventListener(CORRECTION_EVENT, handleSameTab);
    channel?.removeEventListener("message", handleSameTab);
    channel?.close();
  };
}
