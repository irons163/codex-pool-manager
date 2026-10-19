# Issue reporting service

This Cloudflare Worker receives in-app issue reports at `POST /reports` and sends
them to one fixed recipient using ForwardHello, an Apps Script relay, or Cloudflare's
email binding. No email API key,
SMTP password, GitHub token, or user login credential is included in the app.

The repository configuration starts with reporting disabled. Deployment addresses
and secrets live in ignored local configuration and server settings.

## Send through an existing ForwardHello workspace

Use this path when a workspace already has a verified sender domain and production
sending access. The app submits to the Cloudflare Worker; only the Worker contacts
ForwardHello. The API key never enters the app or the public request body.

1. Create a dedicated Sending access key in ForwardHello, scoped to the verified
   sender domain. Keep other applications' keys unchanged. No Full access is needed.
2. Prepare an ignored local configuration:

   ```sh
   node scripts/configure-forwardhello.mjs \
     --from '<verified-sender-address>' --to '<report-recipient>' \
     --account '<cloudflare-account-id>'
   ```

   The base URL defaults to `https://app.forwardhello.com`. The adapter permits
   only official ForwardHello HTTPS origins, refuses redirects, and bounds response
   parsing. To replace an earlier disabled configuration, add `--replace-inactive`;
   the script preserves a backup and refuses to replace an enabled configuration.
3. Store `FORWARD_API_KEY` with `npx wrangler secret put FORWARD_API_KEY --config
   wrangler.local.jsonc` after approving creation of the dedicated credential.
4. Set `REPORTS_ENABLED` to `"true"` in the local configuration, validate with
   `npm test` and `npm run check -- --config wrangler.local.jsonc`, then deploy
   using `npm run deploy -- --config wrangler.local.jsonc`.
5. Check `/health`, submit one approved test report, and confirm the actual delivery
   status in ForwardHello. Set the GitHub repository variable `FEEDBACK_ENDPOINT`
   to the Worker's `/reports` URL before building the app release.

ForwardHello submissions use the report UUID in `Idempotency-Key`, fixed server-side
sender and recipient addresses, and `reply_to` only when supplied by the reporter.
The adapter accepts only genuine live `queued`, `sent`, or `delivered` receipts with
a ForwardHello email ID. Simulated test-mode outcomes and unknown or failed statuses
cannot produce a success message in the app. An accepted queued report means it
has been submitted; it does not claim inbox delivery. Provider errors are not logged
or returned to app users. ForwardHello retains messages under the workspace's own
data-retention policy.

## Send without a domain using Google Apps Script

Use this option when the app owner has a Gmail account but no sender domain.
The owner signs into Google and authorizes sending once. App users do not need
Google accounts or mail applications. The sender is the Google account that owns
the deployment; the recipient may be that same account.

1. Create a Google Apps Script project under the intended sender account. Copy
   `google-apps-script/Code.gs` and `google-apps-script/appsscript.json` into it.
   The manifest requests only `script.send_mail`, which permits sending email;
   it does not grant access to the inbox.
2. Generate private configuration from this directory:

   ```sh
   node scripts/configure-google.mjs \
     --to '<report-recipient>' \
     --account '<cloudflare-account-id>'
   ```

   This creates ignored `wrangler.local.jsonc` and `google-relay-secret.local`
   files without deploying. The generated secret is a random server-to-server
   signing key. Do not commit it or include it in the app.
3. In Apps Script Project Settings, add Script Properties named `REPORT_TO`
   (the same recipient) and `GOOGLE_RELAY_SECRET` (the generated secret).
   Run `authorizeMailer` and authorize the sending permission in Google.
4. Deploy as a web app, executing as the deploying owner, with access set to
   anyone. The endpoint requires a signed request even though the Google web
   app itself is reachable without user sign-in. Copy its `/exec` URL.
5. In `wrangler.local.jsonc`, set `GOOGLE_RELAY_URL` to that production `/exec`
   URL and `REPORTS_ENABLED` to `"true"`. The generated configuration removes
   the Cloudflare email binding and needs no sender domain.
6. Put the same secret into Cloudflare's secret store using:

   ```sh
   npx wrangler secret put GOOGLE_RELAY_SECRET --config wrangler.local.jsonc < google-relay-secret.local
   ```

   Complete the account setup and permission decisions before running this step.
   Validate with `npm test` and `npm run check -- --config wrangler.local.jsonc`,
   then deploy with `npm run deploy -- --config wrangler.local.jsonc`.
7. Verify `/health`, submit a test report to confirm inbox delivery, and set the
   GitHub repository variable `FEEDBACK_ENDPOINT` to the Worker's `/reports` URL
   before building an app release.

The relay checks the request signature, a five-minute timestamp window, the fixed
recipient, and the report fields before sending. A lock and stored hashes prevent
replayed requests from duplicating email. It follows Google's one-time response
redirect only to `script.googleusercontent.com`, with no report or signature in
the redirected request. Exceptions do not log the report or signing secret.

Consumer Gmail accounts currently have a MailApp allowance of 100 recipients per
day, shared with other scripts on the account. The relay checks remaining quota
before sending, and the Worker's daily cap still applies. Google's quota can change.

## Send from a verified domain using Cloudflare Email Service

1. In the intended Cloudflare account, onboard a sender domain to Email Service and
   complete its DNS verification. Add and verify the report recipient. The sender
   must belong to that domain. Existing inbound email routing should be reviewed
   before changing a domain's MX records.
2. Run `npm ci` in this directory, then `npx wrangler login` to authenticate with
   that account. Do not put credentials in source files or the app.
3. Create a local deployment configuration with the verified addresses and account
   ID (replace the angle-bracket values):

   ```sh
   node scripts/configure.mjs \
     --from '<verified-sender-address>' \
     --to '<verified-recipient-address>' \
     --account '<cloudflare-account-id>'
   ```

   This writes the ignored `wrangler.local.jsonc`, locks the email binding to the
   selected sender and recipient, and enables reporting. It does not deploy or send.
   An existing local configuration is never overwritten.
4. Run `npm test` and `npm run check -- --config wrangler.local.jsonc`.
5. Deploy with `npm run deploy -- --config wrangler.local.jsonc`. Keep the Durable
   Object binding name, object name, and migration history on later deployments.
6. Check `GET https://<deployed-worker-host>/health`. A ready configuration returns
   `200` and `{"ready":true}`. This checks configuration only; it does not verify
   DNS, email-provider acceptance, or final inbox delivery. A real test report must
   be sent separately to confirm the complete path.
7. Set the GitHub repository variable `FEEDBACK_ENDPOINT` to
   `https://<deployed-worker-host>/reports` before building the next app release.
   The release packaging script adds this URL to the app before signing. Without
   it, the app shows that email reporting is unavailable and offers GitHub.

## Behaviour and limits

- Accept only JSON containing an ID, subject, description, optional reply email,
  and optional user-approved version/system text. Unknown fields are rejected.
- The HTTP body is capped at 32 KiB, subject at 300 UTF-8 bytes, description at
  20,000 bytes, and system information at 1,000 bytes. Requests cannot select the
  sender or recipient. Reply email is used only as `Reply-To`.
- Anonymous reporting has a coarse IP limit of five requests per minute at each
  Cloudflare location. Shared-network users may share this limit. This is not an
  authentication mechanism. The Durable Object enforces a global budget of 100
  attempted emails per UTC day; adjust `MAX_REPORTS_PER_DAY` between 1 and 1,000.
- A transaction reserves each ID before contacting the email provider. Concurrent
  and repeated submissions cannot cause duplicate sends. A provider exception
  leaves the reservation pending because delivery may already have occurred.
  Retrying that ID returns `409`; the service never claims success in this case.
- Success means the email binding accepted the submission, not confirmed inbox
  delivery. DNS and recipient verification must be completed before enabling.
- Durable Object storage contains only report IDs, hashes, states, expiration
  timestamps, and the daily counter. It does not store the report text or reply
  address. Live deduplication metadata expires after 24 hours and is cleared by
  an alarm. Cloudflare's platform recovery retention may outlast live records.
- Worker observability is disabled in the supplied configuration. The application
  does not log report bodies or email-provider error messages. Cloudflare and the
  email delivery service still process requests and emails under their policies.

## Verification

```sh
npm ci
npm test
npm run check
```

Tests use a fake email binding and do not send real mail. `check` is a dry run
that bundles and checks bindings without deploying. Local development with
`npm run dev` uses the disabled configuration by default.

References: [ForwardHello API](https://forwardhello.com/docs/reference),
[Apps Script web apps](https://developers.google.com/apps-script/guides/web),
[MailApp](https://developers.google.com/apps-script/reference/mail/mail-app),
[Google quotas](https://developers.google.com/apps-script/guides/services/quotas),
[ContentService redirects](https://developers.google.com/apps-script/guides/content#redirects),
[Cloudflare email sending API](https://developers.cloudflare.com/email-service/api/send-emails/workers-api/),
[send bindings](https://developers.cloudflare.com/email-service/configuration/send-bindings/),
[rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/),
[Durable Object storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/).
