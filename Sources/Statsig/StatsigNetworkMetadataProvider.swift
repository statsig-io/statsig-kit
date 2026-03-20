import Foundation

#if canImport(Network)
import Network
#endif

internal protocol StatsigNetworkMetadataProvider {
    func getLogEventNetworkMetadata() -> [String: String]
    func shutdown()
}

internal struct StatsigNoOpNetworkMetadataProvider: StatsigNetworkMetadataProvider {
    func getLogEventNetworkMetadata() -> [String: String] {
        return [:]
    }

    func shutdown() {}
}

internal final class StatsigEnabledNetworkMetadataProvider: StatsigNetworkMetadataProvider {
    static let netTypeKey = "netType"
    static let hasInternetKey = "hasInternet"

    private let lock = NSLock()

    #if canImport(Network)
    private let monitorQueue = DispatchQueue(label: "com.Statsig.networkMetadata")
    private let pathMonitor: AnyObject?
    #endif

    init() {
        #if canImport(Network)
        if #available(iOS 12.0, macOS 10.14, tvOS 12.0, watchOS 6.0, *) {
            let monitor = NWPathMonitor()
            monitor.start(queue: monitorQueue)
            pathMonitor = monitor
        } else {
            pathMonitor = nil
        }
        #endif
    }

    deinit {
        shutdown()
    }

    func getLogEventNetworkMetadata() -> [String: String] {
        #if canImport(Network)
        if #available(iOS 12.0, macOS 10.14, tvOS 12.0, watchOS 6.0, *) {
            if let pathMonitor = pathMonitor as? NWPathMonitor {
                return lock.withLock {
                    Self.makeMetadata(path: pathMonitor.currentPath)
                }
            }
        }
        #endif

        return [:]
    }

    func shutdown() {
        #if canImport(Network)
        if #available(iOS 12.0, macOS 10.14, tvOS 12.0, watchOS 6.0, *) {
            lock.withLock {
                (pathMonitor as? NWPathMonitor)?.cancel()
            }
        }
        #endif
    }

    #if canImport(Network)
    @available(iOS 12.0, macOS 10.14, tvOS 12.0, watchOS 6.0, *)
    private static func makeMetadata(path: NWPath) -> [String: String] {
        let hasInternet = path.status == .satisfied
        let netType = makeNetworkType(
            hasInternet: hasInternet,
            usesWifi: path.usesInterfaceType(.wifi),
            usesCellular: path.usesInterfaceType(.cellular),
            usesWiredEthernet: path.usesInterfaceType(.wiredEthernet),
            usesOther: path.usesInterfaceType(.other))

        return [
            netTypeKey: netType,
            hasInternetKey: hasInternet ? "true" : "false",
        ]
    }
    #endif

    internal static func makeNetworkType(
        hasInternet: Bool,
        usesWifi: Bool,
        usesCellular: Bool,
        usesWiredEthernet: Bool,
        usesOther: Bool
    ) -> String {
        guard hasInternet else {
            return "none"
        }

        if usesWifi {
            return "wifi"
        }
        if usesCellular {
            return "cell"
        }
        if usesWiredEthernet {
            return "ethernet"
        }
        if usesOther {
            return "other"
        }

        return "none"
    }
}
