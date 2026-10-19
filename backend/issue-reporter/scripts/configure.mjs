import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";

const { values } = parseArgs({ options: {
  from: { type: "string" }, to: { type: "string" }, account: { type: "string" },
} });
const pattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
if (![values.from, values.to].every(value => value && value.length <= 254 && pattern.test(value))
    || !/^[0-9a-f]{32}$/i.test(values.account ?? "")) {
  throw new Error("Provide --from <verified sender address> --to <verified recipient> --account <Cloudflare account ID>.");
}
const root = new URL("../", import.meta.url);
const config = JSON.parse(await readFile(new URL("wrangler.jsonc", root), "utf8"));
config.account_id = values.account;
config.vars.REPORT_FROM = values.from;
config.vars.REPORT_TO = values.to;
config.vars.REPORTS_ENABLED = "true";
config.send_email = [{ name: "REPORT_EMAIL", destination_address: values.to, allowed_sender_addresses: [values.from] }];
// Keep deployment addresses outside Git. Never replace an existing deployment config.
await writeFile(new URL("wrangler.local.jsonc", root), JSON.stringify(config, null, 2) + "\n", { flag: "wx", mode: 0o600 });
console.log("Created wrangler.local.jsonc. No deployment or email was sent.");
