import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function proxy(request: NextRequest) {
  if (process.env.NODE_ENV === "development" && request.nextUrl.pathname === "/voice-recognition-test") {
    return NextResponse.next();
  }

  let response = NextResponse.next({
    request,
  });

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("Supabase public environment variables are missing.");
    return response;
  }

  const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },

      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });

        response = NextResponse.next({
          request,
        });

        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
  });

  /*
   * Is call ko remove na karna.
   * Ye expired session ko refresh karke updated cookies browser ko deta hai.
   */
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const pathname = request.nextUrl.pathname;

  const isDashboardRoute =
    pathname === "/dashboard" ||
    pathname.startsWith("/dashboard/") ||
    pathname.startsWith("/addas") ||
    pathname.startsWith("/audit-logs") ||
    pathname.startsWith("/bookings") ||
    pathname.startsWith("/brokers") ||
    pathname.startsWith("/cashbook") ||
    pathname.startsWith("/customer-ledger") ||
    pathname.startsWith("/diesel") ||
    pathname.startsWith("/drivers") ||
    pathname.startsWith("/drivers-ledger") ||
    pathname.startsWith("/employee-ledger") ||
    pathname.startsWith("/employee-loans") ||
    pathname.startsWith("/employee-salary") ||
    pathname.startsWith("/employees") ||
    pathname.startsWith("/expenses") ||
    pathname.startsWith("/loading") ||
    pathname.startsWith("/loading-details") ||
    pathname.startsWith("/owner-ledger") ||
    pathname.startsWith("/other-addas") ||
    pathname.startsWith("/other-adda-account") ||
    pathname.startsWith("/packing") ||
    pathname.startsWith("/payment-receipts") ||
    pathname.startsWith("/petrol-pump-payments") ||
    pathname.startsWith("/petrol-pumps") ||
    pathname.startsWith("/reports") ||
    pathname.startsWith("/settings") ||
    pathname.startsWith("/vehicle-documents") ||
    pathname.startsWith("/vehicle-ledger") ||
    pathname.startsWith("/vehicles") ||
    pathname.startsWith("/workshop");

  const isRecoveryRoute =
    pathname === "/auth/callback" || pathname === "/reset-password";

  const isAuthRoute =
    pathname === "/login" ||
    pathname === "/register" ||
    pathname === "/forgot-password" ||
    isRecoveryRoute;

  // Login ke baghair dashboard open na ho.
  if (!user && isDashboardRoute) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.searchParams.set("next", pathname);

    return NextResponse.redirect(loginUrl);
  }

  // Login user ko dobara login/register page par na bhejo.
  if (user && isAuthRoute && !isRecoveryRoute) {
    const dashboardUrl = request.nextUrl.clone();
    dashboardUrl.pathname = "/dashboard";
    dashboardUrl.search = "";

    return NextResponse.redirect(dashboardUrl);
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Static files, Next.js internals aur aam image files par Proxy nahi chalega.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
