import { cookies } from "next/headers";

import ResetPasswordForm from "@/components/auth/ResetPasswordForm";
import {
  isValidRecoveryContext,
  RECOVERY_CONTEXT_COOKIE,
} from "@/lib/auth/recovery-context";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type ResetPasswordPageProps = {
  searchParams: Promise<{ error?: string | string[] }>;
};

export default async function ResetPasswordPage({
  searchParams,
}: ResetPasswordPageProps) {
  const params = await searchParams;
  const invalidLink = params.error === "invalid-link";
  let recoveryVerified = false;

  if (!invalidLink) {
    try {
      const cookieStore = await cookies();
      const recoveryContext = cookieStore.get(RECOVERY_CONTEXT_COOKIE)?.value;
      const supabase = await createSupabaseServerClient();
      const [
        {
          data: { user },
          error: userError,
        },
        {
          data: { session },
        },
      ] = await Promise.all([supabase.auth.getUser(), supabase.auth.getSession()]);

      recoveryVerified = Boolean(
        !userError &&
          user &&
          session &&
          isValidRecoveryContext(
            recoveryContext,
            user.id,
            session.access_token
          )
      );
    } catch {
      recoveryVerified = false;
    }
  }

  return <ResetPasswordForm recoveryVerified={recoveryVerified} />;
}
