import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import {
  createRecoveryContextValue,
  RECOVERY_CONTEXT_COOKIE,
  RECOVERY_CONTEXT_TTL_SECONDS,
} from "@/lib/auth/recovery-context";

const INVALID_RECOVERY_PATH = "/reset-password?error=invalid-link";

export async function GET(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const code = request.nextUrl.searchParams.get("code");

  const redirectWithCookies = (path: string) => {
    const redirectResponse = NextResponse.redirect(
      new URL(path, request.url)
    );
    response.cookies.getAll().forEach((cookie) => {
      redirectResponse.cookies.set(cookie);
    });
    redirectResponse.headers.set("Cache-Control", "no-store");
    return redirectResponse;
  };

  const clearRecoveryContext = (redirectResponse: NextResponse) => {
    redirectResponse.cookies.set(RECOVERY_CONTEXT_COOKIE, "", {
      httpOnly: true,
      secure: request.nextUrl.protocol === "https:",
      sameSite: "lax",
      path: "/reset-password",
      maxAge: 0,
    });
    return redirectResponse;
  };

  if (!code || !supabaseUrl || !supabaseAnonKey) {
    return clearRecoveryContext(redirectWithCookies(INVALID_RECOVERY_PATH));
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

  let receivedRecoveryEvent = false;
  const {
    data: { subscription },
  } = supabase.auth.onAuthStateChange((event) => {
    if (event === "PASSWORD_RECOVERY") receivedRecoveryEvent = true;
  });

  try {
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    subscription.unsubscribe();

    if (error || !data.session || !receivedRecoveryEvent) {
      if (data.session && !receivedRecoveryEvent) {
        await supabase.auth.signOut({ scope: "local" });
      }
      return clearRecoveryContext(redirectWithCookies(INVALID_RECOVERY_PATH));
    }

    const recoveryContext = createRecoveryContextValue(data.session);
    if (!recoveryContext) {
      await supabase.auth.signOut({ scope: "local" });
      return clearRecoveryContext(redirectWithCookies(INVALID_RECOVERY_PATH));
    }

    const redirectResponse = redirectWithCookies("/reset-password");
    redirectResponse.cookies.set(
      RECOVERY_CONTEXT_COOKIE,
      recoveryContext,
      {
        httpOnly: true,
        secure: request.nextUrl.protocol === "https:",
        sameSite: "lax",
        path: "/reset-password",
        maxAge: RECOVERY_CONTEXT_TTL_SECONDS,
      }
    );
    return redirectResponse;
  } catch {
    subscription.unsubscribe();
    return clearRecoveryContext(redirectWithCookies(INVALID_RECOVERY_PATH));
  }
}
