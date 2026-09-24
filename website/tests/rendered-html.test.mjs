import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { publicVersion, releaseUrl } from "../app/brand-config.ts";

async function render(pathname = "/", language) {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, { headers: { accept: "text/html", ...(language ? { cookie: `tokenmini-language=${language}` } : {}) } }),
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
  assert.ok(html.includes(publicVersion));
  assert.match(html, /Apple Silicon/);
  assert.match(html, /macOS 14\+/);
  assert.match(html, /LOCAL BY DEFAULT/);
  assert.match(html, /OPT-IN RANKING/);
  assert.match(html, /Out of the dark/);
  assert.doesNotMatch(html, /立即充值|立即付款|Token 购买|SUPPLY/);
  assert.match(html, /github\.com\/ai798-Lab\/TokenMini/);
  assert.match(html, /src="\/brand\/logo-horizontal-black\.svg"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
  assert.doesNotMatch(html, /google-analytics|googletagmanager|segment\.com|plausible\.io/i);
});

test("publishes a signed feed consistent with the public download version", async () => {
    const appcast = await readFile(new URL("../public/appcast.xml", import.meta.url), "utf8");
    assert.match(appcast, /xmlns:sparkle=/);
    assert.match(appcast, /<sparkle:version>[1-9][0-9]*<\/sparkle:version>/);
    assert.ok(appcast.includes(`<sparkle:shortVersionString>${publicVersion}</sparkle:shortVersionString>`));
    assert.ok(appcast.includes(releaseUrl));
    assert.match(appcast, /sparkle:edSignature=/);
    assert.match(appcast, /sparkle-signatures:/);
});

test("server-renders the public leaderboard without a login wall", async () => {
  const response = await render("/rankings");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /This week’s community rankings/);
  assert.match(html, /without signing in/);
  assert.match(html, /Token usage/);
  assert.match(html, /API-equivalent cost/);
  assert.match(html, /src="\/icon\.png"/);
  assert.doesNotMatch(html, /\/_vinext\/image/);
});

test("server-renders a dedicated privacy policy for Google OAuth", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Privacy policy/);
  assert.match(html, /Google sign-in/);
  assert.match(html, /no accounts/);
  assert.match(html, /Conversation content/);
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

for (const [path, heading] of [["/", "让消耗，"], ["/privacy", "隐私说明"], ["/rankings", "本周社区排行"]]) {
  test(`renders saved Chinese preference on ${path}`, async () => {
    const html = await (await render(path, "zh")).text();
    assert.match(html, /<html[^>]*lang="zh-CN"/);
    assert.ok(html.includes(heading));
    assert.match(html, /aria-label="简体中文" aria-pressed="true"/);
  });
  test(`defaults to English for absent or invalid preference on ${path}`, async () => {
    for (const language of [undefined, "invalid"]) {
      const html = await (await render(path, language)).text();
      assert.match(html, /<html[^>]*lang="en"/);
      assert.match(html, /aria-label="English" aria-pressed="true"/);
    }
  });
}
