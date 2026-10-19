const allowedHosts = new Set(["app.forwardhello.com", "forwardhello.com"]);

export function forwardHelloEndpoint(baseURL) {
  try {
    const url = new URL(baseURL);
    if (url.protocol !== "https:" || !allowedHosts.has(url.hostname) || url.port
        || url.username || url.password || url.search || url.hash || url.pathname !== "/") return null;
    return new URL("/api/v1/emails", url).href;
  } catch { return null; }
}

export function forwardHelloReady(env) {
  return forwardHelloEndpoint(env.FORWARD_BASE_URL) !== null
    && typeof env.FORWARD_API_KEY === "string" && /^fw_live_[A-Za-z0-9_-]{20,}$/.test(env.FORWARD_API_KEY);
}

async function readReceipt(response) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("Missing ForwardHello receipt");
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) {
        await reader.cancel();
        throw new Error("Invalid ForwardHello receipt");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } finally {
    reader.releaseLock();
  }
}

export async function sendViaForwardHello(env, report, fetcher = fetch) {
  if (!forwardHelloReady(env)) throw new Error("ForwardHello is not configured");
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), 20_000);
  try {
    const response = await fetcher(forwardHelloEndpoint(env.FORWARD_BASE_URL), {
      method: "POST", redirect: "manual", signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${env.FORWARD_API_KEY}`,
        "Content-Type": "application/json", "Accept": "application/json",
        "Idempotency-Key": `codexpool-report-${report.id}`,
        "User-Agent": "CodexPoolManager-Feedback/1.0",
      },
      body: JSON.stringify({
        from: `CodexPoolManager <${env.REPORT_FROM}>`,
        to: env.REPORT_TO,
        subject: `[CodexPoolManager] ${report.title}`,
        ...(report.replyEmail ? { reply_to: report.replyEmail } : {}),
        text: [
          `Report ID: ${report.id}`, "", report.message,
          ...(report.systemInfo ? ["", "--- User-approved system information ---", report.systemInfo] : []),
        ].join("\n"),
      }),
    });
    // Do not forward the credential on redirects or surface provider error bodies.
    if (![200, 202].includes(response.status)) {
      await response.body?.cancel();
      throw new Error("ForwardHello did not accept the report");
    }
    const receipt = await readReceipt(response);
    if (typeof receipt.id !== "string" || !/^em_[a-f0-9]{24}$/.test(receipt.id)
        || receipt.test_mode !== false || receipt.scheduled_at !== null
        || !["queued", "sent", "delivered"].includes(receipt.status)) {
      throw new Error("Unconfirmed ForwardHello submission");
    }
    return { emailID: receipt.id, status: receipt.status };
  } finally {
    clearTimeout(deadline);
  }
}
