import Foundation

nonisolated enum CodexSessionLogParser {
    nonisolated struct Signature: Hashable, Sendable {
        let total: CodexSessionTokens?
        let last: CodexSessionTokens?
    }

    nonisolated struct Event: Sendable {
        let index: Int
        let timestamp: Date
        let model: String
        let signature: Signature
        let tokens: CodexSessionTokens
    }

    nonisolated struct FileUsage: Sendable {
        var sessionID: String?
        var parentID: String?
        var startedAt: Date?
        var events: [Event] = []
        var isLimited = false
        var hasConflictingParent = false

        nonisolated init() {}
    }

    nonisolated struct Reader: Sendable {
        var result = FileUsage()
        var model = "unknown"
        var highWater = CodexSessionTokens()
        var signaturesBySource: [String: Signature] = [:]
        var previousSignature: Signature?
        var eventIndex = 0
        var branchStartedAt: Date?

        nonisolated init() {}

        nonisolated mutating func consume(_ data: Data) {
            let head = String(decoding: data.prefix(512), as: UTF8.self)
            guard head.contains("session_meta") || head.contains("turn_context") || head.contains("token_count"),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = value["type"] as? String,
                  let payload = value["payload"] as? [String: Any] else { return }
            switch type {
            case "session_meta":
                let timestamp = CodexSessionLogParser.date(value["timestamp"])
                if result.startedAt == nil { result.startedAt = timestamp }
                if result.sessionID == nil { result.sessionID = CodexSessionLogParser.threadID(payload["id"] ?? payload["thread_id"]) }
                let fork = CodexSessionLogParser.threadID(payload["forked_from_id"])
                let source = payload["source"] as? [String: Any]
                let subagent = source?["subagent"] as? [String: Any]
                let spawn = subagent?["thread_spawn"] as? [String: Any]
                let spawned = CodexSessionLogParser.threadID(spawn?["parent_thread_id"])
                if let fork, let spawned, fork != spawned { result.hasConflictingParent = true }
                if let existing = result.parentID, let incoming = fork ?? spawned, existing != incoming { result.hasConflictingParent = true }
                if fork != nil || spawned != nil {
                    if let timestamp { branchStartedAt = branchStartedAt.map { min($0, timestamp) } ?? timestamp }
                    result.startedAt = branchStartedAt
                    result.sessionID = CodexSessionLogParser.threadID(payload["id"] ?? payload["thread_id"]) ?? result.sessionID
                }
                result.parentID = fork ?? spawned ?? result.parentID
            case "turn_context":
                if let raw = payload["model"] as? String { model = CodexSessionAnalytics.normalizedModel(String(raw.prefix(120))) }
            case "event_msg":
                guard payload["type"] as? String == "token_count" else { return }
                eventIndex += 1
                guard let info = payload["info"] as? [String: Any] else { return }
                if let raw = (info["model"] ?? info["model_name"] ?? payload["model"]) as? String {
                    model = CodexSessionAnalytics.normalizedModel(String(raw.prefix(120)))
                }
                let total = CodexSessionLogParser.tokens(info["total_token_usage"])
                let last = CodexSessionLogParser.tokens(info["last_token_usage"])
                guard total != nil || last != nil else { return }
                let signature = Signature(total: total, last: last)
                let limits = payload["rate_limits"] as? [String: Any]
                let source = limits?["limit_id"] as? String ?? ""
                let duplicate = total != nil && (signaturesBySource[source] == signature || previousSignature == signature)
                if total != nil { signaturesBySource[source] = signature }
                previousSignature = signature
                let delta = last ?? total?.delta(from: highWater) ?? CodexSessionTokens()
                if let total { highWater = highWater.highWater(with: total) }
                guard !duplicate, !delta.isEmpty, let timestamp = CodexSessionLogParser.date(value["timestamp"]) else { return }
                guard result.events.count < 25_000 else { result.isLimited = true; return }
                result.events.append(Event(index: eventIndex, timestamp: timestamp, model: model.isEmpty ? "unknown" : model, signature: signature, tokens: delta))
            default: break
            }
        }
    }

    nonisolated static func parse(_ text: String, fileName: String = "") -> FileUsage {
        var reader = Reader()
        for line in text.split(separator: "\n") { reader.consume(Data(line.utf8)) }
        resolveFileID(&reader.result, fileName: fileName)
        return reader.result
    }

    nonisolated static func read(_ url: URL) throws -> FileUsage {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var reader = Reader()
        var pending = Data()
        var discardingLine = false
        var bytesRead = 0
        let byteLimit = 128 * 1_024 * 1_024
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            bytesRead += chunk.count
            guard bytesRead <= byteLimit else { reader.result.isLimited = true; break }
            let parts = chunk.split(separator: 10, omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if !discardingLine {
                    pending.append(contentsOf: part)
                    if pending.count > 512 * 1_024 {
                        let head = String(decoding: pending.prefix(512), as: UTF8.self)
                        if head.contains("token_count") { reader.result.isLimited = true }
                        pending.removeAll(keepingCapacity: true)
                        discardingLine = true
                    }
                }
                if index < parts.count - 1 {
                    if !discardingLine { reader.consume(pending) }
                    pending.removeAll(keepingCapacity: true)
                    discardingLine = false
                }
            }
        }
        if !pending.isEmpty && !discardingLine { reader.consume(pending) }
        resolveFileID(&reader.result, fileName: url.lastPathComponent)
        return reader.result
    }

    nonisolated private static func resolveFileID(_ result: inout FileUsage, fileName: String) {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.matches(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)).last,
           let range = Range(match.range, in: fileName) {
            result.sessionID = String(fileName[range]).lowercased()
        }
    }

    nonisolated private static func threadID(_ value: Any?) -> String? {
        guard let raw = value as? String, let id = UUID(uuidString: raw) else { return nil }
        return id.uuidString.lowercased()
    }

    nonisolated private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, text.count < 80 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    nonisolated private static func tokens(_ value: Any?) -> CodexSessionTokens? {
        guard let fields = value as? [String: Any] else { return nil }
        let keys = ["input_tokens", "cached_input_tokens", "cache_read_input_tokens", "output_tokens"]
        guard keys.contains(where: { fields[$0] is NSNumber }) else { return nil }
        func count(_ key: String) -> Int64 {
            guard let number = fields[key] as? NSNumber else { return 0 }
            let value = number.doubleValue
            guard value.isFinite, value >= 0, value <= 1_000_000_000_000 else { return 0 }
            return Int64(value)
        }
        return CodexSessionTokens(input: count("input_tokens"), cachedInput: fields["cached_input_tokens"] != nil ? count("cached_input_tokens") : count("cache_read_input_tokens"), output: count("output_tokens"))
    }

    nonisolated static func report(from files: [FileUsage]) -> CodexSessionUsageReport {
        var report = CodexSessionUsageReport(scannedFiles: files.count)
        var byID: [String: FileUsage] = [:]
        for file in files {
            report.isLimited = report.isLimited || file.isLimited
            guard let id = file.sessionID, !file.hasConflictingParent else {
                if !file.events.isEmpty { report.deferredFiles += 1 }
                continue
            }
            if byID[id] == nil || (byID[id]?.events.count ?? 0) < file.events.count { byID[id] = file }
        }
        for (id, file) in byID {
            var events = file.events
            if let parentID = file.parentID {
                guard parentID != id, let parent = byID[parentID], let cutoff = file.startedAt else {
                    report.deferredFiles += 1
                    continue
                }
                let parentSignatures = parent.events.filter { $0.timestamp <= cutoff }.map(\.signature)
                var cursor = 0
                var replayCount = 0
                for event in events {
                    guard let match = parentSignatures[cursor...].firstIndex(of: event.signature) else { break }
                    cursor = match + 1
                    replayCount += 1
                }
                events.removeFirst(replayCount)
            }
            report.records.append(contentsOf: events.map { event in
                CodexSessionUsageRecord(id: "\(id):\(event.index)", timestamp: event.timestamp, sessionID: id, model: event.model, tokens: event.tokens)
            })
        }
        report.records.sort { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
        if report.records.count > 100_000 {
            report.records = Array(report.records.prefix(100_000))
            report.isLimited = true
        }
        return report
    }
}

actor CodexSessionUsageStore {
    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }
    private var cache: [URL: (Stamp, CodexSessionLogParser.FileUsage)] = [:]

    func scan(root: URL) throws -> CodexSessionUsageReport {
        let fileManager = FileManager.default
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let children = ["sessions", "archived_sessions"].map { root.appendingPathComponent($0, isDirectory: true) }
        var directories = children.filter { fileManager.fileExists(atPath: $0.path) }
        if directories.isEmpty && root.lastPathComponent != ".codex" { directories = [root] }
        var paths: [URL] = []
        var limited = false
        var unavailable = 0
        for directory in directories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in unavailable += 1; return true }) else { unavailable += 1; continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard url.pathExtension == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { unavailable += 1; continue }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                guard paths.count < 10_000 else { limited = true; break }
                paths.append(url)
            }
        }
        var parsed: [CodexSessionLogParser.FileUsage] = []
        var eventCount = 0
        for url in paths.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            guard eventCount < 250_000 else { limited = true; break }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let stamp = Stamp(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
                let file: CodexSessionLogParser.FileUsage
                if let existing = cache[url], existing.0 == stamp { file = existing.1 }
                else {
                    file = try CodexSessionLogParser.read(url)
                    cache[url] = (stamp, file)
                }
                parsed.append(file)
                eventCount += file.events.count
            } catch is CancellationError { throw CancellationError() }
            catch { unavailable += 1 }
        }
        let livePaths = Set(paths)
        cache = cache.filter { livePaths.contains($0.key) }
        var report = CodexSessionLogParser.report(from: parsed)
        report.unavailableFiles = unavailable
        report.isLimited = report.isLimited || limited
        return report
    }
}
