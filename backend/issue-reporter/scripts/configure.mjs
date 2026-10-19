import { readFile, writeFile, copyFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { constants } from "node:fs";

const { values } = parseArgs({ options: {
  from: { type: "string" }, to: { type: "string" }, account: { type: "string" },
  "replace-inactive": { type: "boolean", default: false },
} });
const pattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
if (![values.from, values.to].every(value => value && value.length <= 254 && pattern.test(value))
    || !/^[0-9a-f]{32}$/i.test(values.account ?? "")) {
  throw new Error("Provide --from <verified sender address> --to <verified recipient> --account <Cloudflare account ID>.");
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
config.vars.MAIL_PROVIDER = "cloudflare";
config.vars.REPORT_FROM = values.from;
config.vars.REPORT_TO = values.to;
config.vars.REPORTS_ENABLED = "false";
config.send_email = [{ name: "REPORT_EMAIL", destination_address: values.to, allowed_sender_addresses: [values.from] }];
// Keep addresses outside Git and preserve a backup when replacing a disabled config.
await writeFile(output, JSON.stringify(config, null, 2) + "\n", { flag: previous ? "w" : "wx", mode: 0o600 });
console.log("Prepared Cloudflare configuration with reporting disabled until email verification is complete.");
