// Deploy as a web app that executes as its owner. Only the send-mail OAuth scope
// is required. Configure REPORT_TO and GOOGLE_RELAY_SECRET in Script Properties.
function authorizeMailer() {
  return MailApp.getRemainingDailyQuota();
}

function doPost(event) {
  const reply = function(value) {
    return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
  };
  let lock;
  try {
    const raw = event && event.postData && event.postData.contents;
    if (typeof raw !== 'string' || raw.length > 48000) return reply({ accepted: false });
    const properties = PropertiesService.getScriptProperties();
    const secret = properties.getProperty('GOOGLE_RELAY_SECRET');
    const recipient = properties.getProperty('REPORT_TO');
    if (!secret || secret.length < 32 || !validReportEmail_(recipient)) return reply({ accepted: false });

    const envelope = JSON.parse(raw);
    const now = Date.now();
    if (!Number.isInteger(envelope.timestamp) || Math.abs(now / 1000 - envelope.timestamp) > 300
        || typeof envelope.payload !== 'string' || envelope.payload.length > 44000
        || typeof envelope.signature !== 'string' || !/^[a-f0-9]{64}$/.test(envelope.signature)) {
      return reply({ accepted: false });
    }
    const signature = Utilities.computeHmacSha256Signature(
      envelope.timestamp + '\n' + envelope.payload, secret, Utilities.Charset.UTF_8
    ).map(function(byte) { return ('0' + ((byte + 256) % 256).toString(16)).slice(-2); }).join('');
    let different = 0;
    for (let i = 0; i < signature.length; i++) different |= signature.charCodeAt(i) ^ envelope.signature.charCodeAt(i);
    if (different !== 0) return reply({ accepted: false });

    const data = JSON.parse(Utilities.newBlob(Utilities.base64Decode(envelope.payload)).getDataAsString('UTF-8'));
    const report = data.report;
    if (data.recipient !== recipient || !validRelayReport_(report)) return reply({ accepted: false });
    lock = LockService.getScriptLock();
    if (!lock.tryLock(5000)) return reply({ accepted: false });

    // Store no message content. Preserve a pending reservation if sending throws.
    const all = properties.getProperties();
    Object.keys(all).filter(function(key) { return key.indexOf('report:') === 0; }).forEach(function(key) {
      try {
        if (JSON.parse(all[key]).expiresAt < now) properties.deleteProperty(key);
      } catch (_) { properties.deleteProperty(key); }
    });
    const key = 'report:' + report.id;
    const previous = properties.getProperty(key);
    const digest = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, envelope.payload, Utilities.Charset.UTF_8)
      .map(function(byte) { return ('0' + ((byte + 256) % 256).toString(16)).slice(-2); }).join('');
    if (previous) {
      const record = JSON.parse(previous);
      return reply({ accepted: record.state === 'sent' && record.digest === digest, reportID: report.id });
    }
    if (MailApp.getRemainingDailyQuota() < 1) return reply({ accepted: false });
    const record = { digest: digest, state: 'pending', expiresAt: now + 86400000 };
    properties.setProperty(key, JSON.stringify(record));
    const message = {
      to: recipient,
      subject: '[CodexPoolManager] ' + report.title,
      body: 'Report ID: ' + report.id + '\n\n' + report.message
        + (report.systemInfo ? '\n\n--- User-approved system information ---\n' + report.systemInfo : ''),
      name: 'CodexPoolManager 回報',
    };
    if (report.replyEmail) message.replyTo = report.replyEmail;
    MailApp.sendEmail(message);
    record.state = 'sent';
    properties.setProperty(key, JSON.stringify(record));
    return reply({ accepted: true, reportID: report.id });
  } catch (_) {
    return reply({ accepted: false });
  } finally {
    if (lock && lock.hasLock()) lock.releaseLock();
  }
}

function validReportEmail_(value) {
  return typeof value === 'string' && value.length <= 254
    && /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/.test(value);
}

function validRelayReport_(report) {
  if (!report || typeof report !== 'object' || Array.isArray(report)) return false;
  const fields = ['id', 'title', 'message', 'replyEmail', 'systemInfo'];
  if (Object.keys(report).some(function(key) { return fields.indexOf(key) === -1; })) return false;
  if (typeof report.id !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(report.id)) return false;
  if (typeof report.title !== 'string' || !report.title.trim()
      || Utilities.newBlob(report.title).getBytes().length > 300 || /[\x00-\x1f\x7f-\x9f\u2028\u2029]/.test(report.title)) return false;
  if (typeof report.message !== 'string' || !report.message.trim() || report.message.indexOf('\x00') !== -1
      || Utilities.newBlob(report.message).getBytes().length > 20000) return false;
  if (report.replyEmail != null && !validReportEmail_(report.replyEmail)) return false;
  return report.systemInfo == null || typeof report.systemInfo === 'string'
    && Utilities.newBlob(report.systemInfo).getBytes().length <= 1000;
}
