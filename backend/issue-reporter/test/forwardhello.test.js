import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import { forwardHelloEndpoint, forwardHelloReady, sendViaForwardHello } from "../src/forwardhello.js";
import worker, { ReportDeliveryGate } from "../src/worker.js";

const env = {
  MAIL_PROVIDER: "forwardhello", REPORTS_ENABLED: "true",
  FORWARD_BASE_URL: "https://app.forwardhello.com",
  FORWARD_API_KEY: "fw_live_synthetic_server_only_test_key_12345",
  REPORT_FROM: "reports@example.com", REPORT_TO: "owner@example.net",
};
const emailID = "em_" + "a".repeat(24);
const receipt = overrides => ({ id: emailID, status: "queued", provider_message_id: null,
  test_mode: false, scheduled_at: null, idempotent_replay: false, ...overrides });
const report = overrides => ({ id: randomUUID(), title: "同步錯誤", message: "這是一筆測試回報。", ...overrides });

test("ForwardHello credentials can only target the official HTTPS API", async () => {
  assert.equal(forwardHelloEndpoint(env.FORWARD_BASE_URL), "https://app.forwardhello.com/api/v1/emails");
  assert.ok(forwardHelloReady(env));
  for (const value of [undefined, "", "http://app.forwardhello.com", "https://app.forwardhello.com.attacker.example",
    "https://user:secret@app.forwardhello.com", "https://app.forwardhello.com/other", "https://app.forwardhello.com?key=secret"]) {
    let calls = 0;
    await assert.rejects(() => sendViaForwardHello({ ...env, FORWARD_BASE_URL: value }, report(), async () => { calls += 1; }));
    assert.equal(calls, 0);
  }
});

test("ForwardHello request uses server-owned addresses and the documented reply_to field", async () => {
  const payload = report({ replyEmail: "reporter@example.org", systemInfo: "App 1.0\nmacOS" });
  const result = await sendViaForwardHello(env, payload, async (url, options) => {
    assert.equal(url, "https://app.forwardhello.com/api/v1/emails");
    assert.equal(options.method, "POST");
    assert.equal(options.redirect, "manual");
    assert.equal(options.headers.Authorization, `Bearer ${env.FORWARD_API_KEY}`);
    assert.equal(options.headers["Idempotency-Key"], `codexpool-report-${payload.id}`);
    const body = JSON.parse(options.body);
    assert.equal(body.from, "CodexPoolManager <reports@example.com>");
    assert.equal(body.to, "owner@example.net");
    assert.equal(body.reply_to, "reporter@example.org");
    assert.match(body.text, /同步|測試回報/);
    assert.match(body.text, /macOS/);
    assert.ok(!options.body.includes(env.FORWARD_API_KEY));
    return Response.json(receipt(), { status: 202 });
  });
  assert.deepEqual(result, { emailID, status: "queued" });
});

test("unselected system information and absent reply address are omitted", async () => {
  await sendViaForwardHello(env, report(), async (_url, options) => {
    const body = JSON.parse(options.body);
    assert.ok(!("reply_to" in body));
    assert.ok(!("html" in body));
    assert.ok(!body.text.includes("system information"));
    return Response.json(receipt(), { status: 202 });
  });
});

test("identical retries reuse the same provider idempotency key and body", async () => {
  const calls = [];
  const payload = report();
  const fetcher = async (_url, options) => {
    calls.push(options);
    return Response.json(receipt({ idempotent_replay: calls.length > 1 }), { status: calls.length > 1 ? 200 : 202 });
  };
  await sendViaForwardHello(env, payload, fetcher);
  await sendViaForwardHello(env, payload, fetcher);
  assert.equal(calls[0].headers["Idempotency-Key"], calls[1].headers["Idempotency-Key"]);
  assert.equal(calls[0].body, calls[1].body);
});

test("test-mode, failed, uncertain, scheduled, and incomplete receipts are never treated as submitted", async () => {
  for (const body of [
    receipt({ test_mode: true }), receipt({ test_mode: undefined }), receipt({ status: "failed" }),
    receipt({ status: "unknown" }), receipt({ status: "bounced" }), receipt({ status: "scheduled" }),
    receipt({ scheduled_at: "2026-11-01T00:00:00Z" }), receipt({ id: "invalid" }), { id: emailID },
  ]) {
    await assert.rejects(() => sendViaForwardHello(env, report(), async () => Response.json(body, { status: 202 })));
  }
});

test("redirects, authentication failures and rate limits never expose provider details or forward credentials", async () => {
  for (const status of [301, 302, 307, 401, 403, 409, 429, 500, 503]) {
    let calls = 0;
    const error = await sendViaForwardHello(env, report(), async () => {
      calls += 1;
      return new Response("private provider diagnostic", { status, headers: { Location: "https://attacker.example" } });
    }).then(() => null, error => error);
    assert.ok(error);
    assert.ok(!error.message.includes("private provider diagnostic"));
    assert.equal(calls, 1);
  }
});

test("malformed and oversized provider responses fail safely", async () => {
  for (const text of ["<html>Sign in</html>", "x".repeat(8193)]) {
    await assert.rejects(() => sendViaForwardHello(env, report(), async () => new Response(text, { status: 202 })));
  }
});

test("ForwardHello is not ready without a server-side sending key", async () => {
  const response = await worker.fetch(new Request("https://feedback.example/health"), {
    ...env, FORWARD_API_KEY: undefined, REPORT_GATE: {}, REPORT_RATE_LIMITER: {},
  });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { ready: false });
});

test("Worker routes through ForwardHello and deduplicates without calling the Cloudflare email binding", async () => {
  const stored = new Map();
  const storage = {
    get: async key => stored.get(key), put: async (key, value) => stored.set(key, value),
    getAlarm: async () => null, setAlarm: async () => {},
  };
  storage.transaction = async callback => callback(storage);
  let sends = 0;
  const settings = { ...env, REPORT_RATE_LIMITER: { limit: async () => ({ success: true }) } };
  const gate = new ReportDeliveryGate({ storage }, settings, async () => { sends += 1; return Response.json(receipt(), { status: 202 }); });
  settings.REPORT_GATE = { idFromName: name => name, get: () => gate };
  const payload = report();
  for (const status of [202, 200]) {
    const request = new Request("https://feedback.example/reports", {
      method: "POST", headers: { "Content-Type": "application/json", "cf-connecting-ip": "192.0.2.4" },
      body: JSON.stringify(payload),
    });
    const response = await worker.fetch(request, settings);
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { accepted: true, reportID: payload.id });
  }
  assert.equal(sends, 1);
});
