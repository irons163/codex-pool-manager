# Issue reporting service

This Cloudflare Worker receives in-app issue reports at `POST /reports` and sends
them to one verified recipient using Cloudflare's email binding. No email API key,
SMTP password, GitHub token, or user login credential is included in the app.

The repository configuration starts with reporting disabled. No production account,
sender domain, recipient, or endpoint has been selected or deployed yet.

## Set up and deploy

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

References: [email sending API](https://developers.cloudflare.com/email-service/api/send-emails/workers-api/),
[send bindings](https://developers.cloudflare.com/email-service/configuration/send-bindings/),
[rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/),
[Durable Object storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/).
