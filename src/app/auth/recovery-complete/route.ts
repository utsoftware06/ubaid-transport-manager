import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { RECOVERY_CONTEXT_COOKIE } from "@/lib/auth/recovery-context";
export async function POST(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const cookieOptions = {
    httpOnly: true,
    secure: request.nextUrl.protocol === "https:",
    sameSite: "lax",
    path: "/reset-password",
    maxAge: 0,
  } as const;

  if (!supabaseUrl || !supabaseAnonKey) {
    const failureResponse = NextResponse.json(
      { success: false },
      { status: 500, headers: { "Cache-Control": "no-store" } }
    );
    failureResponse.cookies.set(RECOVERY_CONTEXT_COOKIE, "", cookieOptions);
    return failureResponse;
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
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
  });

  const { error } = await supabase.auth.signOut({ scope: "local" });
  const finalResponse = NextResponse.json(
    { success: !error },
    {
      status: error ? 500 : 200,
      headers: { "Cache-Control": "no-store" },
    }
  );
  response.cookies.getAll().forEach((cookie) => {
    finalResponse.cookies.set(cookie);
  });
  finalResponse.cookies.set(RECOVERY_CONTEXT_COOKIE, "", cookieOptions);

  return finalResponse;
}
