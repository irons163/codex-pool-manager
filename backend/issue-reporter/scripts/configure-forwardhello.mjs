import { readFile, writeFile, copyFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { constants } from "node:fs";
import { forwardHelloEndpoint } from "../src/forwardhello.js";

const { values } = parseArgs({ options: {
  from: { type: "string" }, to: { type: "string" }, account: { type: "string" },
  base: { type: "string", default: "https://app.forwardhello.com" },
  "replace-inactive": { type: "boolean", default: false },
} });
const email = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
if (![values.from, values.to].every(value => value && value.length <= 254 && email.test(value))
    || !/^[0-9a-f]{32}$/i.test(values.account ?? "") || !forwardHelloEndpoint(values.base)) {
  throw new Error("Provide --from <verified sender> --to <recipient> --account <Cloudflare account ID> and an official ForwardHello base URL.");
}
const root = new URL("../", import.meta.url);
const output = new URL("wrangler.local.jsonc", root);
let previous;
try { previous = JSON.parse(await readFile(output, "utf8")); }
catch (error) { if (error.code !== "ENOENT") throw error; }
if (previous) {
  if (!values["replace-inactive"] || previous.vars?.REPORTS_ENABLED !== "false") {
    throw new Error("An existing config can only be replaced with --replace-inactive while reporting is disabled.");
  }
  await copyFile(output, new URL(`wrangler.previous-${Date.now()}.local.jsonc`, root), constants.COPYFILE_EXCL);
}
const config = JSON.parse(await readFile(new URL("wrangler.jsonc", root), "utf8"));
config.account_id = values.account;
Object.assign(config.vars, {
  MAIL_PROVIDER: "forwardhello", FORWARD_BASE_URL: new URL(values.base).origin,
  REPORT_FROM: values.from, REPORT_TO: values.to, REPORTS_ENABLED: "false",
});
delete config.send_email;
await writeFile(output, JSON.stringify(config, null, 2) + "\n", { flag: previous ? "w" : "wx", mode: 0o600 });
console.log("Prepared ForwardHello config with reporting disabled. Add the server secret before enabling and deploying.");
