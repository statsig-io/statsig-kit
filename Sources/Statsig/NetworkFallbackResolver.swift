import Foundation

public protocol FallbackResolverArgs {
    var fallbackUrl: String? { get }
}

public struct FallbackInfoEntry {
    var url: URL
    var previous: [String]
    var expiryTime: Date
}

typealias FallbackInfo = [Endpoint: FallbackInfoEntry]

let DEFAULT_TTL_SECONDS: TimeInterval = 7 * 24 * 60 * 60  // 7 days (in seconds)
let COOLDOWN_TIME_SECONDS: TimeInterval = 4 * 60 * 60  // 4 hours (in seconds)

let notDomainFailureCodes: [Int] = [
    NSURLErrorCancelled,
    NSURLErrorNotConnectedToInternet,
]

#if TEST
let DEFAULT_NETWORK_FALLBACK_ENABLED = false
#else
let DEFAULT_NETWORK_FALLBACK_ENABLED = true
#endif

public class NetworkFallbackResolver {

    private let sdkKey: String
    private var store: InternalStore
    private var errorBoundary: ErrorBoundary
    private var fallbackInfo: FallbackInfo? = nil

    private var dnsQueryCooldowns: [Endpoint: Date] = [:]

    /**
     Function to get the current Date. Used for tests.
     */
    internal static var now: () -> Date = { Date() }

    internal static var fallbackEnabled = DEFAULT_NETWORK_FALLBACK_ENABLED

    init(sdkKey: String, store: InternalStore, errorBoundary: ErrorBoundary) {
        self.sdkKey = sdkKey
        self.store = store
        self.errorBoundary = errorBoundary
    }

    func tryBumpExpiryTime(endpoint: Endpoint) {
        if var info = self.fallbackInfo?[endpoint] {
            info.expiryTime = NetworkFallbackResolver.now().addingTimeInterval(DEFAULT_TTL_SECONDS)
            self.fallbackInfo?[endpoint] = info
            self.store.saveNetworkFallbackInfo(self.fallbackInfo)
        }
    }

    internal func getActiveFallbackURL(
        endpoint: Endpoint
    ) -> URL? {
        var info = self.fallbackInfo
        if info == nil {
            info = self.store.getNetworkFallbackInfo()
            self.fallbackInfo = info
        }

        guard let entry = info?[endpoint] else {
            return nil
        }

        // If the entry exists, but is expired, we remove that endpoint from fallbackInfo
        guard NetworkFallbackResolver.now() <= entry.expiryTime else {
            self.fallbackInfo?.removeValue(forKey: endpoint)
            self.store.saveNetworkFallbackInfo(self.fallbackInfo)
            return nil
        }

        self.fallbackInfo = info

        return entry.url
    }

    func isDomainFailure(error: (any Error)?) -> Bool {
        if !NetworkFallbackResolver.fallbackEnabled {
            return false
        }
        if let nsError = error as? NSError {
            return
                (nsError.domain == NSURLErrorDomain
                && !notDomainFailureCodes.contains(nsError.code))
        }
        return false
    }

    func tryFetchUpdatedFallbackInfo(
        endpoint: Endpoint,
        completion: @escaping (_ fallbackUpdated: Bool) -> Void
    ) {
        let now = NetworkFallbackResolver.now()
        if let cooldown = self.dnsQueryCooldowns[endpoint], now < cooldown {
            return
        }

        self.dnsQueryCooldowns[endpoint] = now.addingTimeInterval(COOLDOWN_TIME_SECONDS)

        fetchTxtRecords { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            completion(self.handleTxtQueryResult(endpoint: endpoint, result: result))
        }
    }

    private func handleTxtQueryResult(endpoint: Endpoint, result: Result<[String], Error>) -> Bool {
        let records: [String]
        switch result {
        case .failure(let error):
            self.errorBoundary.logException(tag: "network_fallback_resolver", error: error)
            return false
        case .success(let value):
            records = value
        }

        guard
            let defaultURL: URL = NetworkService.defaultURLForEndpoint(endpoint),
            let defaultURLComponents = URLComponents(url: defaultURL, resolvingAgainstBaseURL: true)
        else {
            self.errorBoundary.logException(
                tag: "network_fallback_resolver",
                error: StatsigError.invalidRequestURL("\(endpoint)"))
            return false
        }

        let urls = parseURLsFromRecords(
            records, endpoint: endpoint, defaultURLComponents: defaultURLComponents)
        guard
            let newURL = pickNewFallbackUrl(
                currentFallbackInfo: self.fallbackInfo?[endpoint], urls: urls)
        else {
            return false
        }

        updateFallbackInfoWithNewURL(endpoint: endpoint, newURL: newURL)
        return true
    }

    private func updateFallbackInfoWithNewURL(endpoint: Endpoint, newURL: URL) {
        var newFallbackInfo = FallbackInfoEntry(
            url: newURL,
            previous: [],
            expiryTime: NetworkFallbackResolver.now().addingTimeInterval(DEFAULT_TTL_SECONDS)
        )

        if let previousInfo = self.fallbackInfo?[endpoint] {
            newFallbackInfo.previous.append(contentsOf: previousInfo.previous)
            newFallbackInfo.previous.append(previousInfo.url.absoluteString)
        }

        if newFallbackInfo.previous.count > 10 {
            newFallbackInfo.previous = []
        }

        self.fallbackInfo?[endpoint] = newFallbackInfo

        self.store.saveNetworkFallbackInfo(self.fallbackInfo)
    }

    private func parseURLsFromRecords(
        _ records: [String], endpoint: Endpoint, defaultURLComponents: URLComponents
    ) -> [URL] {
        var urls = [URL]()
        for record in records {
            let startsWith = "\(endpoint.dnsKey)="
            if !record.starts(with: startsWith) {
                continue
            }

            let start = record.index(record.startIndex, offsetBy: startsWith.count)
            var urlComponents = defaultURLComponents
            urlComponents.host = removingTrailingSlash(record[start...])
            if let url = urlComponents.url {
                urls.append(url)
            } else {
                self.errorBoundary.logException(
                    tag: "parse_dns_txt",
                    error: StatsigError.unexpectedError("Failed to parse URL from DNS TXT records"))
            }
        }
        return urls
    }

    private func pickNewFallbackUrl(currentFallbackInfo: FallbackInfoEntry?, urls: [URL]) -> URL? {
        let previouslyUsed = Set(currentFallbackInfo?.previous ?? [])
        let currentFallbackUrl = currentFallbackInfo?.url.absoluteString

        for loopUrl in urls {
            let loopURLString = loopUrl.absoluteString
            let urlString = removingTrailingSlash(loopURLString)

            if !previouslyUsed.contains(urlString) && urlString != currentFallbackUrl,
                let url = URL(string: urlString)
            {
                return url
            }
        }

        return nil
    }
}

func getFallbackInfoStorageKey(sdkKey: String) -> String {
    return "statsig.network_fallback.\(sdkKey.djb2())"
}

fileprivate func removingTrailingSlash<T>(_ str: T) -> String where T: StringProtocol {
    let end = str.index(str.endIndex, offsetBy: str.hasSuffix("/") ? -1 : 0)
    return String(str[..<end])
}
