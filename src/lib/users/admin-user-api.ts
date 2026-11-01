import "server-only";

import { USER_ROLES } from "@/config/navigation";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AdminClient = ReturnType<typeof createSupabaseAdminClient>;

export function adminApiError(
  message: string,
  status: number,
  code: string
) {
  return Response.json({ success: false, error: { code, message } }, { status });
}

function getBearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

export async function authorizeSuperAdmin(
  request: Request,
  adminClient: AdminClient
): Promise<
  | { authorized: true; callerId: string }
  | { authorized: false; response: Response }
> {
  const accessToken = getBearerToken(request);

  if (!accessToken) {
    return {
      authorized: false,
      response: adminApiError(
        "Authentication is required.",
        401,
        "AUTHENTICATION_REQUIRED"
      ),
    };
  }

  const {
    data: { user: requestingUser },
    error: authenticationError,
  } = await adminClient.auth.getUser(accessToken);

  if (authenticationError || !requestingUser) {
    if (authenticationError) {
      console.error("Admin user API authentication failed:", authenticationError);
    }

    return {
      authorized: false,
      response: adminApiError(
        "Your session is invalid or has expired.",
        401,
        "INVALID_SESSION"
      ),
    };
  }

  const { data: requestingProfile, error: profileError } = await adminClient
    .from("profiles")
    .select("role, is_active")
    .eq("id", requestingUser.id)
    .maybeSingle();

  if (profileError) {
    console.error("Unable to verify admin profile:", profileError);
    return {
      authorized: false,
      response: adminApiError(
        "Unable to verify your access.",
        500,
        "ACCESS_CHECK_FAILED"
      ),
    };
  }

  if (
    requestingProfile?.role !== USER_ROLES.superAdmin ||
    requestingProfile.is_active !== true
  ) {
    return {
      authorized: false,
      response: adminApiError(
        "You do not have permission to manage users.",
        403,
        "FORBIDDEN"
      ),
    };
  }

  return { authorized: true, callerId: requestingUser.id };
}

export async function validateAddaExists(
  adminClient: AdminClient,
  addaId: string
): Promise<Response | null> {
  const { data: adda, error } = await adminClient
    .from("addas")
    .select("id")
    .eq("id", addaId)
    .maybeSingle();

  if (error) {
    console.error("Unable to validate the selected Adda:", error);
    return adminApiError(
      "Unable to validate the selected Adda.",
      500,
      "ADDA_VALIDATION_FAILED"
    );
  }

  return adda
    ? null
    : adminApiError(
        "The selected Adda does not exist.",
        400,
        "INVALID_ADDA"
      );
}

export function isLinkedRecordError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "23503"
  );
}
