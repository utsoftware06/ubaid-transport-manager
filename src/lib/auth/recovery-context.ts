import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";

export const RECOVERY_CONTEXT_COOKIE = "ut-password-recovery-context";
export const RECOVERY_CONTEXT_TTL_SECONDS = 60 * 60;

type RecoveryContextPayload = {
  userId: string;
  sessionId: string;
  issuedAt: number;
  expiresAt: number;
};

function getSigningKey() {
  return process.env.SUPABASE_SERVICE_ROLE_KEY;
}

function getSessionId(accessToken: string): string | null {
  try {
    const payloadSegment = accessToken.split(".")[1];
    if (!payloadSegment) return null;

    const claims = JSON.parse(
      Buffer.from(payloadSegment, "base64url").toString("utf8")
    ) as { session_id?: unknown };

    return typeof claims.session_id === "string" ? claims.session_id : null;
  } catch {
    return null;
  }
}

function sign(encodedPayload: string, signingKey: string) {
  return createHmac("sha256", signingKey)
    .update(`ut-password-recovery-context-v1:${encodedPayload}`)
    .digest("base64url");
}

export function createRecoveryContextValue(session: {
  user: { id: string };
  access_token: string;
}): string | null {
  const signingKey = getSigningKey();
  const sessionId = getSessionId(session.access_token);
  if (!signingKey || !sessionId || !session.user.id) return null;

  const issuedAt = Math.floor(Date.now() / 1000);
  const payload: RecoveryContextPayload = {
    userId: session.user.id,
    sessionId,
    issuedAt,
    expiresAt: issuedAt + RECOVERY_CONTEXT_TTL_SECONDS,
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString(
    "base64url"
  );

  return `${encodedPayload}.${sign(encodedPayload, signingKey)}`;
}

export function isValidRecoveryContext(
  value: string | undefined,
  userId: string,
  accessToken: string
): boolean {
  const signingKey = getSigningKey();
  const sessionId = getSessionId(accessToken);
  if (!value || !signingKey || !sessionId) return false;

  const [encodedPayload, providedSignature, extraPart] = value.split(".");
  if (!encodedPayload || !providedSignature || extraPart !== undefined) {
    return false;
  }

  const expectedSignature = Buffer.from(sign(encodedPayload, signingKey));
  const actualSignature = Buffer.from(providedSignature);
  if (
    actualSignature.length !== expectedSignature.length ||
    !timingSafeEqual(actualSignature, expectedSignature)
  ) {
    return false;
  }

  try {
    const payload = JSON.parse(
      Buffer.from(encodedPayload, "base64url").toString("utf8")
    ) as Partial<RecoveryContextPayload>;
    const now = Math.floor(Date.now() / 1000);

    return (
      payload.userId === userId &&
      payload.sessionId === sessionId &&
      typeof payload.issuedAt === "number" &&
      typeof payload.expiresAt === "number" &&
      payload.issuedAt <= now + 60 &&
      payload.expiresAt > now &&
      payload.expiresAt - payload.issuedAt <= RECOVERY_CONTEXT_TTL_SECONDS
    );
  } catch {
    return false;
  }
}
