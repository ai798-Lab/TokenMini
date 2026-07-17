"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Overview = {
  members: number;
  dau: number;
  retention: { d1: number | null; d7: number | null; d30: number | null };
  versions: Array<{ app_version: string; count: number }>;
  metric_scope: string;
};
type UserRow = {
  id: string;
  email: string;
  nickname: string;
  display_mode: string;
  joined_at: string;
  left_at: string | null;
  hidden_at: string | null;
  last_app_version: string | null;
  last_sync_at: string | null;
};

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize(options: { client_id: string; callback(value: { credential: string }): void }): void;
          renderButton(element: HTMLElement, options: Record<string, unknown>): void;
        };
      };
    };
  }
}

function percent(value: number | null): string {
  return value == null ? "—" : Math.round(value * 100) + "%";
}

async function fetchAdmin(token: string): Promise<{ overview: Overview; users: UserRow[] }> {
  const headers = { authorization: "Bearer " + token };
  const [overviewResponse, usersResponse] = await Promise.all([
    fetch("/api/v1/admin/overview", { headers, cache: "no-store" }),
    fetch("/api/v1/admin/users", { headers, cache: "no-store" }),
  ]);
  if (!overviewResponse.ok || !usersResponse.ok) {
    const detail = await overviewResponse.json().catch(() => null) as { message?: string } | null;
    throw new Error(detail?.message ?? "无法读取后台");
  }
  const overview = await overviewResponse.json() as Overview;
  const body = await usersResponse.json() as { users: UserRow[] };
  return { overview, users: body.users };
}

export default function AdminClient() {
  const buttonRef = useRef<HTMLDivElement>(null);
  const [accessToken, setAccessToken] = useState("");
  const [overview, setOverview] = useState<Overview | null>(null);
  const [users, setUsers] = useState<UserRow[]>([]);
  const [message, setMessage] = useState("正在检查登录配置…");

  const authenticate = useCallback(async (credential: string) => {
    setMessage("正在登录…");
    const response = await fetch("/api/v1/auth/google", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id_token: credential,
        display_mode: "masked",
        app_version: "web-admin",
        purpose: "admin",
      }),
    });
    const body = await response.json() as { access_token?: string; message?: string };
    if (!response.ok || !body.access_token) throw new Error(body.message ?? "登录失败");
    sessionStorage.setItem("macpulse.admin.token", body.access_token);
    setAccessToken(body.access_token);
    const next = await fetchAdmin(body.access_token);
    setOverview(next.overview);
    setUsers(next.users);
    setMessage("");
  }, []);

  useEffect(() => {
    const existing = sessionStorage.getItem("macpulse.admin.token");
    if (existing) {
      void fetchAdmin(existing)
        .then((next) => {
          setAccessToken(existing);
          setOverview(next.overview);
          setUsers(next.users);
          setMessage("");
        })
        .catch((error: Error) => {
          sessionStorage.removeItem("macpulse.admin.token");
          setAccessToken("");
          setMessage(error.message);
        });
      return;
    }
    void fetch("/api/v1/config", { cache: "no-store" })
      .then((response) => response.json())
      .then((config: { google_web_client_id: string | null }) => {
        if (!config.google_web_client_id) throw new Error("Google 网页登录尚未配置");
        const script = document.createElement("script");
        script.src = "https://accounts.google.com/gsi/client";
        script.async = true;
        script.onload = () => {
          if (!window.google || !buttonRef.current) return;
          window.google.accounts.id.initialize({
            client_id: config.google_web_client_id!,
            callback: ({ credential }) => { void authenticate(credential).catch((error: Error) => setMessage(error.message)); },
          });
          window.google.accounts.id.renderButton(buttonRef.current, {
            type: "standard", theme: "outline", size: "large", text: "signin_with", shape: "rectangular",
          });
          setMessage("请使用管理员 Google 账号登录");
        };
        script.onerror = () => setMessage("Google 登录组件加载失败");
        document.head.appendChild(script);
      })
      .catch((error: Error) => setMessage(error.message));
  }, [authenticate]);

  const setHidden = async (user: UserRow, hidden: boolean) => {
    const response = await fetch("/api/v1/admin/users/" + user.id + "/hidden", {
      method: "PATCH",
      headers: { authorization: "Bearer " + accessToken, "content-type": "application/json" },
      body: JSON.stringify({ hidden }),
    });
    if (!response.ok) return setMessage("操作失败，请重试");
    setUsers((current) => current.map((item) => item.id === user.id
      ? { ...item, hidden_at: hidden ? new Date().toISOString() : null } : item));
  };

  if (!overview) {
    return (
      <section className="admin-login shell">
        <p className="eyebrow">OWNER ACCESS</p>
        <h1>MacPulse 运营后台</h1>
        <p>仅允许配置在服务端白名单中的 Google 账号访问。</p>
        <div ref={buttonRef} className="google-button" />
        <small>{message}</small>
      </section>
    );
  }

  return (
    <section className="admin-shell shell">
      <div className="admin-heading">
        <div><p className="eyebrow">RANKING MEMBERS ONLY</p><h1>运营概览</h1></div>
        <button className="button secondary" onClick={() => {
          sessionStorage.removeItem("macpulse.admin.token"); setAccessToken(""); setOverview(null); location.reload();
        }}>退出后台</button>
      </div>
      {message && <p className="admin-message">{message}</p>}
      <div className="admin-metrics">
        <article><small>排行榜成员</small><strong>{overview.members}</strong></article>
        <article><small>今日活跃</small><strong>{overview.dau}</strong></article>
        <article><small>次日留存</small><strong>{percent(overview.retention.d1)}</strong></article>
        <article><small>7 日留存</small><strong>{percent(overview.retention.d7)}</strong></article>
        <article><small>30 日留存</small><strong>{percent(overview.retention.d30)}</strong></article>
      </div>
      <div className="admin-grid">
        <article className="admin-panel">
          <h2>版本分布</h2>
          {overview.versions.length === 0 && <p>暂无同步数据</p>}
          {overview.versions.map((version) => (
            <div className="version-row" key={version.app_version}>
              <span>{version.app_version}</span><b>{version.count}</b>
            </div>
          ))}
        </article>
        <article className="admin-panel users-panel">
          <h2>排行榜用户</h2>
          <div className="admin-user-list">
            {users.map((user) => (
              <div className="admin-user-row" key={user.id}>
                <div><strong>{user.nickname}</strong><small>{user.email}</small></div>
                <span>{user.last_app_version ?? "—"}</span>
                <span>{user.last_sync_at ? new Date(user.last_sync_at).toLocaleDateString("zh-CN") : "未同步"}</span>
                <button onClick={() => void setHidden(user, !user.hidden_at)}>
                  {user.hidden_at ? "恢复榜单" : "隐藏异常"}
                </button>
              </div>
            ))}
          </div>
        </article>
      </div>
    </section>
  );
}
