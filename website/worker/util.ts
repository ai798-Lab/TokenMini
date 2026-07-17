export const rankingTimeZone = "Asia/Shanghai";

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

export function errorResponse(code: string, message: string, status = 400): Response {
  return json({ error: code, message }, status);
}

export function bearerToken(request: Request): string | null {
  const value = request.headers.get("authorization");
  if (!value?.startsWith("Bearer ")) return null;
  const token = value.slice(7).trim();
  return token.length > 0 ? token : null;
}

export function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

export function randomToken(byteCount = 32): string {
  return base64URL(crypto.getRandomValues(new Uint8Array(byteCount)));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function maskNickname(raw: string): string {
  const characters = Array.from(raw.trim());
  if (characters.length <= 1) return "＊＊＊";
  return "＊＊＊" + characters.at(-1);
}

export function publicName(nickname: string, displayMode: string): string {
  return displayMode === "public" ? nickname : maskNickname(nickname);
}

export function safeNickname(name: string | undefined, email: string, subject: string): string {
  const candidate = (name ?? "").trim().replace(/\s+/gu, " ").slice(0, 32);
  if (candidate.length > 0) return candidate;
  const emailName = email.split("@")[0]?.trim().slice(0, 32);
  if (emailName) return emailName;
  return "脉冲用户 " + subject.slice(-4).toUpperCase();
}

export function shanghaiDayKey(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: rankingTimeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

export function weekStartKey(date = new Date()): string {
  const day = shanghaiDayKey(date);
  const utc = new Date(day + "T00:00:00Z");
  const mondayOffset = (utc.getUTCDay() + 6) % 7;
  utc.setUTCDate(utc.getUTCDate() - mondayOffset);
  return utc.toISOString().slice(0, 10);
}

export function isValidDayKey(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value)
    && !Number.isNaN(Date.parse(value + "T00:00:00Z"));
}

export function adminEmails(value: string | undefined): Set<string> {
  return new Set((value ?? "").split(",").map((email) => email.trim().toLowerCase()).filter(Boolean));
}
