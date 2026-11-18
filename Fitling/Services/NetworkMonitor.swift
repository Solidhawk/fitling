import Foundation
import Network
import Observation

/// Tells the app when the connection comes back, so pending changes are pushed right away.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isConnected = connected }
        }
        monitor.start(queue: DispatchQueue(label: "nl.fitling.network-monitor"))
    }
}
