import crypto from "crypto";

// HMAC-signed approval tokens so only the email recipient can approve/reject.
// Payload: proposalId + action + expiry epoch ms.

function sign(secret: string, payload: string): string {
  return crypto.createHmac("sha256", secret).update(payload, "utf8").digest("hex");
}

export function createApprovalToken(
  secret: string,
  proposalId: string,
  action: "approve" | "reject",
  expiresAtMs: number
): string {
  return sign(secret, `${proposalId}:${action}:${expiresAtMs}`);
}

export function verifyApprovalToken(
  secret: string,
  proposalId: string,
  action: string,
  expiresAtMs: number,
  token: string
): boolean {
  if (action !== "approve" && action !== "reject") return false;
  if (!Number.isFinite(expiresAtMs) || Date.now() > expiresAtMs) return false;
  const expected = sign(secret, `${proposalId}:${action}:${expiresAtMs}`);
  if (expected.length !== token.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected, "utf8"), Buffer.from(token, "utf8"));
}
