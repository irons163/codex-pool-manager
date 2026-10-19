import assert from "node:assert/strict";
import { createHash, createHmac, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { test } from "node:test";
import worker from "../src/worker.js";
import { validGoogleRelayURL, signedGoogleEnvelope, sendViaGoogleRelay } from "../src/google-relay.js";

const code = await readFile(new URL("../google-apps-script/Code.gs", import.meta.url), "utf8");
const relayURL = "https://script.google.com/macros/s/test-deployment/exec";
const secret = "synthetic-relay-secret-for-testing-only-12345";
const recipient = "owner@example.net";

function report(overrides = {}) {
  return { id: randomUUID(), title: "同步錯誤", message: "發生錯誤，請協助確認。", ...overrides };
}

function appsScript({ mailError = false, quota = 100 } = {}) {
  const values = new Map([["GOOGLE_RELAY_SECRET", secret], ["REPORT_TO", recipient]]);
  const messages = [];
  let locked = false;
  const blob = value => {
    const bytes = typeof value === "string" ? Buffer.from(value, "utf8") : Buffer.from(value);
    return { getBytes: () => [...bytes], getDataAsString: () => bytes.toString("utf8") };
  };
  const context = vm.createContext({
    PropertiesService: { getScriptProperties: () => ({
      getProperty: key => values.get(key) ?? null,
      setProperty: (key, value) => values.set(key, value),
      deleteProperty: key => values.delete(key),
      getProperties: () => Object.fromEntries(values),
    }) },
    ContentService: { MimeType: { JSON: "application/json" }, createTextOutput: text => ({
      setMimeType: () => JSON.parse(text),
    }) },
    Utilities: {
      Charset: { UTF_8: "utf8" }, DigestAlgorithm: { SHA_256: "sha256" },
      newBlob: blob, base64Decode: text => [...Buffer.from(text, "base64")],
      computeHmacSha256Signature: (text, key) => [...createHmac("sha256", key).update(text).digest()],
      computeDigest: (algorithm, text) => [...createHash(algorithm).update(text).digest()],
    },
    LockService: { getScriptLock: () => ({
      tryLock: () => { if (locked) return false; locked = true; return true; },
      hasLock: () => locked,
      releaseLock: () => { locked = false; },
    }) },
    MailApp: {
      getRemainingDailyQuota: () => quota,
      sendEmail: message => { messages.push(message); if (mailError) throw new Error("Provider failure"); },
    },
  });
  vm.runInContext(code, context);
  return {
    values, messages,
    post: envelope => context.doPost({ postData: { contents: JSON.stringify(envelope) } }),
  };
}

test("relay accepts only an HTTPS production Apps Script URL", () => {
  assert.ok(validGoogleRelayURL(relayURL));
  for (const value of [undefined, "", "http://script.google.com/macros/s/id/exec",
    "https://script.google.com.evil.example/macros/s/id/exec", "https://script.google.com/macros/s/id/dev",
    "https://user:secret@script.google.com/macros/s/id/exec", relayURL + "?token=secret"]) {
    assert.equal(validGoogleRelayURL(value), false);
  }
});

test("Worker envelope is accepted by the Apps Script with the fixed recipient and optional Reply-To", async () => {
  const script = appsScript();
  const payload = report({ replyEmail: "reporter@example.org", systemInfo: "App 1.0\nmacOS" });
  const envelope = await signedGoogleEnvelope(payload, recipient, secret);
  assert.deepEqual(script.post(envelope), { accepted: true, reportID: payload.id });
  assert.equal(script.messages.length, 1);
  assert.equal(script.messages[0].to, recipient);
  assert.equal(script.messages[0].replyTo, payload.replyEmail);
  assert.match(script.messages[0].subject, /同步錯誤/);
  assert.match(script.messages[0].body, /macOS/);
  const stored = JSON.stringify([...script.values]);
  assert.ok(!stored.includes(payload.message));
  assert.ok(!stored.includes(payload.replyEmail));
});

test("Apps Script rejects forged, changed, and expired envelopes before sending", async () => {
  const script = appsScript();
  const envelope = await signedGoogleEnvelope(report(), recipient, secret);
  const wrongTimestamp = Math.floor(Date.now() / 1000) - 1000;
  const old = { ...envelope, timestamp: wrongTimestamp,
    signature: createHmac("sha256", secret).update(`${wrongTimestamp}\n${envelope.payload}`).digest("hex") };
  for (const value of [
    { ...envelope, signature: "0".repeat(64) },
    { ...envelope, payload: envelope.payload + "AAAA" }, old,
  ]) {
    assert.equal(script.post(value).accepted, false);
  }
  assert.equal(script.messages.length, 0);
});

test("Apps Script refuses a different recipient and invalid report fields even with a valid signature", async () => {
  const script = appsScript();
  const otherRecipient = await signedGoogleEnvelope(report(), "attacker@example.com", secret);
  assert.equal(script.post(otherRecipient).accepted, false);
  for (const payload of [report({ to: "attacker@example.com" }), report({ title: "Hi\r\nBcc: bad@example.com" }),
    report({ replyEmail: "bad@example.com\nCc: other@example.com" }), report({ message: "x".repeat(20_001) })]) {
    assert.equal(script.post(await signedGoogleEnvelope(payload, recipient, secret)).accepted, false);
  }
  assert.equal(script.messages.length, 0);
});

test("Apps Script deduplicates retry and refuses changed content under the same report ID", async () => {
  const script = appsScript();
  const payload = report();
  const envelope = await signedGoogleEnvelope(payload, recipient, secret);
  assert.equal(script.post(envelope).accepted, true);
  assert.equal(script.post(envelope).accepted, true);
  assert.equal(script.post(await signedGoogleEnvelope({ ...payload, message: "Different" }, recipient, secret)).accepted, false);
  assert.equal(script.messages.length, 1);
});

test("Apps Script preserves an uncertain-send reservation and rejects quota exhaustion", async () => {
  const failed = appsScript({ mailError: true });
  const envelope = await signedGoogleEnvelope(report(), recipient, secret);
  assert.equal(failed.post(envelope).accepted, false);
  assert.equal(failed.post(envelope).accepted, false);
  assert.equal(failed.messages.length, 1);
  const noQuota = appsScript({ quota: 0 });
  assert.equal(noQuota.post(envelope).accepted, false);
  assert.equal(noQuota.messages.length, 0);
});

test("relay follows only Google's ContentService redirect and never forwards the report to it", async () => {
  const payload = report();
  const calls = [];
  const env = { GOOGLE_RELAY_URL: relayURL, GOOGLE_RELAY_SECRET: secret, REPORT_TO: recipient };
  await sendViaGoogleRelay(env, payload, async (url, options) => {
    calls.push({ url, options });
    if (calls.length === 1) return new Response(null, { status: 302,
      headers: { Location: "https://script.googleusercontent.com/macros/echo?one-time-token=synthetic" } });
    return Response.json({ accepted: true, reportID: payload.id });
  });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[1].options.method, "GET");
  assert.equal(calls[1].options.body, undefined);
  assert.equal(calls[1].options.headers, undefined);
});

test("relay rejects unrelated redirects, HTML login pages and mismatched receipts", async () => {
  const payload = report();
  const env = { GOOGLE_RELAY_URL: relayURL, GOOGLE_RELAY_SECRET: secret, REPORT_TO: recipient };
  for (const response of [
    new Response(null, { status: 302, headers: { Location: "https://attacker.example/receive" } }),
    new Response("<html>Sign in</html>"),
    Response.json({ accepted: false, reportID: payload.id }),
    Response.json({ accepted: true, reportID: randomUUID() }),
  ]) {
    let calls = 0;
    await assert.rejects(() => sendViaGoogleRelay(env, payload, async () => { calls += 1; return response; }));
    assert.equal(calls, 1);
  }
});

test("Apps Script provider stays unavailable until the URL and server secret are configured", async () => {
  const response = await worker.fetch(new Request("https://feedback.example/health"), {
    REPORTS_ENABLED: "true", MAIL_PROVIDER: "apps_script", REPORT_TO: recipient,
    GOOGLE_RELAY_URL: relayURL, REPORT_GATE: {}, REPORT_RATE_LIMITER: {},
  });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { ready: false });
});
