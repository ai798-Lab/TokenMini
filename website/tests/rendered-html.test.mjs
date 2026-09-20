import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the TokenMini public beta landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /FREE AI USAGE MONITOR FOR MAC/);
  assert.match(html, /TokenMini/);
  assert.match(html, /https:\/\/tokenmini\.cc/);
  assert.match(html, /0\.11\.0/);
  assert.match(html, /Apple Silicon/);
  assert.match(html, /macOS 14\+/);
  assert.match(html, /LOCAL BY DEFAULT/);
  assert.match(html, /OPT-IN RANKING/);
  assert.match(html, /大模型的消耗/);
  assert.doesNotMatch(html, /立即充值|立即付款|Token 购买|SUPPLY/);
  assert.match(html, /github\.com\/ai798-Lab\/TokenMini/);
  assert.match(html, /src="\/brand\/logo-horizontal-black\.svg"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
  assert.doesNotMatch(html, /google-analytics|googletagmanager|segment\.com|plausible\.io/i);
});

test("publishes the signed 0.10.0 update feed", async () => {
    const appcast = await readFile(new URL("../public/appcast.xml", import.meta.url), "utf8");
    assert.match(appcast, /xmlns:sparkle=/);
    assert.match(appcast, /<sparkle:version>3<\/sparkle:version>/);
    assert.match(appcast, /<sparkle:shortVersionString>0\.10\.0<\/sparkle:shortVersionString>/);
    assert.match(appcast, /releases\/download\/v0\.10\.0\/MacPulse-0\.10\.0\.dmg/);
    assert.match(appcast, /sparkle:edSignature=/);
    assert.match(appcast, /sparkle-signatures:/);
});

test("server-renders the public leaderboard without a login wall", async () => {
  const response = await render("/rankings");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /本周社区排行/);
  assert.match(html, /无需登录|无需登录即可浏览/);
  assert.match(html, /Token 消耗/);
  assert.match(html, /API 等价费用/);
  assert.match(html, /src="\/icon\.png"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
});

test("server-renders a dedicated privacy policy for Google OAuth", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /隐私说明/);
  assert.match(html, /Google 登录/);
  assert.match(html, /默认没有账号/);
  assert.match(html, /会话正文/);
  assert.match(html, /src="\/icon\.png"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
});

test("keeps the operations console out of search results", async () => {
  const response = await render("/admin");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /TokenMini 运营后台/);
  assert.match(html, /noindex/i);
  assert.match(html, /src="\/icon\.png"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
});
