import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import worker, { ReportDeliveryGate } from "../src/worker.js";

function report(overrides = {}) {
  return { id: randomUUID(), title: "同步失敗", message: "按立即同步後出現錯誤。", ...overrides };
}

function request(body, headers = {}) {
  return new Request("https://feedback.example.com/reports", {
    method: "POST", headers: { "Content-Type": "application/json", "cf-connecting-ip": "192.0.2.1", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

class Storage {
  values = new Map();
  alarm = null;
  queue = Promise.resolve();
  async get(key) { return structuredClone(this.values.get(key)); }
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  async delete(key) { return this.values.delete(key); }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async list({ prefix }) { return new Map([...this.values].filter(([key]) => key.startsWith(prefix))); }
  transaction(callback) {
    const result = this.queue.then(() => callback(this));
    this.queue = result.catch(() => {});
    return result;
  }
}

function setup(overrides = {}) {
  const messages = [];
  const rateKeys = [];
  const storage = new Storage();
  const env = {
    REPORTS_ENABLED: "true", REPORT_FROM: "reports@example.com", REPORT_TO: "owner@example.net",
    MAX_REPORTS_PER_DAY: "100",
    REPORT_EMAIL: { send: async message => { messages.push(message); return { messageId: randomUUID() }; } },
    REPORT_RATE_LIMITER: { limit: async ({ key }) => { rateKeys.push(key); return { success: true }; } },
    ...overrides,
  };
  const gate = new ReportDeliveryGate({ storage }, env);
  env.REPORT_GATE = { idFromName: name => name, get: () => gate };
  return { env, gate, messages, storage, rateKeys };
}

test("sends UTF-8 report only to the configured recipient, with optional Reply-To", async () => {
  const fixture = setup();
  const payload = report({ replyEmail: "user+report@example.org", systemInfo: "CodexPoolManager 1.0.21 (151)\nmacOS" });
  const response = await worker.fetch(request(payload), fixture.env);
  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), { accepted: true, reportID: payload.id });
  assert.equal(fixture.messages[0].to, "owner@example.net");
  assert.equal(fixture.messages[0].from, "reports@example.com");
  assert.equal(fixture.messages[0].replyTo, payload.replyEmail);
  assert.match(fixture.messages[0].text, /按立即同步後出現錯誤/);
  assert.match(fixture.messages[0].text, /macOS/);
  const stored = JSON.stringify([...fixture.storage.values]);
  assert.ok(!stored.includes(payload.message));
  assert.ok(!stored.includes(payload.replyEmail));
});

test("omits unselected system information and empty reply address", async () => {
  const fixture = setup();
  const response = await worker.fetch(request(report()), fixture.env);
  assert.equal(response.status, 202);
  assert.ok(!("replyTo" in fixture.messages[0]));
  assert.ok(!fixture.messages[0].text.includes("system information"));
});

test("deduplicates a completed report and rejects changing its content under the same ID", async () => {
  const fixture = setup();
  const payload = report();
  assert.equal((await worker.fetch(request(payload), fixture.env)).status, 202);
  assert.equal((await worker.fetch(request(payload), fixture.env)).status, 200);
  assert.equal((await worker.fetch(request({ ...payload, message: "Changed" }), fixture.env)).status, 409);
  assert.equal(fixture.messages.length, 1);
});

test("does not acknowledge or duplicate an in-flight delivery", async () => {
  let release;
  let started;
  const isStarted = new Promise(resolve => { started = resolve; });
  const send = new Promise(resolve => { release = resolve; });
  let count = 0;
  const fixture = setup({ REPORT_EMAIL: { send: async () => { count += 1; started(); await send; } } });
  const payload = report();
  let finished = false;
  const first = worker.fetch(request(payload), fixture.env).then(response => { finished = true; return response; });
  await isStarted;
  assert.equal(finished, false);
  assert.equal((await worker.fetch(request(payload), fixture.env)).status, 409);
  release();
  assert.equal((await first).status, 202);
  assert.equal(count, 1);
});

test("keeps uncertain delivery reserved instead of silently sending it again", async () => {
  let count = 0;
  const fixture = setup({ REPORT_EMAIL: { send: async () => { count += 1; throw new Error("private provider diagnostic"); } } });
  const payload = report();
  const response = await worker.fetch(request(payload), fixture.env);
  assert.equal(response.status, 502);
  assert.ok(!(await response.text()).includes("private provider diagnostic"));
  assert.equal((await worker.fetch(request(payload), fixture.env)).status, 409);
  assert.equal(count, 1);
});

test("atomically enforces the daily budget across concurrent requests", async () => {
  const fixture = setup({ MAX_REPORTS_PER_DAY: "1" });
  const responses = await Promise.all([worker.fetch(request(report()), fixture.env), worker.fetch(request(report()), fixture.env)]);
  assert.deepEqual(responses.map(value => value.status).sort(), [202, 429]);
  assert.equal(fixture.messages.length, 1);
});

test("fails closed when disabled, unconfigured, or bindings fail", async () => {
  for (const overrides of [
    { REPORTS_ENABLED: "false" }, { REPORT_FROM: "" }, { REPORT_TO: "invalid" }, { REPORT_EMAIL: undefined },
    { REPORT_RATE_LIMITER: { limit: async () => { throw new Error("unavailable"); } } },
    { MAX_REPORTS_PER_DAY: "0" },
  ]) {
    const fixture = setup(overrides);
    const response = await worker.fetch(request(report()), fixture.env);
    assert.equal(response.status, 503);
    assert.equal(fixture.messages.length, 0);
  }
});

test("checks Cloudflare rate limit before reading the report", async () => {
  const fixture = setup({ REPORT_RATE_LIMITER: { limit: async () => ({ success: false }) } });
  const response = await worker.fetch(request("invalid JSON"), fixture.env);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.equal(fixture.messages.length, 0);
});

test("rejects unknown fields, header injection, malformed addresses, and oversized content", async () => {
  const fixture = setup();
  for (const payload of [
    null, [], report({ to: "attacker@example.com" }), report({ title: "Hi\r\nBcc: bad@example.com" }),
    report({ replyEmail: "valid@example.com\nBcc: bad@example.com" }), report({ title: "" }),
    report({ title: "中".repeat(101) }), report({ message: "x".repeat(20_001) }),
    report({ systemInfo: "x".repeat(1_001) }), report({ id: "../../bad" }), report({ message: "\0" }),
  ]) {
    assert.equal((await worker.fetch(request(payload), fixture.env)).status, 400);
  }
  assert.equal(fixture.messages.length, 0);
});

test("bounds streaming request size even without Content-Length", async () => {
  const fixture = setup();
  assert.equal((await worker.fetch(request("x".repeat(32_769)), fixture.env)).status, 413);
  assert.equal((await worker.fetch(request(report(), { "Content-Length": "9999999" }), fixture.env)).status, 413);
  assert.equal((await worker.fetch(request(report(), { "Content-Type": "text/plain" }), fixture.env)).status, 415);
  assert.equal(fixture.messages.length, 0);
});

test("health endpoint never sends mail; unsupported paths and methods are rejected", async () => {
  const fixture = setup();
  const health = await worker.fetch(new Request("https://feedback.example.com/health"), fixture.env);
  assert.deepEqual(await health.json(), { ready: true });
  assert.equal((await worker.fetch(new Request("https://feedback.example.com/reports"), fixture.env)).status, 405);
  assert.equal((await worker.fetch(new Request("https://feedback.example.com/unknown"), fixture.env)).status, 404);
  assert.equal(fixture.messages.length, 0);
});

test("alarm removes expired metadata without retaining report bodies", async () => {
  const fixture = setup();
  await fixture.storage.put("report:old", { digest: "old", state: "sent", expiresAt: Date.now() - 1 });
  const nextExpiry = Date.now() + 10_000;
  await fixture.storage.put("report:recent", { digest: "new", state: "sent", expiresAt: nextExpiry });
  await fixture.gate.alarm();
  assert.equal(await fixture.storage.get("report:old"), undefined);
  assert.equal(fixture.storage.alarm, nextExpiry);
});
