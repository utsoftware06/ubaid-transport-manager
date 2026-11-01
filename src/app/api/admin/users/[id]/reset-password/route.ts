import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import {
  adminApiError,
  authorizeSuperAdmin,
  UUID_PATTERN,
} from "@/lib/users/admin-user-api";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function POST(request: Request, context: RouteContext) {
  try {
    const { id } = await context.params;

    if (!UUID_PATTERN.test(id)) {
      return adminApiError("Invalid user identifier.", 400, "INVALID_USER_ID");
    }

    const adminClient = createSupabaseAdminClient();
    const authorization = await authorizeSuperAdmin(request, adminClient);

    if (!authorization.authorized) {
      return authorization.response;
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return adminApiError(
        "A valid JSON request body is required.",
        400,
        "INVALID_JSON"
      );
    }

    const password =
      typeof body === "object" &&
      body !== null &&
      "password" in body &&
      typeof body.password === "string"
        ? body.password
        : "";

    if (!password.trim()) {
      return adminApiError(
        "A temporary password is required.",
        400,
        "PASSWORD_REQUIRED"
      );
    }

    if (password.length < 8) {
      return adminApiError(
        "Password must contain at least 8 characters.",
        400,
        "PASSWORD_TOO_SHORT"
      );
    }

    const { data: targetProfile, error: targetError } = await adminClient
      .from("profiles")
      .select("id")
      .eq("id", id)
      .maybeSingle();

    if (targetError) {
      console.error("Unable to load password-reset target:", targetError);
      return adminApiError(
        "Unable to load the selected user.",
        500,
        "TARGET_USER_LOAD_FAILED"
      );
    }

    if (!targetProfile) {
      return adminApiError("The selected user was not found.", 404, "USER_NOT_FOUND");
    }

    const { error: resetError } =
      await adminClient.auth.admin.updateUserById(id, { password });

    if (resetError) {
      console.error("Unable to reset the managed user password:", resetError);
      return adminApiError(
        "Unable to reset the password.",
        500,
        "PASSWORD_RESET_FAILED"
      );
    }

    return Response.json({ success: true });
  } catch (error) {
    console.error("Unexpected managed-user password reset failure:", error);
    return adminApiError(
      "Unable to reset the password.",
      500,
      "PASSWORD_RESET_FAILED"
    );
  }
}
