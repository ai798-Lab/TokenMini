import type { D1DatabaseLike, Env } from "./types";
import {
  createRefreshSession,
  isAdmin,
  issueAccessToken,
  rotateRefreshSession,
  verifyAccessToken,
  verifyGoogleIDToken,
  type GoogleIdentity,
  type SessionIdentity,
} from "./auth";
import {
  bearerToken,
  errorResponse,
  isValidDayKey,
  json,
  publicName,
  safeNickname,
  shanghaiDayKey,
  weekStartKey,
} from "./util";

interface ProfileRow {
  id: string;
  email: string;
  nickname: string;
  display_mode: string;
  joined_at: string;
  left_at: string | null;
  hidden_at: string | null;
}

interface LeaderboardRow extends ProfileRow {
  value: number;
}

type GoogleVerifier = (token: string, env: Env) => Promise<GoogleIdentity>;

export async function handleAPI(
  request: Request,
  env: Env,
  verifyGoogle: GoogleVerifier = verifyGoogleIDToken,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/api/v1/")) return null;

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": url.origin,
        "access-control-allow-headers": "authorization, content-type",
        "access-control-allow-methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
      },
    });
  }

  if (url.pathname === "/api/v1/health") {
    return json({ ok: true, database: Boolean(env.DB), auth: authReady(env) });
  }
  if (url.pathname === "/api/v1/config") {
    return json({
      google_desktop_client_id: env.GOOGLE_DESKTOP_CLIENT_ID?.trim() || null,
      google_web_client_id: env.GOOGLE_WEB_CLIENT_ID?.trim() || null,
      auth_ready: authReady(env),
    });
  }

  const db = env.DB;
  if (!db) return errorResponse("database_unavailable", "排行榜数据库尚未配置", 503);

  try {
    if (url.pathname === "/api/v1/auth/google" && request.method === "POST") {
      return await googleLogin(request, env, db, verifyGoogle);
    }
    if (url.pathname === "/api/v1/auth/refresh" && request.method === "POST") {
      return await refreshSession(request, env, db);
    }
    if (url.pathname === "/api/v1/rankings" && request.method === "GET") {
      return await publicRankings(url, db);
    }

    const session = await requireSession(request, env);
    if (session instanceof Response) return session;

    if (url.pathname === "/api/v1/rankings/me" && request.method === "GET") {
      return await myRankings(session, db);
    }
    if (url.pathname === "/api/v1/me/daily-usage" && request.method === "PUT") {
      return await upsertDailyUsage(request, session, db);
    }
    if (url.pathname === "/api/v1/me/display-mode" && request.method === "PATCH") {
      return await updateDisplayMode(request, session, db);
    }
    if (url.pathname === "/api/v1/me/ranking" && request.method === "DELETE") {
      return await leaveRanking(session, db);
    }
    if (url.pathname === "/api/v1/admin/overview" && request.method === "GET") {
      return await adminOverview(session, env, db);
    }
    if (url.pathname === "/api/v1/admin/users" && request.method === "GET") {
      return await adminUsers(session, env, db);
    }
    const hiddenMatch = url.pathname.match(/^\/api\/v1\/admin\/users\/([^/]+)\/hidden$/u);
    if (hiddenMatch && request.method === "PATCH") {
      return await setUserHidden(request, session, env, db, hiddenMatch[1]);
    }
    return errorResponse("not_found", "接口不存在", 404);
  } catch (error) {
    console.error("[api]", error instanceof Error ? error.message : "unexpected error");
    return errorResponse("server_error", "服务暂时不可用，请稍后重试", 500);
  }
}

function authReady(env: Env): boolean {
  return Boolean(
    env.DB && env.SESSION_SIGNING_KEY?.trim()
      && (env.GOOGLE_DESKTOP_CLIENT_ID?.trim() || env.GOOGLE_WEB_CLIENT_ID?.trim()),
  );
}

async function bodyJSON(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const value = await request.json();
    return value && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

async function googleLogin(
  request: Request,
  env: Env,
  db: D1DatabaseLike,
  verifyGoogle: GoogleVerifier,
): Promise<Response> {
  const body = await bodyJSON(request);
  const token = typeof body?.id_token === "string" ? body.id_token : "";
  if (!token) return errorResponse("invalid_request", "缺少 Google 登录凭证");

  const identity = await verifyGoogle(token, env);
  const now = new Date().toISOString();
  const adminRequested = body?.purpose === "admin";
  const adminOnly = adminRequested && isAdmin(identity.email, env);
  if (adminRequested && !adminOnly) {
    return errorResponse("forbidden", "该 Google 账号没有后台权限", 403);
  }
  const displayMode = body?.display_mode === "public" ? "public" : "masked";
  const appVersion = typeof body?.app_version === "string" ? body.app_version.slice(0, 32) : null;
  const id = crypto.randomUUID();
  const nickname = safeNickname(identity.name, identity.email, identity.subject);

  if (adminOnly) {
    await db.prepare(
      `INSERT INTO profiles
       (id, google_sub, email, nickname, display_mode, joined_at, left_at, consent_version,
        last_app_version, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'masked', ?, ?, 'admin', ?, ?, ?)
       ON CONFLICT(google_sub) DO UPDATE SET
         email = excluded.email,
         nickname = CASE WHEN profiles.nickname = '' THEN excluded.nickname ELSE profiles.nickname END,
         last_app_version = COALESCE(excluded.last_app_version, profiles.last_app_version),
         updated_at = excluded.updated_at`,
    ).bind(id, identity.subject, identity.email, nickname, now, now, appVersion, now, now).run();
  } else {
    await db.prepare(
      `INSERT INTO profiles
       (id, google_sub, email, nickname, display_mode, joined_at, left_at, consent_version,
        last_app_version, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL, '2026-07-17-v1', ?, ?, ?)
       ON CONFLICT(google_sub) DO UPDATE SET
         email = excluded.email,
         nickname = CASE WHEN profiles.nickname = '' THEN excluded.nickname ELSE profiles.nickname END,
         display_mode = excluded.display_mode,
         joined_at = CASE WHEN profiles.left_at IS NULL THEN profiles.joined_at ELSE excluded.joined_at END,
         left_at = NULL,
         consent_version = excluded.consent_version,
         last_app_version = COALESCE(excluded.last_app_version, profiles.last_app_version),
         updated_at = excluded.updated_at`,
    ).bind(
      id, identity.subject, identity.email, nickname, displayMode, now,
      appVersion, now, now,
    ).run();
  }

  const profile = await db.prepare(
    "SELECT id, email, nickname, display_mode, joined_at, left_at, hidden_at FROM profiles WHERE google_sub = ?",
  ).bind(identity.subject).first<ProfileRow>();
  if (!profile) return errorResponse("profile_error", "无法创建排行榜账号", 500);

  const session: SessionIdentity = {
    userID: profile.id,
    email: profile.email,
    admin: isAdmin(profile.email, env),
  };
  const accessToken = await issueAccessToken(session, env);
  if (adminOnly) {
    return json({
      access_token: accessToken,
      expires_in: 3600,
      profile: serializedProfile(profile),
    });
  }
  const refreshToken = await createRefreshSession(db, profile.id);
  return json({
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: 3600,
    profile: serializedProfile(profile),
  });
}

async function refreshSession(request: Request, env: Env, db: D1DatabaseLike): Promise<Response> {
  const body = await bodyJSON(request);
  const token = typeof body?.refresh_token === "string" ? body.refresh_token : "";
  if (!token) return errorResponse("invalid_request", "缺少刷新凭证");
  const rotated = await rotateRefreshSession(db, token);
  if (!rotated) return errorResponse("invalid_session", "登录已失效，请重新登录", 401);
  const accessToken = await issueAccessToken({
    userID: rotated.userID,
    email: rotated.email,
    admin: isAdmin(rotated.email, env),
  }, env);
  return json({ access_token: accessToken, refresh_token: rotated.token, expires_in: 3600 });
}

function metricFromURL(url: URL): "tokens" | "cost" {
  return url.searchParams.get("metric") === "cost" ? "cost" : "tokens";
}

async function leaderboardRows(
  db: D1DatabaseLike,
  metric: "tokens" | "cost",
  limit = 100,
): Promise<LeaderboardRow[]> {
  const column = metric === "cost" ? "estimated_cost_micro_usd" : "total_tokens";
  const result = await db.prepare(
    `SELECT p.id, p.email, p.nickname, p.display_mode, p.joined_at, p.left_at, p.hidden_at,
            CAST(SUM(d.${column}) AS INTEGER) AS value
       FROM profiles p
       JOIN daily_usage d ON d.user_id = p.id
      WHERE p.left_at IS NULL AND p.hidden_at IS NULL AND d.local_day >= ?
      GROUP BY p.id
      ORDER BY value DESC, p.joined_at ASC
      LIMIT ?`,
  ).bind(weekStartKey(), limit).all<LeaderboardRow>();
  return result.results;
}

async function publicRankings(url: URL, db: D1DatabaseLike): Promise<Response> {
  const metric = metricFromURL(url);
  const rows = await leaderboardRows(db, metric);
  return json({
    metric,
    period: "week",
    period_start: weekStartKey(),
    entries: rows.map((row, index) => ({
      rank: index + 1,
      name: publicName(row.nickname, row.display_mode),
      value: Number(row.value),
    })),
  });
}

async function myRankings(session: SessionIdentity, db: D1DatabaseLike): Promise<Response> {
  const profile = await db.prepare(
    "SELECT id, email, nickname, display_mode, joined_at, left_at, hidden_at FROM profiles WHERE id = ?",
  ).bind(session.userID).first<ProfileRow>();
  if (!profile || profile.left_at) return errorResponse("not_joined", "当前账号未加入排行榜", 404);

  const [tokens, cost] = await Promise.all([
    leaderboardRows(db, "tokens", 10000),
    leaderboardRows(db, "cost", 10000),
  ]);
  const valueFor = (rows: LeaderboardRow[]) => {
    const index = rows.findIndex((row) => row.id === session.userID);
    return index < 0 ? { rank: null, value: 0 } : { rank: index + 1, value: Number(rows[index].value) };
  };
  return json({
    profile: serializedProfile(profile),
    period_start: weekStartKey(),
    tokens: valueFor(tokens),
    cost: valueFor(cost),
  });
}

async function upsertDailyUsage(
  request: Request,
  session: SessionIdentity,
  db: D1DatabaseLike,
): Promise<Response> {
  const body = await bodyJSON(request);
  const day = body?.local_day;
  const tokens = body?.total_tokens;
  const cost = body?.estimated_cost_micro_usd;
  if (!isValidDayKey(day) || typeof tokens !== "number" || typeof cost !== "number"
      || !Number.isSafeInteger(tokens) || !Number.isSafeInteger(cost)
      || tokens < 0 || cost < 0 || tokens > 1_000_000_000_000_000 || cost > 1_000_000_000_000_000) {
    return errorResponse("invalid_usage", "排行榜聚合值格式不正确");
  }
  const today = shanghaiDayKey();
  const earliest = new Date(today + "T00:00:00Z");
  earliest.setUTCDate(earliest.getUTCDate() - 31);
  if (day > today || day < earliest.toISOString().slice(0, 10)) {
    return errorResponse("invalid_day", "只接受最近 31 天内的聚合值");
  }
  const pricingVersion = typeof body?.pricing_version === "string"
    ? body.pricing_version.slice(0, 32) : "unknown";
  const appVersion = typeof body?.app_version === "string"
    ? body.app_version.slice(0, 32) : "unknown";
  const now = new Date().toISOString();

  await db.batch([
    db.prepare(
      `INSERT INTO daily_usage
       (user_id, local_day, total_tokens, estimated_cost_micro_usd, pricing_version,
        app_version, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, local_day) DO UPDATE SET
         total_tokens = excluded.total_tokens,
         estimated_cost_micro_usd = excluded.estimated_cost_micro_usd,
         pricing_version = excluded.pricing_version,
         app_version = excluded.app_version,
         updated_at = excluded.updated_at`,
    ).bind(session.userID, day, tokens, cost, pricingVersion, appVersion, now, now),
    db.prepare("UPDATE profiles SET last_app_version = ?, updated_at = ? WHERE id = ?")
      .bind(appVersion, now, session.userID),
  ]);
  return json({ ok: true, local_day: day });
}

async function updateDisplayMode(
  request: Request,
  session: SessionIdentity,
  db: D1DatabaseLike,
): Promise<Response> {
  const body = await bodyJSON(request);
  if (body?.display_mode !== "masked" && body?.display_mode !== "public") {
    return errorResponse("invalid_display_mode", "名称显示方式不正确");
  }
  await db.prepare("UPDATE profiles SET display_mode = ?, updated_at = ? WHERE id = ?")
    .bind(body.display_mode, new Date().toISOString(), session.userID).run();
  return json({ ok: true, display_mode: body.display_mode });
}

async function leaveRanking(session: SessionIdentity, db: D1DatabaseLike): Promise<Response> {
  const now = new Date().toISOString();
  await db.batch([
    db.prepare("UPDATE profiles SET left_at = ?, updated_at = ? WHERE id = ?")
      .bind(now, now, session.userID),
    db.prepare("DELETE FROM daily_usage WHERE user_id = ?").bind(session.userID),
    db.prepare("DELETE FROM refresh_sessions WHERE user_id = ?").bind(session.userID),
  ]);
  return json({ ok: true });
}

async function requireSession(request: Request, env: Env): Promise<SessionIdentity | Response> {
  const token = bearerToken(request);
  if (!token) return errorResponse("unauthorized", "请先登录", 401);
  try {
    return await verifyAccessToken(token, env);
  } catch {
    return errorResponse("invalid_session", "登录已失效，请重新登录", 401);
  }
}

async function requireAdmin(
  session: SessionIdentity,
  env: Env,
): Promise<Response | null> {
  return session.admin && isAdmin(session.email, env)
    ? null
    : errorResponse("forbidden", "无管理权限", 403);
}

async function adminOverview(
  session: SessionIdentity,
  env: Env,
  db: D1DatabaseLike,
): Promise<Response> {
  const denied = await requireAdmin(session, env);
  if (denied) return denied;
  const today = shanghaiDayKey();
  const [members, dau, versions, d1, d7, d30] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM profiles WHERE left_at IS NULL").first<{ count: number }>(),
    db.prepare("SELECT COUNT(DISTINCT user_id) AS count FROM daily_usage WHERE local_day = ?")
      .bind(today).first<{ count: number }>(),
    db.prepare(
      `SELECT app_version, COUNT(DISTINCT user_id) AS count
         FROM daily_usage WHERE local_day >= ?
        GROUP BY app_version ORDER BY count DESC LIMIT 10`,
    ).bind(weekStartKey()).all<{ app_version: string; count: number }>(),
    retention(db, 1, today),
    retention(db, 7, today),
    retention(db, 30, today),
  ]);
  return json({
    members: Number(members?.count ?? 0),
    dau: Number(dau?.count ?? 0),
    retention: { d1, d7, d30 },
    versions: versions.results,
    metric_scope: "ranking_members",
  });
}

async function retention(db: D1DatabaseLike, days: number, today: string): Promise<number | null> {
  const result = await db.prepare(
    `SELECT COUNT(*) AS eligible,
            SUM(CASE WHEN EXISTS (
              SELECT 1 FROM daily_usage d
               WHERE d.user_id = p.id
                 AND d.local_day = date(p.joined_at, '+8 hours', ?)
            ) THEN 1 ELSE 0 END) AS retained
      FROM profiles p
      WHERE p.consent_version != 'admin'
        AND date(p.joined_at, '+8 hours') <= date(?, ?)`,
  ).bind(`+${days} day`, today, `-${days} day`).first<{ eligible: number; retained: number }>();
  const eligible = Number(result?.eligible ?? 0);
  return eligible > 0 ? Number(result?.retained ?? 0) / eligible : null;
}

async function adminUsers(
  session: SessionIdentity,
  env: Env,
  db: D1DatabaseLike,
): Promise<Response> {
  const denied = await requireAdmin(session, env);
  if (denied) return denied;
  const result = await db.prepare(
    `SELECT p.id, p.email, p.nickname, p.display_mode, p.joined_at, p.left_at, p.hidden_at,
            p.last_app_version,
            MAX(d.updated_at) AS last_sync_at
       FROM profiles p LEFT JOIN daily_usage d ON d.user_id = p.id
      WHERE p.consent_version != 'admin'
      GROUP BY p.id ORDER BY p.joined_at DESC LIMIT 500`,
  ).all<Record<string, unknown>>();
  return json({ users: result.results });
}

async function setUserHidden(
  request: Request,
  session: SessionIdentity,
  env: Env,
  db: D1DatabaseLike,
  targetID: string,
): Promise<Response> {
  const denied = await requireAdmin(session, env);
  if (denied) return denied;
  const body = await bodyJSON(request);
  if (typeof body?.hidden !== "boolean") return errorResponse("invalid_request", "缺少 hidden");
  const now = new Date().toISOString();
  await db.batch([
    db.prepare("UPDATE profiles SET hidden_at = ?, updated_at = ? WHERE id = ?")
      .bind(body.hidden ? now : null, now, targetID),
    db.prepare(
      "INSERT INTO admin_audit (id, actor_id, action, target_id, created_at) VALUES (?, ?, ?, ?, ?)",
    ).bind(crypto.randomUUID(), session.userID, body.hidden ? "hide_user" : "show_user", targetID, now),
  ]);
  return json({ ok: true, hidden: body.hidden });
}

function serializedProfile(profile: ProfileRow) {
  return {
    id: profile.id,
    name: publicName(profile.nickname, profile.display_mode),
    nickname: profile.nickname,
    display_mode: profile.display_mode,
    joined_at: profile.joined_at,
  };
}
