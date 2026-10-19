import { readFile, writeFile, access, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { parseArgs } from "node:util";
import { validGoogleRelayURL } from "../src/google-relay.js";

const { values } = parseArgs({ options: {
  to: { type: "string" }, account: { type: "string" }, relay: { type: "string" },
} });
const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
if (!values.to || values.to.length > 254 || !emailPattern.test(values.to)
    || !/^[0-9a-f]{32}$/i.test(values.account ?? "") || values.relay && !validGoogleRelayURL(values.relay)) {
  throw new Error("Provide --to <recipient> --account <Cloudflare account ID> and optional --relay <Apps Script /exec URL>.");
}
const root = new URL("../", import.meta.url);
const output = new URL("wrangler.local.jsonc", root);
const secretFile = new URL("google-relay-secret.local", root);
for (const file of [output, secretFile]) {
  try { await access(file); } catch (error) { if (error.code === "ENOENT") continue; throw error; }
  throw new Error("Local relay configuration already exists; refusing to overwrite it.");
}
const config = JSON.parse(await readFile(new URL("wrangler.jsonc", root), "utf8"));
config.account_id = values.account;
config.vars.REPORT_TO = values.to;
config.vars.MAIL_PROVIDER = "apps_script";
config.vars.GOOGLE_RELAY_URL = values.relay ?? "";
config.vars.REPORTS_ENABLED = values.relay ? "true" : "false";
delete config.vars.REPORT_FROM;
delete config.send_email;
await writeFile(secretFile, randomBytes(32).toString("base64url"), { flag: "wx", mode: 0o600 });
try {
  await writeFile(output, JSON.stringify(config, null, 2) + "\n", { flag: "wx", mode: 0o600 });
} catch (error) { await unlink(secretFile); throw error; }
console.log("Created private relay configuration and secret file. No deployment or email was sent.");
