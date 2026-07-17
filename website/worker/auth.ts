import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTPayload } from "jose";
import type { D1DatabaseLike, Env } from "./types";
import { adminEmails, randomToken, sha256Hex } from "./util";

const googleJWKs = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));
const issuer = "macpulse";
const audience = "macpulse-api";

export interface GoogleIdentity {
  subject: string;
  email: string;
  name?: string;
}

export interface SessionIdentity {
  userID: string;
  email: string;
  admin: boolean;
}

function configuredAudiences(env: Env): string[] {
  return [env.GOOGLE_DESKTOP_CLIENT_ID, env.GOOGLE_WEB_CLIENT_ID]
    .map((value) => value?.trim())
    .filter((value): value is string => Boolean(value));
}

function signingKey(env: Env): Uint8Array {
  const value = env.SESSION_SIGNING_KEY?.trim() ?? "";
  if (value.length < 32) throw new Error("SESSION_SIGNING_KEY is not configured");
  return new TextEncoder().encode(value);
}

export async function verifyGoogleIDToken(idToken: string, env: Env): Promise<GoogleIdentity> {
  const audiences = configuredAudiences(env);
  if (audiences.length === 0) throw new Error("Google OAuth client IDs are not configured");

  const { payload } = await jwtVerify(idToken, googleJWKs, {
    issuer: ["https://accounts.google.com", "accounts.google.com"],
    audience: audiences,
  });
  if (typeof payload.sub !== "string" || typeof payload.email !== "string") {
    throw new Error("Google identity is missing required claims");
  }
  if (payload.email_verified === false) throw new Error("Google email is not verified");
  return {
    subject: payload.sub,
    email: payload.email.toLowerCase(),
    name: typeof payload.name === "string" ? payload.name : undefined,
  };
}

export function isAdmin(email: string, env: Env): boolean {
  return adminEmails(env.ADMIN_EMAILS).has(email.toLowerCase());
}

export async function issueAccessToken(identity: SessionIdentity, env: Env): Promise<string> {
  return new SignJWT({ email: identity.email, adm: identity.admin })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(issuer)
    .setAudience(audience)
    .setSubject(identity.userID)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(signingKey(env));
}

export async function verifyAccessToken(token: string, env: Env): Promise<SessionIdentity> {
  const { payload } = await jwtVerify(token, signingKey(env), { issuer, audience });
  return sessionIdentity(payload);
}

function sessionIdentity(payload: JWTPayload): SessionIdentity {
  if (typeof payload.sub !== "string" || typeof payload.email !== "string") {
    throw new Error("Session token is missing required claims");
  }
  return { userID: payload.sub, email: payload.email, admin: payload.adm === true };
}

export async function createRefreshSession(
  db: D1DatabaseLike,
  userID: string,
  now = new Date(),
): Promise<string> {
  const token = randomToken(32);
  const hash = await sha256Hex(token);
  const expires = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
  await db.prepare(
    "INSERT INTO refresh_sessions (token_hash, user_id, expires_at, created_at, last_used_at) VALUES (?, ?, ?, ?, ?)",
  ).bind(hash, userID, expires, now.toISOString(), now.toISOString()).run();
  return token;
}

export async function rotateRefreshSession(
  db: D1DatabaseLike,
  refreshToken: string,
  now = new Date(),
): Promise<{ token: string; userID: string; email: string } | null> {
  const oldHash = await sha256Hex(refreshToken);
  const row = await db.prepare(
    `SELECT r.user_id AS user_id, p.email AS email
       FROM refresh_sessions r
       JOIN profiles p ON p.id = r.user_id
      WHERE r.token_hash = ? AND r.expires_at > ? AND p.left_at IS NULL`,
  ).bind(oldHash, now.toISOString()).first<{ user_id: string; email: string }>();
  if (!row) return null;

  const token = randomToken(32);
  const newHash = await sha256Hex(token);
  const expires = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const result = await db.prepare(
    `UPDATE refresh_sessions
        SET token_hash = ?, expires_at = ?, last_used_at = ?
      WHERE token_hash = ?`,
  ).bind(newHash, expires, now.toISOString(), oldHash).run();
  const changes = result.meta?.changes;
  if (!result.success || (typeof changes === "number" && changes !== 1)) return null;
  return { token, userID: row.user_id, email: row.email };
}
