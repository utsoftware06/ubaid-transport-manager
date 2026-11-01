import { Suspense } from "react";

import BiltyManager from "@/components/bilty/BiltyManager";

export default function BiltyPage() {
  return (
    <Suspense fallback={null}>
      <BiltyManager />
    </Suspense>
  );
}
