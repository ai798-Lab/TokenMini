import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue, type StatementSync } from "node:sqlite";
import test from "node:test";
import { handleAPI } from "../worker/api.ts";
import type {
  D1AllResult,
  D1DatabaseLike,
  D1PreparedStatement,
  D1RunResult,
  Env,
} from "../worker/types.ts";
import { shanghaiDayKey, weekStartKey } from "../worker/util.ts";

function sqliteValue(value: unknown): SQLInputValue {
  if (value === null || typeof value === "string" || typeof value === "number"
      || typeof value === "bigint" || value instanceof Uint8Array) return value;
  throw new TypeError(`Unsupported SQLite value: ${typeof value}`);
}

class SQLiteStatement implements D1PreparedStatement {
  private values: SQLInputValue[] = [];

  constructor(private readonly statement: StatementSync) {}

  bind(...values: unknown[]): D1PreparedStatement {
    this.values = values.map(sqliteValue);
    return this;
  }

  async first<T>(): Promise<T | null> {
    return (this.statement.get(...this.values) as T | undefined) ?? null;
  }

  async all<T>(): Promise<D1AllResult<T>> {
    return { success: true, results: this.statement.all(...this.values) as T[] };
  }

  async run(): Promise<D1RunResult> {
    const result = this.statement.run(...this.values);
    return { success: true, meta: { changes: Number(result.changes) } };
  }
}

class SQLiteDB implements D1DatabaseLike {
  readonly raw = new DatabaseSync(":memory:");

  constructor() {
    const migration = readFileSync(new URL("../drizzle/0001_rankings.sql", import.meta.url), "utf8");
    this.raw.exec(migration);
  }

  prepare(query: string): D1PreparedStatement {
    return new SQLiteStatement(this.raw.prepare(query));
  }

  async batch(statements: D1PreparedStatement[]): Promise<D1RunResult[]> {
    this.raw.exec("BEGIN");
    try {
      const results = await Promise.all(statements.map((statement) => statement.run()));
      this.raw.exec("COMMIT");
      return results;
    } catch (error) {
      this.raw.exec("ROLLBACK");
      throw error;
    }
  }

  close() { this.raw.close(); }
}

function env(db: D1DatabaseLike, overrides: Partial<Env> = {}): Env {
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

async function login(db: SQLiteDB, subject = "google-person") {
  const response = await handleAPI(
    new Request("https://example.test/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id_token: "verified-by-test", app_version: "0.10.0 (3)" }),
    }),
    env(db),
    async () => ({ subject, email: `${subject}@example.com`, name: "和平" }),
  );
  assert.equal(response?.status, 200);
  return await response?.json() as {
    access_token: string;
    refresh_token: string;
    profile: { id: string; display_mode: string; name: string };
  };
}

function authorizedRequest(path: string, accessToken: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("authorization", `Bearer ${accessToken}`);
  if (init.body) headers.set("content-type", "application/json");
  return new Request(`https://example.test${path}`, { ...init, headers });
}

test("public ranking stays readable without login and protects masked names", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const day = weekStartKey();
  const now = new Date().toISOString();
  db.raw.exec(`
    INSERT INTO profiles VALUES
      ('p1', 's1', 'one@example.com', '和平', 'masked', '${now}', NULL, NULL, 'v1', '0.10.0', '${now}', '${now}'),
      ('p2', 's2', 'two@example.com', '公开用户', 'public', '${now}', NULL, NULL, 'v1', '0.10.0', '${now}', '${now}');
    INSERT INTO daily_usage VALUES
      ('p1', '${day}', 200, 3000000, 'test', '0.10.0', '${now}', '${now}'),
      ('p2', '${day}', 100, 1000000, 'test', '0.10.0', '${now}', '${now}');
  `);

  const response = await handleAPI(
    new Request("https://example.test/api/v1/rankings?metric=tokens"), env(db),
  );
  assert.equal(response?.status, 200);
  const body = await response?.json() as {
    entries: Array<{ rank: number; name: string; value: number }>;
  };
  assert.deepEqual(body.entries, [
    { rank: 1, name: "＊＊＊平", value: 200 },
    { rank: 2, name: "公开用户", value: 100 },
  ]);
  assert.equal(JSON.stringify(body).includes("@example.com"), false);
});

test("member can upload summaries, change visibility, then leave with all ranking data removed", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const auth = await login(db);
  const upload = await handleAPI(
    authorizedRequest("/api/v1/me/daily-usage", auth.access_token, {
      method: "PUT",
      body: JSON.stringify({
        local_day: shanghaiDayKey(),
        total_tokens: 123456,
        estimated_cost_micro_usd: 789000,
        pricing_version: "2026-07-06",
        app_version: "0.10.0 (3)",
      }),
    }),
    env(db),
  );
  assert.equal(upload?.status, 200);

  const display = await handleAPI(
    authorizedRequest("/api/v1/me/display-mode", auth.access_token, {
      method: "PATCH",
      body: JSON.stringify({ display_mode: "public" }),
    }),
    env(db),
  );
  assert.equal(display?.status, 200);

  const mine = await handleAPI(
    authorizedRequest("/api/v1/rankings/me", auth.access_token), env(db),
  );
  assert.equal(mine?.status, 200);
  const mineBody = await mine?.json() as {
    profile: { display_mode: string };
    tokens: { rank: number; value: number };
    cost: { rank: number; value: number };
  };
  assert.equal(mineBody.profile.display_mode, "public");
  assert.deepEqual(mineBody.tokens, { rank: 1, value: 123456 });
  assert.deepEqual(mineBody.cost, { rank: 1, value: 789000 });

  const leave = await handleAPI(
    authorizedRequest("/api/v1/me/ranking", auth.access_token, { method: "DELETE" }), env(db),
  );
  assert.equal(leave?.status, 200);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS count FROM daily_usage").get().count, 0);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS count FROM refresh_sessions").get().count, 0);

  const staleUpload = await handleAPI(
    authorizedRequest("/api/v1/me/daily-usage", auth.access_token, {
      method: "PUT",
      body: JSON.stringify({
        local_day: shanghaiDayKey(), total_tokens: 1, estimated_cost_micro_usd: 1,
      }),
    }),
    env(db),
  );
  assert.equal(staleUpload?.status, 409);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS count FROM daily_usage").get().count, 0);
});

test("refresh tokens rotate and an already-used token cannot be replayed", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const auth = await login(db, "refresh-member");
  const refresh = (token: string) => handleAPI(
    new Request("https://example.test/api/v1/auth/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: token }),
    }),
    env(db),
  );

  const first = await refresh(auth.refresh_token);
  assert.equal(first?.status, 200);
  const firstBody = await first?.json() as { access_token: string; refresh_token: string };
  assert.notEqual(firstBody.refresh_token, auth.refresh_token);
  assert.equal(typeof firstBody.access_token, "string");

  const replay = await refresh(auth.refresh_token);
  assert.equal(replay?.status, 401);
  const second = await refresh(firstBody.refresh_token);
  assert.equal(second?.status, 200);
});

test("usage upload rejects malformed values and stores only aggregate columns", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const auth = await login(db, "invalid-usage");
  const response = await handleAPI(
    authorizedRequest("/api/v1/me/daily-usage", auth.access_token, {
      method: "PUT",
      body: JSON.stringify({
        local_day: shanghaiDayKey(),
        total_tokens: -1,
        estimated_cost_micro_usd: 10,
        session_text: "must never be accepted",
      }),
    }),
    env(db),
  );
  assert.equal(response?.status, 400);
  assert.equal(db.raw.prepare("SELECT COUNT(*) AS count FROM daily_usage").get().count, 0);

  const valid = await handleAPI(
    authorizedRequest("/api/v1/me/daily-usage", auth.access_token, {
      method: "PUT",
      body: JSON.stringify({
        local_day: shanghaiDayKey(),
        total_tokens: 42,
        estimated_cost_micro_usd: 10,
        session_text: "must never be stored",
        project_path: "/private/project",
      }),
    }),
    env(db),
  );
  assert.equal(valid?.status, 200);
  const stored = db.raw.prepare("SELECT * FROM daily_usage").get();
  assert.equal(stored.total_tokens, 42);
  assert.equal("session_text" in stored, false);
  assert.equal("project_path" in stored, false);
});

test("admin overview reports ranking-member usage without counting admin-only login", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const member = await login(db, "ranking-member");
  const upload = await handleAPI(
    authorizedRequest("/api/v1/me/daily-usage", member.access_token, {
      method: "PUT",
      body: JSON.stringify({
        local_day: shanghaiDayKey(), total_tokens: 100, estimated_cost_micro_usd: 200,
        app_version: "0.10.0 (3)", pricing_version: "2026-07-06",
      }),
    }),
    env(db),
  );
  assert.equal(upload?.status, 200);

  const adminLogin = await handleAPI(
    new Request("https://example.test/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id_token: "verified-admin", purpose: "admin", app_version: "web-admin" }),
    }),
    env(db, { ADMIN_EMAILS: "owner@example.com" }),
    async () => ({ subject: "google-owner", email: "owner@example.com", name: "Owner" }),
  );
  assert.equal(adminLogin?.status, 200);
  const admin = await adminLogin?.json() as { access_token: string };
  const overview = await handleAPI(
    authorizedRequest("/api/v1/admin/overview", admin.access_token),
    env(db, { ADMIN_EMAILS: "owner@example.com" }),
  );
  assert.equal(overview?.status, 200);
  const body = await overview?.json() as {
    members: number;
    dau: number;
    retention: { d1: number | null; d7: number | null; d30: number | null };
    versions: Array<{ app_version: string; count: number }>;
    metric_scope: string;
  };
  assert.equal(body.members, 1);
  assert.equal(body.dau, 1);
  assert.deepEqual(body.versions, [{ app_version: "0.10.0 (3)", count: 1 }]);
  assert.equal(body.metric_scope, "ranking_members");
  assert.deepEqual(body.retention, { d1: null, d7: null, d30: null });
});

test("configuration remains public but reports login unavailable until OAuth is configured", async (t) => {
  const db = new SQLiteDB();
  t.after(() => db.close());
  const response = await handleAPI(
    new Request("https://example.test/api/v1/config"),
    env(db, { GOOGLE_DESKTOP_CLIENT_ID: undefined, GOOGLE_WEB_CLIENT_ID: undefined }),
  );
  assert.equal(response?.status, 200);
  assert.deepEqual(await response?.json(), {
    google_desktop_client_id: null,
    google_web_client_id: null,
    auth_ready: false,
  });
});
