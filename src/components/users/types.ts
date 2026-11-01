import { USER_ROLES, type UserRole } from "@/config/navigation";

export type ManagedUser = {
  id: string;
  fullName: string | null;
  email: string | null;
  role: string;
  addaId: string | null;
  addaName: string | null;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
};

export type AddaOption = {
  id: string;
  name: string;
};

export type CreatableUserRole =
  | typeof USER_ROLES.addaAdmin
  | typeof USER_ROLES.operator;

export type CreateUserValues = {
  fullName: string;
  email: string;
  password: string;
  confirmPassword: string;
  role: CreatableUserRole;
  addaId: string;
  isActive: boolean;
};

export type UpdateUserValues = {
  fullName: string;
  role: CreatableUserRole;
  addaId: string;
  isActive: boolean;
};

export type RoleFilter = UserRole | "all";
export type StatusFilter = "all" | "active" | "inactive";

export type UsersListResponse = {
  success: true;
  users: ManagedUser[];
};
