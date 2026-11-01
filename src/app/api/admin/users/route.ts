import { isUserRole, USER_ROLES, type UserRole } from "@/config/navigation";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import {
  adminApiError as errorResponse,
  authorizeSuperAdmin,
  type AdminClient,
  UUID_PATTERN,
  validateAddaExists,
} from "@/lib/users/admin-user-api";

const ADMIN_PAGE_SIZE = 1000;

type CreateUserRequest = {
  fullName: string;
  email: string;
  password: string;
  role: UserRole;
  addaId: string | null;
  isActive: boolean;
};

type RequestRecord = Record<string, unknown>;

type ProfileRow = {
  id: string;
  full_name: string | null;
  role: string;
  adda_id: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

function isRequestRecord(value: unknown): value is RequestRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readRequiredString(
  body: RequestRecord,
  field: "fullName" | "email" | "password"
): string | null {
  const value = body[field];
  return typeof value === "string" && value.trim() ? value : null;
}

function parseRequestBody(body: unknown):
  | { data: CreateUserRequest; error: null }
  | { data: null; error: Response } {
  if (!isRequestRecord(body)) {
    return {
      data: null,
      error: errorResponse(
        "A valid JSON request body is required.",
        400,
        "INVALID_REQUEST"
      ),
    };
  }

  const fullName = readRequiredString(body, "fullName");
  const email = readRequiredString(body, "email");
  const password = readRequiredString(body, "password");

  if (!fullName) {
    return {
      data: null,
      error: errorResponse(
        "Full name is required.",
        400,
        "FULL_NAME_REQUIRED"
      ),
    };
  }

  if (!email) {
    return {
      data: null,
      error: errorResponse("Email is required.", 400, "EMAIL_REQUIRED"),
    };
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    return {
      data: null,
      error: errorResponse(
        "Enter a valid email address.",
        400,
        "INVALID_EMAIL"
      ),
    };
  }

  if (!password) {
    return {
      data: null,
      error: errorResponse("Password is required.", 400, "PASSWORD_REQUIRED"),
    };
  }

  if (password.length < 8) {
    return {
      data: null,
      error: errorResponse(
        "Password must contain at least 8 characters.",
        400,
        "PASSWORD_TOO_SHORT"
      ),
    };
  }

  if (!isUserRole(body.role)) {
    return {
      data: null,
      error: errorResponse(
        "Select a valid user role.",
        400,
        "INVALID_ROLE"
      ),
    };
  }

  const rawAddaId = body.addaId;
  const addaId =
    typeof rawAddaId === "string" && rawAddaId.trim()
      ? rawAddaId.trim()
      : null;
  const isActive = body.isActive === undefined ? true : body.isActive;

  if (typeof isActive !== "boolean") {
    return {
      data: null,
      error: errorResponse(
        "Active status must be true or false.",
        400,
        "INVALID_ACTIVE_STATUS"
      ),
    };
  }

  if (
    (body.role === USER_ROLES.addaAdmin ||
      body.role === USER_ROLES.operator) &&
    !addaId
  ) {
    return {
      data: null,
      error: errorResponse(
        "An Adda is required for this role.",
        400,
        "ADDA_REQUIRED"
      ),
    };
  }

  if (addaId && !UUID_PATTERN.test(addaId)) {
    return {
      data: null,
      error: errorResponse(
        "Select a valid Adda.",
        400,
        "INVALID_ADDA"
      ),
    };
  }

  return {
    data: {
      fullName: fullName.trim(),
      email: email.trim().toLowerCase(),
      password,
      role: body.role,
      addaId: body.role === USER_ROLES.superAdmin ? null : addaId,
      isActive,
    },
    error: null,
  };
}

async function listAllProfiles(adminClient: AdminClient): Promise<ProfileRow[]> {
  const profiles: ProfileRow[] = [];

  for (let from = 0; ; from += ADMIN_PAGE_SIZE) {
    const { data, error } = await adminClient
      .from("profiles")
      .select(
        "id, full_name, role, adda_id, is_active, created_at, updated_at"
      )
      .order("created_at", { ascending: false })
      .range(from, from + ADMIN_PAGE_SIZE - 1);

    if (error) {
      throw error;
    }

    const page = (data ?? []) as ProfileRow[];
    profiles.push(...page);

    if (page.length < ADMIN_PAGE_SIZE) {
      return profiles;
    }
  }
}

async function listAllAuthEmails(
  adminClient: AdminClient
): Promise<Map<string, string | null>> {
  const emails = new Map<string, string | null>();
  let page = 1;

  while (true) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage: ADMIN_PAGE_SIZE,
    });

    if (error) {
      throw error;
    }

    for (const user of data.users) {
      emails.set(user.id, user.email ?? null);
    }

    if (data.nextPage === null) {
      return emails;
    }

    page = data.nextPage;
  }
}

export async function GET(request: Request) {
  try {
    const adminClient = createSupabaseAdminClient();
    const authorization = await authorizeSuperAdmin(request, adminClient);

    if (!authorization.authorized) {
      return authorization.response;
    }

    const [profiles, authEmails, addasResult] = await Promise.all([
      listAllProfiles(adminClient),
      listAllAuthEmails(adminClient),
      adminClient.from("addas").select("id, name").order("name"),
    ]);

    if (addasResult.error) {
      throw addasResult.error;
    }

    const addaNames = new Map(
      (addasResult.data ?? []).map((adda) => [adda.id, adda.name])
    );

    return Response.json({
      success: true,
      users: profiles.map((profile) => ({
        id: profile.id,
        fullName: profile.full_name,
        email: authEmails.get(profile.id) ?? null,
        role: profile.role,
        addaId: profile.adda_id,
        addaName: profile.adda_id
          ? addaNames.get(profile.adda_id) ?? null
          : null,
        isActive: profile.is_active,
        createdAt: profile.created_at,
        updatedAt: profile.updated_at,
      })),
    });
  } catch (error) {
    console.error("Unable to list managed users:", error);
    return errorResponse(
      "Unable to load users.",
      500,
      "USER_LIST_FAILED"
    );
  }
}

export async function POST(request: Request) {
  try {
    const adminClient = createSupabaseAdminClient();
    const authorization = await authorizeSuperAdmin(request, adminClient);

    if (!authorization.authorized) {
      return authorization.response;
    }

    let requestBody: unknown;

    try {
      requestBody = await request.json();
    } catch {
      return errorResponse(
        "A valid JSON request body is required.",
        400,
        "INVALID_JSON"
      );
    }

    const parsedRequest = parseRequestBody(requestBody);

    if (parsedRequest.error) {
      return parsedRequest.error;
    }

    const { fullName, email, password, role, addaId, isActive } =
      parsedRequest.data;

    if (addaId) {
      const addaValidationError = await validateAddaExists(adminClient, addaId);
      if (addaValidationError) return addaValidationError;
    }

    const { data: createdUserData, error: createUserError } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
        },
      });

    if (createUserError || !createdUserData.user) {
      if (createUserError) {
        console.error("Unable to create Supabase Auth user:", createUserError);
      }

      const duplicateUser =
        createUserError?.code === "email_exists" ||
        createUserError?.code === "user_already_exists";

      return errorResponse(
        duplicateUser
          ? "A user with this email already exists."
          : "Unable to create the user account.",
        duplicateUser ? 409 : 500,
        duplicateUser ? "EMAIL_ALREADY_EXISTS" : "USER_CREATION_FAILED"
      );
    }

    const createdUser = createdUserData.user;
    const { error: profileInsertError } = await adminClient
      .from("profiles")
      .insert({
        id: createdUser.id,
        full_name: fullName,
        role,
        adda_id: addaId,
        is_active: isActive,
      });

    if (profileInsertError) {
      console.error("Unable to create the user profile:", profileInsertError);

      const { error: rollbackError } =
        await adminClient.auth.admin.deleteUser(createdUser.id);

      if (rollbackError) {
        console.error(
          "Unable to roll back Auth user after profile creation failed:",
          rollbackError
        );
      }

      return errorResponse(
        "Unable to complete user creation.",
        500,
        "PROFILE_CREATION_FAILED"
      );
    }

    return Response.json(
      {
        success: true,
        user: {
          id: createdUser.id,
          fullName,
          email,
          role,
          addaId,
          isActive,
        },
      },
      { status: 201 }
    );
  } catch (error) {
    console.error("Unexpected admin user creation failure:", error);
    return errorResponse(
      "Unable to create the user account.",
      500,
      "USER_CREATION_FAILED"
    );
  }
}
