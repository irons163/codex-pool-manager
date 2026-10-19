#!/usr/bin/env bash
set -euo pipefail

TASK_TRANSPORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_TRANSPORT_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/codexpool-transport.XXXXXX")"
TASK_TRANSPORT_SERVER_PID=""
trap 'if [[ -n "$TASK_TRANSPORT_SERVER_PID" ]]; then kill "$TASK_TRANSPORT_SERVER_PID" 2>/dev/null || true; wait "$TASK_TRANSPORT_SERVER_PID" 2>/dev/null || true; fi; rm -rf "$TASK_TRANSPORT_TEMP"' EXIT
TASK_TRANSPORT_BINARY="${ISSUE_REPORT_SMOKE_BINARY:-${ISSUE_REPORT_SMOKE_OUTPUT:-$TASK_TRANSPORT_TEMP/issue-report-transport-smoke}}"

# Run the production transport with Release optimization and the same isolation
# settings as the application. The executable also runs on hosted macOS runners.
if [[ -z "${ISSUE_REPORT_SMOKE_BINARY:-}" ]]; then
  for TASK_TRANSPORT_ARCH in arm64 x86_64; do
    xcrun swiftc \
      -parse-as-library -O -whole-module-optimization -swift-version 5 \
      -default-isolation MainActor \
      -enable-upcoming-feature NonisolatedNonsendingByDefault \
      -enable-upcoming-feature InferIsolatedConformances \
      -target "$TASK_TRANSPORT_ARCH-apple-macosx15.0" \
      "$TASK_TRANSPORT_ROOT/CodexPoolManager/IssueReporting/IssueReportService.swift" \
      "$TASK_TRANSPORT_ROOT/CodexPoolManager/IssueReporting/IssueReportHTTPTransport.swift" \
      "$TASK_TRANSPORT_ROOT/CodexPoolManager/Support/L10n.swift" \
      "$TASK_TRANSPORT_ROOT/scripts/IssueReportTransportSmoke.swift" \
      -o "$TASK_TRANSPORT_TEMP/smoke-$TASK_TRANSPORT_ARCH"
  done
  xcrun lipo -create "$TASK_TRANSPORT_TEMP/smoke-arm64" "$TASK_TRANSPORT_TEMP/smoke-x86_64" \
    -output "$TASK_TRANSPORT_BINARY"
fi

# Use a real loopback redirect: a custom URLProtocol does not model the
# Foundation redirect lifecycle. The server listens only on 127.0.0.1.
python3 - "$TASK_TRANSPORT_TEMP/port" <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer

class LoopbackServer(ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]

class RedirectHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(307 if self.path == '/redirect' else 200)
        if self.path == '/redirect':
            self.send_header('Location', f'http://127.0.0.1:{self.server.server_port}/forbidden')
        self.send_header('Content-Length', '0')
        self.end_headers()

    do_GET = do_POST

    def log_message(self, *args):
        pass

server = LoopbackServer(('127.0.0.1', 0), RedirectHandler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY
TASK_TRANSPORT_SERVER_PID=$!
for TASK_TRANSPORT_ATTEMPT in {1..400}; do
  [[ -s "$TASK_TRANSPORT_TEMP/port" ]] && break
  kill -0 "$TASK_TRANSPORT_SERVER_PID" 2>/dev/null || { echo 'Loopback test server exited.' >&2; exit 1; }
  sleep 0.05
done
[[ -s "$TASK_TRANSPORT_TEMP/port" ]] || { echo 'Loopback test server did not start.' >&2; exit 1; }
TASK_TRANSPORT_PORT="$(cat "$TASK_TRANSPORT_TEMP/port")"

ISSUE_REPORT_REDIRECT_URL="http://127.0.0.1:$TASK_TRANSPORT_PORT/redirect" "$TASK_TRANSPORT_BINARY"
