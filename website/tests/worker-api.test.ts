import assert from "node:assert/strict";
import test from "node:test";
import { handleAPI } from "../worker/api.ts";
import type {
  D1AllResult,
  D1DatabaseLike,
  D1PreparedStatement,
  D1RunResult,
  Env,
} from "../worker/types.ts";
import { maskNickname, weekStartKey } from "../worker/util.ts";

type Profile = {
  id: string;
  google_sub: string;
  email: string;
  nickname: string;
  display_mode: string;
  joined_at: string;
  left_at: string | null;
  hidden_at: string | null;
};

class FakeStatement implements D1PreparedStatement {
  values: unknown[] = [];
  private readonly db: FakeDB;
  private readonly sql: string;
  constructor(db: FakeDB, sql: string) {
    this.db = db;
    this.sql = sql;
  }

  bind(...values: unknown[]): D1PreparedStatement {
    this.values = values;
    return this;
  }

  async first<T>(): Promise<T | null> {
    if (this.sql.includes("FROM profiles WHERE google_sub")) return this.db.profile as T | null;
    return null;
  }

  async all<T>(): Promise<D1AllResult<T>> {
    return { success: true, results: [] };
  }

  async run(): Promise<D1RunResult> {
    if (this.sql.includes("INSERT INTO profiles")) {
      if (this.sql.includes("'admin'")) {
        const [id, sub, email, nickname, joinedAt, leftAt] = this.values as string[];
        this.db.profile = {
          id, google_sub: sub, email, nickname,
          display_mode: "masked", joined_at: joinedAt, left_at: leftAt, hidden_at: null,
        };
      } else {
        const [id, sub, email, nickname, displayMode, joinedAt] = this.values as string[];
        this.db.profile = {
          id, google_sub: sub, email, nickname,
          display_mode: displayMode, joined_at: joinedAt, left_at: null, hidden_at: null,
        };
      }
    }
    if (this.sql.includes("INSERT INTO refresh_sessions")) this.db.refreshSessionCount += 1;
    return { success: true };
  }
}

class FakeDB implements D1DatabaseLike {
  profile: Profile | null = null;
  refreshSessionCount = 0;
  prepare(query: string): D1PreparedStatement { return new FakeStatement(this, query); }
  async batch(statements: D1PreparedStatement[]): Promise<D1RunResult[]> {
    return Promise.all(statements.map((statement) => statement.run()));
  }
}

function env(db?: FakeDB, overrides: Partial<Env> = {}): Env {
  return {
    ASSETS: { fetch: async () => new Response("not found", { status: 404 }) } as Fetcher,
    IMAGES: {} as Env["IMAGES"],
    DB: db,
    GOOGLE_DESKTOP_CLIENT_ID: "desktop-client.apps.googleusercontent.com",
    GOOGLE_WEB_CLIENT_ID: "web-client.apps.googleusercontent.com",
    SESSION_SIGNING_KEY: "test-only-signing-key-that-is-longer-than-thirty-two-characters",
    ...overrides,
  };
}

test("masks every nickname to a fixed prefix and final character", () => {
  assert.equal(maskNickname("示例用户"), "＊＊＊户");
  assert.equal(maskNickname("A"), "＊＊＊");
  assert.equal(maskNickname(""), "＊＊＊");
});

test("uses Monday in Asia/Shanghai as the weekly boundary", () => {
  assert.equal(weekStartKey(new Date("2026-07-17T07:00:00Z")), "2026-07-13");
  assert.equal(weekStartKey(new Date("2026-07-19T16:30:00Z")), "2026-07-20");
});

test("reports configuration without exposing secrets", async () => {
  const response = await handleAPI(new Request("https://example.test/api/v1/config"), env(new FakeDB()));
  assert.equal(response?.status, 200);
  const body = await response?.json() as Record<string, unknown>;
  assert.equal(body.auth_ready, true);
  assert.equal(body.google_desktop_client_id, "desktop-client.apps.googleusercontent.com");
  assert.equal("session_signing_key" in body, false);
});

test("Google app login automatically joins with a masked profile", async () => {
  const db = new FakeDB();
  const response = await handleAPI(
    new Request("https://example.test/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id_token: "verified-by-test", app_version: "0.10.0 (3)" }),
    }),
    env(db),
    async () => ({ subject: "google-123", email: "person@example.com", name: "示例用户" }),
  );
  assert.equal(response?.status, 200);
  const body = await response?.json() as {
    access_token: unknown;
    refresh_token: unknown;
    profile: { id: string; display_mode: string; name: string };
  };
  assert.equal(typeof body.access_token, "string");
  assert.equal(typeof body.refresh_token, "string");
  assert.equal(body.profile.id, db.profile?.id);
  assert.equal(body.profile.display_mode, "masked");
  assert.equal(body.profile.name, "＊＊＊户");
  assert.equal(db.profile?.left_at, null);
  assert.equal(db.refreshSessionCount, 1);
});

test("admin-only Google login does not inflate ranking membership", async () => {
  const db = new FakeDB();
  const response = await handleAPI(
    new Request("https://example.test/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id_token: "verified-by-test", purpose: "admin", app_version: "web-admin" }),
    }),
    env(db, { ADMIN_EMAILS: "owner@example.com" }),
    async () => ({ subject: "google-owner", email: "owner@example.com", name: "Owner" }),
  );
  assert.equal(response?.status, 200);
  assert.notEqual(db.profile?.left_at, null);
  assert.equal(db.refreshSessionCount, 0);
  const body = await response?.json() as Record<string, unknown>;
  assert.equal("refresh_token" in body, false);
});

test("non-admin Google login through the admin page is rejected without joining", async () => {
  const db = new FakeDB();
  const response = await handleAPI(
    new Request("https://example.test/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id_token: "verified-by-test", purpose: "admin", app_version: "web-admin" }),
    }),
    env(db, { ADMIN_EMAILS: "owner@example.com" }),
    async () => ({ subject: "google-visitor", email: "visitor@example.com", name: "Visitor" }),
  );
  assert.equal(response?.status, 403);
  assert.equal(db.profile, null);
  assert.equal(db.refreshSessionCount, 0);
});
