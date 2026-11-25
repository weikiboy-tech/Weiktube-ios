// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Network
import Foundation

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var cellular = false
    @Published private(set) var constrained = false
    @Published private(set) var connected = false
    /// Start conservatively until an unmetered Wi-Fi/Ethernet path is actually known.
    @Published private(set) var useMobileQuality = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.weiktube.ios.network", qos: .utility)
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular)
            let constrained = path.isConstrained
            let connected = path.status == .satisfied
            let knownUnmetered = connected && !path.isExpensive && !constrained &&
                (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor [weak self] in
                self?.cellular = cellular; self?.constrained = constrained; self?.connected = connected
                self?.useMobileQuality = !knownUnmetered
            }
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }
}
