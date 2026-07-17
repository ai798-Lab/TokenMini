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

test("server-renders the MacPulse public beta landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /PUBLIC BETA/);
  assert.match(html, /Apple Silicon/);
  assert.match(html, /macOS 14\+/);
  assert.match(html, /NO TELEMETRY/);
  assert.match(html, /github\.com\/hepinga\/MacPulse/);
  assert.doesNotMatch(html, /google-analytics|googletagmanager|segment\.com|plausible\.io/i);
});

test("ships an empty production appcast shell before the signed release", async () => {
  const appcast = await readFile(new URL("../public/appcast.xml", import.meta.url), "utf8");
  assert.match(appcast, /xmlns:sparkle=/);
  assert.match(appcast, /https:\/\/macpulse-monitor\.peaceaii\.chatgpt\.site\/appcast\.xml/);
  assert.doesNotMatch(appcast, /<item>/);
});
