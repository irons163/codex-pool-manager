import Foundation
import Network
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetBridgePublisher {
    static let widgetKind = "CodexPoolWidget"
    private static let stateLock = NSLock()
    private static let minimumPublishInterval: TimeInterval = 10
    private static var lastPublishedSignature: String?
    private static var lastPublishedAt: Date = .distantPast

    struct Snapshot: Codable {
        let updatedAt: Date
        let status: String
        let source: String
        let mode: String?
        let totalAccounts: Int?
        let availableAccounts: Int?
        let overallUsagePercent: Int?
        let activeAccountName: String?
        let activeIsPaid: Bool?
        let activeRemainingUnits: Int?
        let activeQuota: Int?
        let activeFiveHourRemainingPercent: Int?
        let activeWeeklyResetAt: Date?
        let activeFiveHourResetAt: Date?
    }

    static func configureBridge() {
        guard !isXCTestEnvironment() else { return }
        WidgetBridgeLocalServer.shared.startIfNeeded()
    }

    static func publishFromMainApp(status: String) {
        let snapshot = Snapshot(
            updatedAt: Date(),
            status: status,
            source: "CodexPoolManager",
            mode: nil,
            totalAccounts: nil,
            availableAccounts: nil,
            overallUsagePercent: nil,
            activeAccountName: nil,
            activeIsPaid: nil,
            activeRemainingUnits: nil,
            activeQuota: nil,
            activeFiveHourRemainingPercent: nil,
            activeWeeklyResetAt: nil,
            activeFiveHourResetAt: nil
        )
        publish(snapshot)
    }

    static func publish(from poolSnapshot: AccountPoolSnapshot) {
        let snapshot = buildSnapshot(from: poolSnapshot)
        publish(snapshot)
    }

    private static func buildSnapshot(
        from poolSnapshot: AccountPoolSnapshot,
        updatedAt: Date = Date()
    ) -> Snapshot {
        let includedAccounts = poolSnapshot.accounts.filter { !$0.isUsageSyncExcluded }
        let uniqueIncludedAccounts = uniqueAccounts(from: includedAccounts)
        let totalAccounts = uniqueIncludedAccounts.count
        let availableAccounts = uniqueIncludedAccounts.filter { $0.remainingUnits > 0 }.count
        let totalUsedUnits = uniqueIncludedAccounts.reduce(0) { $0 + $1.usedUnits }
        let totalQuota = uniqueIncludedAccounts.reduce(0) { $0 + $1.quota }
        let overallUsagePercent: Int
        if totalQuota > 0 {
            overallUsagePercent = Int((Double(totalUsedUnits) / Double(totalQuota) * 100).rounded())
        } else {
            overallUsagePercent = 0
        }

        let activeAccount = poolSnapshot.accounts.first(where: { $0.id == poolSnapshot.activeAccountID })
        let activeAccountName = activeAccount?.name
        let status = activeAccountName.map { "Active: \($0)" } ?? "No active account"
        let activeFiveHourRemainingPercent = activeAccount?.primaryUsagePercent.map { max(0, min(100, 100 - $0)) }

        return Snapshot(
            updatedAt: updatedAt,
            status: status,
            source: "CodexPoolManager",
            mode: poolSnapshot.mode.rawValue,
            totalAccounts: totalAccounts,
            availableAccounts: availableAccounts,
            overallUsagePercent: overallUsagePercent,
            activeAccountName: activeAccountName,
            activeIsPaid: activeAccount?.isPaid,
            activeRemainingUnits: activeAccount?.remainingUnits,
            activeQuota: activeAccount?.quota,
            activeFiveHourRemainingPercent: activeFiveHourRemainingPercent,
            activeWeeklyResetAt: activeAccount?.usageWindowResetAt,
            activeFiveHourResetAt: activeAccount?.primaryUsageResetAt
        )
    }

    private static func publish(
        _ snapshot: Snapshot,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || isXCTestEnvironment(environment: environment) {
            return
        }

        let signature = snapshotSignature(for: snapshot)
        let now = Date()
        guard !shouldThrottlePublish(signature: signature, now: now) else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            WidgetBridgeLocalServer.shared.startIfNeeded()
            WidgetBridgeLocalServer.shared.update(snapshotData: data)

            markPublished(signature: signature, at: now)

            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            NSLog("WidgetBridgePublisher failed: \(error.localizedDescription)")
        }
    }

    private static func isXCTestEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    private static func shouldThrottlePublish(
        signature: String,
        now: Date
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastPublishedSignature == signature &&
            now.timeIntervalSince(lastPublishedAt) < minimumPublishInterval
    }

    private static func markPublished(
        signature: String,
        at publishedAt: Date
    ) {
        stateLock.lock()
        lastPublishedSignature = signature
        lastPublishedAt = publishedAt
        stateLock.unlock()
    }

    private static func snapshotSignature(for snapshot: Snapshot) -> String {
        let activeRemaining = snapshot.activeRemainingUnits.map(String.init) ?? ""
        let activeQuota = snapshot.activeQuota.map(String.init) ?? ""
        let activeIsPaid = snapshot.activeIsPaid.map { $0 ? "1" : "0" } ?? ""
        let activeFiveHourRemaining = snapshot.activeFiveHourRemainingPercent.map(String.init) ?? ""
        let activeWeeklyReset = snapshot.activeWeeklyResetAt.map { String($0.timeIntervalSince1970) } ?? ""
        let activeFiveHourReset = snapshot.activeFiveHourResetAt.map { String($0.timeIntervalSince1970) } ?? ""
        let totalAccounts = snapshot.totalAccounts.map(String.init) ?? ""
        let availableAccounts = snapshot.availableAccounts.map(String.init) ?? ""
        let overallUsagePercent = snapshot.overallUsagePercent.map(String.init) ?? ""

        return [
            snapshot.status,
            snapshot.source,
            snapshot.mode ?? "",
            snapshot.activeAccountName ?? "",
            activeIsPaid,
            activeRemaining,
            activeQuota,
            activeFiveHourRemaining,
            activeWeeklyReset,
            activeFiveHourReset,
            totalAccounts,
            availableAccounts,
            overallUsagePercent
        ].joined(separator: "|")
    }

    private static func uniqueAccounts(from accounts: [AgentAccount]) -> [AgentAccount] {
        var seen = Set<String>()
        var unique: [AgentAccount] = []
        unique.reserveCapacity(accounts.count)

        for account in accounts {
            if seen.insert(account.deduplicationKey).inserted {
                unique.append(account)
            }
        }

        return unique
    }
}

#if DEBUG
extension WidgetBridgePublisher {
    static func debugBuildSnapshot(
        from poolSnapshot: AccountPoolSnapshot,
        updatedAt: Date
    ) -> Snapshot {
        buildSnapshot(from: poolSnapshot, updatedAt: updatedAt)
    }

    static func debugSnapshotSignature(for snapshot: Snapshot) -> String {
        snapshotSignature(for: snapshot)
    }

    static func debugUniqueAccountDedupKeys(from accounts: [AgentAccount]) -> [String] {
        uniqueAccounts(from: accounts).map(\.deduplicationKey)
    }

    static func debugShouldThrottle(signature: String, now: Date) -> Bool {
        shouldThrottlePublish(signature: signature, now: now)
    }

    static func debugMarkPublished(signature: String, at publishedAt: Date) {
        markPublished(signature: signature, at: publishedAt)
    }

    static func debugResetPublishState() {
        stateLock.lock()
        lastPublishedSignature = nil
        lastPublishedAt = .distantPast
        stateLock.unlock()
    }

    static func debugBridgeEndpoint() -> String {
        WidgetBridgeLocalServer.debugEndpoint()
    }

    static func debugResetBridgeServerState() {
        WidgetBridgeLocalServer.shared.debugResetForTests()
    }

    static func debugPublishFromMainApp(status: String, environment: [String: String]) {
        let snapshot = Snapshot(
            updatedAt: Date(),
            status: status,
            source: "CodexPoolManager",
            mode: nil,
            totalAccounts: nil,
            availableAccounts: nil,
            overallUsagePercent: nil,
            activeAccountName: nil,
            activeIsPaid: nil,
            activeRemainingUnits: nil,
            activeQuota: nil,
            activeFiveHourRemainingPercent: nil,
            activeWeeklyResetAt: nil,
            activeFiveHourResetAt: nil
        )
        publish(snapshot, environment: environment)
    }

    static func debugHTTPBridgeResponse(payload: Data) -> Data {
        WidgetBridgeLocalServer.debugResponseData(payload: payload)
    }
}
#endif

private final class WidgetBridgeLocalServer {
    static let shared = WidgetBridgeLocalServer()

    private static var port: NWEndpoint.Port {
        if let configured = ProcessInfo.processInfo.environment["WIDGET_BRIDGE_PORT"],
           let rawValue = UInt16(configured),
           let port = NWEndpoint.Port(rawValue: rawValue)
        {
            return port
        }
        return NWEndpoint.Port(rawValue: 38477)!
    }
    private static let listenerQueue = DispatchQueue(label: "WidgetBridgeLocalServer.queue")
    private static var endpoint: String { "http://127.0.0.1:\(port.rawValue)/widget-snapshot" }

    private var listener: NWListener?
    private var latestSnapshotData = Data()
    private var hasStarted = false

    private init() {}

    func startIfNeeded() {
        Self.listenerQueue.async {
            guard !self.hasStarted else { return }
            self.hasStarted = true

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true

                let listener = try NWListener(using: parameters, on: Self.port)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        NSLog("WidgetBridgeLocalServer listening at \(Self.endpoint)")
                    case .failed(let error):
                        NSLog("WidgetBridgeLocalServer failed: \(error.localizedDescription)")
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection: connection)
                }

                self.listener = listener
                listener.start(queue: Self.listenerQueue)
            } catch {
                NSLog("WidgetBridgeLocalServer failed to start: \(error.localizedDescription)")
            }
        }
    }

    func update(snapshotData: Data) {
        Self.listenerQueue.async {
            self.latestSnapshotData = snapshotData
        }
    }

    private func serve(connection: NWConnection) {
        connection.start(queue: Self.listenerQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let payload = self.latestSnapshotData
            let response = Self.responseData(payload: payload)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func responseData(payload: Data) -> Data {
        let statusLine = payload.isEmpty ? "HTTP/1.1 204 No Content\r\n" : "HTTP/1.1 200 OK\r\n"
        var headers = statusLine
        headers += "Content-Type: application/json\r\n"
        headers += "Content-Length: \(payload.count)\r\n"
        headers += "Connection: close\r\n\r\n"

        var response = Data(headers.utf8)
        response.append(payload)
        return response
    }
}

#if DEBUG
extension WidgetBridgeLocalServer {
    static func debugEndpoint() -> String { endpoint }
    static func debugResponseData(payload: Data) -> Data { responseData(payload: payload) }

    func debugResetForTests() {
        Self.listenerQueue.sync {
            listener?.cancel()
            listener = nil
            latestSnapshotData = Data()
            hasStarted = false
        }
    }
}
#endif
