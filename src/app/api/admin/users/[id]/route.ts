import { USER_ROLES } from "@/config/navigation";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import {
  adminApiError,
  authorizeSuperAdmin,
  isLinkedRecordError,
  UUID_PATTERN,
  validateAddaExists,
} from "@/lib/users/admin-user-api";

type RouteContext = {
  params: Promise<{ id: string }>;
};

type RequestRecord = Record<string, unknown>;

type UpdateUserRequest = {
  fullName: string;
  role: typeof USER_ROLES.addaAdmin | typeof USER_ROLES.operator;
  addaId: string;
  isActive: boolean;
};

function isRequestRecord(value: unknown): value is RequestRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseUpdateRequest(body: unknown):
  | { data: UpdateUserRequest; error: null }
  | { data: null; error: Response } {
  if (!isRequestRecord(body)) {
    return {
      data: null,
      error: adminApiError(
        "A valid JSON request body is required.",
        400,
        "INVALID_REQUEST"
      ),
    };
  }

  const fullName =
    typeof body.fullName === "string" ? body.fullName.trim() : "";
  const role = body.role;
  const addaId = typeof body.addaId === "string" ? body.addaId.trim() : "";
  const isActive = body.isActive;

  if (!fullName) {
    return {
      data: null,
      error: adminApiError(
        "Full name is required.",
        400,
        "FULL_NAME_REQUIRED"
      ),
    };
  }

  if (role !== USER_ROLES.addaAdmin && role !== USER_ROLES.operator) {
    return {
      data: null,
      error: adminApiError(
        "Only Adda Admin or Operator may be assigned.",
        400,
        "INVALID_MANAGED_ROLE"
      ),
    };
  }

  if (!addaId) {
    return {
      data: null,
      error: adminApiError(
        "An Adda is required for this role.",
        400,
        "ADDA_REQUIRED"
      ),
    };
  }

  if (!UUID_PATTERN.test(addaId)) {
    return {
      data: null,
      error: adminApiError(
        "Select a valid Adda.",
        400,
        "INVALID_ADDA"
      ),
    };
  }

  if (typeof isActive !== "boolean") {
    return {
      data: null,
      error: adminApiError(
        "Active status must be true or false.",
        400,
        "INVALID_ACTIVE_STATUS"
      ),
    };
  }

  return {
    data: { fullName, role, addaId, isActive },
    error: null,
  };
}

export async function PATCH(request: Request, context: RouteContext) {
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

    const parsed = parseUpdateRequest(body);
    if (parsed.error) return parsed.error;

    const { data: targetProfile, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, is_active")
      .eq("id", id)
      .maybeSingle();

    if (targetError) {
      console.error("Unable to load the target user profile:", targetError);
      return adminApiError(
        "Unable to load the selected user.",
        500,
        "TARGET_USER_LOAD_FAILED"
      );
    }

    if (!targetProfile) {
      return adminApiError("The selected user was not found.", 404, "USER_NOT_FOUND");
    }

    if (
      id === authorization.callerId &&
      targetProfile.is_active === true &&
      parsed.data.isActive === false
    ) {
      return adminApiError(
        "You cannot deactivate your own account.",
        409,
        "SELF_DEACTIVATION_FORBIDDEN"
      );
    }

    if (targetProfile.role === USER_ROLES.superAdmin) {
      return adminApiError(
        "Super Admin accounts are protected.",
        409,
        "PROTECTED_SUPER_ADMIN"
      );
    }

    const addaValidationError = await validateAddaExists(
      adminClient,
      parsed.data.addaId
    );
    if (addaValidationError) return addaValidationError;

    const { data: updatedProfile, error: updateError } = await adminClient
      .from("profiles")
      .update({
        full_name: parsed.data.fullName,
        role: parsed.data.role,
        adda_id: parsed.data.addaId,
        is_active: parsed.data.isActive,
      })
      .eq("id", id)
      .select(
        "id, full_name, role, adda_id, is_active, created_at, updated_at"
      )
      .single();

    if (updateError) {
      console.error("Unable to update the managed user:", updateError);
      return adminApiError(
        "Unable to update the user.",
        500,
        "USER_UPDATE_FAILED"
      );
    }

    return Response.json({ success: true, user: updatedProfile });
  } catch (error) {
    console.error("Unexpected managed-user update failure:", error);
    return adminApiError(
      "Unable to update the user.",
      500,
      "USER_UPDATE_FAILED"
    );
  }
}

export async function DELETE(request: Request, context: RouteContext) {
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

    if (id === authorization.callerId) {
      return adminApiError(
        "You cannot delete your own account.",
        409,
        "SELF_DELETE_FORBIDDEN"
      );
    }

    const { data: targetProfile, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role")
      .eq("id", id)
      .maybeSingle();

    if (targetError) {
      console.error("Unable to load the target user profile:", targetError);
      return adminApiError(
        "Unable to load the selected user.",
        500,
        "TARGET_USER_LOAD_FAILED"
      );
    }

    if (!targetProfile) {
      return adminApiError("The selected user was not found.", 404, "USER_NOT_FOUND");
    }

    if (targetProfile.role === USER_ROLES.superAdmin) {
      return adminApiError(
        "Super Admin accounts cannot be deleted.",
        409,
        "PROTECTED_SUPER_ADMIN"
      );
    }

    if (
      targetProfile.role !== USER_ROLES.addaAdmin &&
      targetProfile.role !== USER_ROLES.operator
    ) {
      return adminApiError(
        "Only Adda Admin or Operator accounts may be deleted.",
        409,
        "UNSUPPORTED_TARGET_ROLE"
      );
    }

    const { error: deleteError } =
      await adminClient.auth.admin.deleteUser(id);

    if (deleteError) {
      console.error("Unable to delete the managed Auth user:", deleteError);

      if (
        isLinkedRecordError(deleteError) ||
        deleteError.message.includes("23503") ||
        /foreign key/i.test(deleteError.message)
      ) {
        return adminApiError(
          "This user is linked to existing records and cannot be deleted.",
          409,
          "USER_HAS_LINKED_RECORDS"
        );
      }

      return adminApiError(
        "Unable to delete the user.",
        500,
        "USER_DELETE_FAILED"
      );
    }

    return Response.json({ success: true, deletedUserId: id });
  } catch (error) {
    console.error("Unexpected managed-user deletion failure:", error);
    return adminApiError(
      "Unable to delete the user.",
      500,
      "USER_DELETE_FAILED"
    );
  }
}
