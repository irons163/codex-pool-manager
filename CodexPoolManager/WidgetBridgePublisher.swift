import Foundation
import Network
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetBridgePublisher {
    static let widgetKind = "CodexPoolWidget"
    private static let stateLock = NSLock()
    private static let minimumPublishInterval: TimeInterval = 30
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
    }

    static func configureBridge() {
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
            activeFiveHourRemainingPercent: nil
        )
        publish(snapshot)
    }

    static func publish(from poolSnapshot: AccountPoolSnapshot) {
        let includedAccounts = poolSnapshot.accounts.filter { !$0.isUsageSyncExcluded }
        let totalAccounts = includedAccounts.count
        let availableAccounts = includedAccounts.filter { $0.remainingUnits > 0 }.count
        let totalUsedUnits = includedAccounts.reduce(0) { $0 + $1.usedUnits }
        let totalQuota = includedAccounts.reduce(0) { $0 + $1.quota }
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

        let snapshot = Snapshot(
            updatedAt: Date(),
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
            activeFiveHourRemainingPercent: activeFiveHourRemainingPercent
        )
        publish(snapshot)
    }

    private static func publish(_ snapshot: Snapshot) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }

        let signature = snapshotSignature(for: snapshot)
        let now = Date()
        stateLock.lock()
        let shouldThrottle = lastPublishedSignature == signature &&
            now.timeIntervalSince(lastPublishedAt) < minimumPublishInterval
        stateLock.unlock()
        guard !shouldThrottle else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            WidgetBridgeLocalServer.shared.startIfNeeded()
            WidgetBridgeLocalServer.shared.update(snapshotData: data)

            stateLock.lock()
            lastPublishedSignature = signature
            lastPublishedAt = now
            stateLock.unlock()

            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            #endif
        } catch {
            NSLog("WidgetBridgePublisher failed: \(error.localizedDescription)")
        }
    }

    private static func snapshotSignature(for snapshot: Snapshot) -> String {
        let activeRemaining = snapshot.activeRemainingUnits.map(String.init) ?? ""
        let activeQuota = snapshot.activeQuota.map(String.init) ?? ""
        let activeIsPaid = snapshot.activeIsPaid.map { $0 ? "1" : "0" } ?? ""
        let activeFiveHourRemaining = snapshot.activeFiveHourRemainingPercent.map(String.init) ?? ""
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
            totalAccounts,
            availableAccounts,
            overallUsagePercent
        ].joined(separator: "|")
    }
}

private final class WidgetBridgeLocalServer {
    static let shared = WidgetBridgeLocalServer()

    private static let port: NWEndpoint.Port = 38477
    private static let listenerQueue = DispatchQueue(label: "WidgetBridgeLocalServer.queue")
    private static let endpoint = "http://127.0.0.1:\(port.rawValue)/widget-snapshot"

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
            let statusLine = payload.isEmpty ? "HTTP/1.1 204 No Content\r\n" : "HTTP/1.1 200 OK\r\n"
            var headers = statusLine
            headers += "Content-Type: application/json\r\n"
            headers += "Content-Length: \(payload.count)\r\n"
            headers += "Connection: close\r\n\r\n"

            var response = Data(headers.utf8)
            response.append(payload)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
