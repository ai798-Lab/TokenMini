import vinext from "vinext";
import { defineConfig } from "vite";
import { sites } from "./build/sites-vite-plugin";

const SITE_CREATOR_PLACEHOLDER_DATABASE_ID =
  "00000000-0000-4000-8000-000000000000";

const d1 = process.env.MACPULSE_D1_BINDING ?? "DB";
const r2 = process.env.MACPULSE_R2_BINDING ?? null;

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === "seatbelt";

const localBindingConfig = {
  main: "./worker/index.ts",
  compatibility_flags: ["nodejs_compat"],
  d1_databases: d1
    ? [
        {
          binding: d1,
          database_name: "site-creator-d1",
          database_id: SITE_CREATOR_PLACEHOLDER_DATABASE_ID,
        },
      ]
    : [],
  r2_buckets: r2
    ? [
        {
          binding: r2,
          bucket_name: "site-creator-r2",
        },
      ]
    : [],
};

export default defineConfig(async ({ command }) => {
  // Keep Wrangler and Miniflare state project-local. These are non-secret tool
  // settings; application environment belongs in ignored `.env*` files.
  process.env.WRANGLER_WRITE_LOGS ??= "false";
  process.env.WRANGLER_LOG_PATH ??= ".wrangler/logs";
  process.env.MINIFLARE_REGISTRY_PATH ??= ".wrangler/registry";

  // Wrangler snapshots its log path while the Cloudflare plugin is imported.
  const { cloudflare } = await import("@cloudflare/vite-plugin");
  const analyticsURL = process.env.TOKENMINI_ANALYTICS_WEB_URL || "";
  if (analyticsURL) {
    const url = new URL(analyticsURL);
    const localTest = command === "serve" && ["localhost", "127.0.0.1"].includes(url.hostname);
    if (url.username || url.password || (url.protocol !== "https:" && !localTest)) throw new Error("Analytics requires HTTPS (loopback HTTP is only allowed during local development)");
  }

  return {
    // Only the write-only web client ID is public. Never expose admin/read credentials.
    define: {
      "process.env.TOKENMINI_ANALYTICS_WEB_URL": JSON.stringify(analyticsURL),
      "process.env.TOKENMINI_ANALYTICS_WEB_CLIENT_ID": JSON.stringify(process.env.TOKENMINI_ANALYTICS_WEB_CLIENT_ID || ""),
    },
    server: isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : undefined,
    plugins: [
      vinext(),
      sites(),
      cloudflare({
        viteEnvironment: { name: "rsc", childEnvironments: ["ssr"] },
        config: localBindingConfig,
      }),
    ],
  };
});
