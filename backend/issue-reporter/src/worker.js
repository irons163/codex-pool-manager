const encoder = new TextEncoder();
const maxBodyBytes = 32_768;
const retentionMilliseconds = 24 * 60 * 60 * 1000;
const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;

function json(body, status = 200, headers = {}) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

function failure(code, status, headers) {
  return json({ accepted: false, error: code }, status, headers);
}

function validEmail(value) {
  return typeof value === "string" && encoder.encode(value).length <= 254 && emailPattern.test(value);
}

function ready(env) {
  return env.REPORTS_ENABLED === "true" && validEmail(env.REPORT_FROM) && validEmail(env.REPORT_TO)
    && env.REPORT_EMAIL && env.REPORT_GATE && env.REPORT_RATE_LIMITER;
}

export function validateReport(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const fields = new Set(["id", "title", "message", "replyEmail", "systemInfo"]);
  if (Object.keys(value).some(key => !fields.has(key))) return null;
  if (typeof value.id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value.id)) return null;
  if (typeof value.title !== "string" || typeof value.message !== "string") return null;
  const title = value.title.trim();
  const message = value.message.trim();
  if (!title || encoder.encode(title).length > 300 || /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(title)) return null;
  if (!message || encoder.encode(message).length > 20_000 || message.includes("\0")) return null;
  const replyEmail = value.replyEmail == null ? null : value.replyEmail;
  const systemInfo = value.systemInfo == null ? null : value.systemInfo;
  if (replyEmail !== null && !validEmail(replyEmail)) return null;
  if (systemInfo !== null && (typeof systemInfo !== "string" || encoder.encode(systemInfo).length > 1_000)) return null;
  return { id: value.id.toLowerCase(), title, message, replyEmail, systemInfo };
}

async function readReport(request) {
  if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
    return failure("unsupported_media_type", 415);
  }
  if (Number(request.headers.get("content-length")) > maxBodyBytes) return failure("too_large", 413);
  if (!request.body) return failure("invalid_report", 400);
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  const deadline = setTimeout(() => { void reader.cancel().catch(() => {}); }, 10_000);
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBodyBytes) {
        await reader.cancel();
        return failure("too_large", 413);
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const report = validateReport(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
    return report ?? failure("invalid_report", 400);
  } catch {
    return failure("invalid_report", 400);
  } finally {
    clearTimeout(deadline);
    reader.releaseLock();
  }
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/health" && request.method === "GET") {
      return json({ ready: Boolean(ready(env)) }, ready(env) ? 200 : 503);
    }
    if (path !== "/reports") return failure("not_found", 404);
    if (request.method !== "POST") return failure("method_not_allowed", 405, { Allow: "POST" });
    if (!ready(env)) return failure("unavailable", 503);
    try {
      // Cloudflare sets this header. There is no client-supplied secret in the app.
      const ip = request.headers.get("cf-connecting-ip");
      if (!ip) return failure("unavailable", 503);
      const { success } = await env.REPORT_RATE_LIMITER.limit({ key: `reports:${ip}` });
      if (!success) return failure("rate_limited", 429, { "Retry-After": "60" });
      const report = await readReport(request);
      if (report instanceof Response) return report;
      const gate = env.REPORT_GATE.get(env.REPORT_GATE.idFromName("report-delivery-v1"));
      return await gate.fetch(new Request("https://internal/reports", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(report),
      }));
    } catch {
      // Do not log the submitted text, reply address, or provider error messages.
      return failure("unavailable", 503);
    }
  },
};

export class ReportDeliveryGate {
  constructor(state, env) {
    this.storage = state.storage;
    this.env = env;
  }

  async fetch(request) {
    if (!ready(this.env)) return failure("unavailable", 503);
    const report = await readReport(request);
    if (report instanceof Response) return report;
    const digestBytes = await crypto.subtle.digest("SHA-256", encoder.encode(JSON.stringify(report)));
    const digest = Array.from(new Uint8Array(digestBytes), byte => byte.toString(16).padStart(2, "0")).join("");
    const now = Date.now();
    const day = new Date(now).toISOString().slice(0, 10);
    const key = `report:${report.id}`;
    const maxPerDay = Number(this.env.MAX_REPORTS_PER_DAY ?? 100);
    if (!Number.isInteger(maxPerDay) || maxPerDay < 1 || maxPerDay > 1_000) return failure("unavailable", 503);

    const decision = await this.storage.transaction(async tx => {
      const previous = await tx.get(key);
      if (previous) {
        if (previous.digest !== digest) return "conflict";
        return previous.state === "sent" ? "sent" : "pending";
      }
      const budget = await tx.get("budget");
      const used = budget?.day === day ? budget.used : 0;
      if (used >= maxPerDay) return "limited";
      await tx.put("budget", { day, used: used + 1 });
      await tx.put(key, { digest, state: "pending", expiresAt: now + retentionMilliseconds });
      if (await tx.getAlarm() === null) await tx.setAlarm(now + retentionMilliseconds);
      return "send";
    });

    if (decision === "sent") return json({ accepted: true, reportID: report.id });
    if (decision === "conflict" || decision === "pending") return failure("pending_or_conflicting_report", 409);
    if (decision === "limited") return failure("daily_limit", 429, { "Retry-After": "3600" });

    try {
      await this.env.REPORT_EMAIL.send({
        from: this.env.REPORT_FROM,
        to: this.env.REPORT_TO,
        subject: `[CodexPoolManager] ${report.title}`,
        ...(report.replyEmail ? { replyTo: report.replyEmail } : {}),
        text: [
          `Report ID: ${report.id}`, "", report.message,
          ...(report.systemInfo ? ["", "--- User-approved system information ---", report.systemInfo] : []),
        ].join("\n"),
      });
      await this.storage.put(key, { digest, state: "sent", expiresAt: now + retentionMilliseconds });
      return json({ accepted: true, reportID: report.id }, 202);
    } catch {
      // Delivery may have reached the provider before a connection error. Keep
      // the reservation to prevent retries from sending the same report twice.
      return failure("delivery_unconfirmed", 502);
    }
  }

  async alarm() {
    const records = await this.storage.list({ prefix: "report:" });
    const now = Date.now();
    for (const [key, record] of records) {
      if (record.expiresAt <= now) await this.storage.delete(key);
    }
    const remaining = await this.storage.list({ prefix: "report:" });
    if (remaining.size) await this.storage.setAlarm(Math.min(...Array.from(remaining.values(), record => record.expiresAt)));
  }
}
