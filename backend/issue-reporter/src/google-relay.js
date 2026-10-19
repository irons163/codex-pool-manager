const encoder = new TextEncoder();

export function validGoogleRelayURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "script.google.com"
      && !url.port && !url.username && !url.password && !url.search && !url.hash
      && /^\/macros\/s\/[A-Za-z0-9_-]+\/exec$/.test(url.pathname);
  } catch { return false; }
}

export function googleRelayReady(env) {
  return validGoogleRelayURL(env.GOOGLE_RELAY_URL)
    && typeof env.GOOGLE_RELAY_SECRET === "string" && env.GOOGLE_RELAY_SECRET.length >= 32;
}

export async function signedGoogleEnvelope(report, recipient, secret) {
  const bytes = encoder.encode(JSON.stringify({ report, recipient }));
  const payload = btoa(String.fromCharCode(...bytes));
  const timestamp = Math.floor(Date.now() / 1000);
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}\n${payload}`));
  const hex = Array.from(new Uint8Array(signature), byte => byte.toString(16).padStart(2, "0")).join("");
  return { timestamp, payload, signature: hex };
}

export async function sendViaGoogleRelay(env, report, fetcher = fetch) {
  if (!googleRelayReady(env)) throw new Error("Google relay is not configured");
  const envelope = await signedGoogleEnvelope(report, env.REPORT_TO, env.GOOGLE_RELAY_SECRET);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  try {
    let response = await fetcher(env.GOOGLE_RELAY_URL, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(envelope), redirect: "manual", signal: controller.signal,
    });
    // Apps Script ContentService returns its response through a one-time Google
    // URL. Follow that redirect with GET, without forwarding the signed report.
    if ([302, 303].includes(response.status)) {
      const location = new URL(response.headers.get("Location"));
      if (location.protocol !== "https:" || location.hostname !== "script.googleusercontent.com"
          || location.username || location.password || location.port) {
        throw new Error("Unexpected Google relay redirect");
      }
      response = await fetcher(location.href, { method: "GET", redirect: "error", signal: controller.signal });
    }
    if (!response.ok) throw new Error("Google relay did not accept the report");
    const text = await response.text();
    if (text.length > 4096) throw new Error("Invalid Google relay receipt");
    const receipt = JSON.parse(text);
    if (receipt.accepted !== true || receipt.reportID !== report.id) throw new Error("Unconfirmed Google relay delivery");
  } finally {
    clearTimeout(timeout);
  }
}
