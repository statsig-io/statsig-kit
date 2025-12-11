import Foundation
import Nimble
import OHHTTPStubs

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

func skipFrame() {
    waitUntil { done in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            done()
        }
    }
}

class TestUtils {
    static func clearStorage() {
        InternalStore.deleteAllLocalStorage()
    }

    static func startStatsigAndWait(
        key: String, _ user: StatsigUser? = nil, _ options: StatsigOptions? = nil
    ) {
        var called = false
        waitUntil(timeout: .seconds(10)) { done in
            Statsig.client = nil
            Statsig.initialize(sdkKey: key, user: user, options: options) { _ in
                called = true
                done()
            }
        }

        if !called {
            let stubs = HTTPStubs.allStubs() as? [HTTPStubsDescriptor]
            fatalError("Failed to start Statsig. Stubs: \(String(describing: stubs))")
        }
    }

    static func startWithResponseAndWait(
        _ response: [String: Any], _ key: String = "client-api-key"
    ) -> URLRequest? {
        return startWithResponseAndWait(response, key, nil)
    }

    static func startWithResponseAndWait(
        _ response: [String: Any], _ key: String = "client-api-key", _ user: StatsigUser? = nil
    ) -> URLRequest? {
        return startWithResponseAndWait(response, key, user, 200)
    }

    static func startWithResponseAndWait(
        _ response: [String: Any], _ key: String = "client-api-key", _ user: StatsigUser? = nil,
        _ statusCode: Int32 = 200
    ) -> URLRequest? {
        return startWithResponseAndWait(response, key, user, 200, options: nil)
    }

    static func startWithResponseAndWait(
        _ response: [String: Any], _ key: String = "client-api-key", _ user: StatsigUser? = nil,
        _ statusCode: Int32 = 200, options: StatsigOptions? = nil
    ) -> URLRequest? {
        var result: URLRequest? = nil
        let host =
            options?.initializationURL?.host ?? NetworkService.defaultInitializationURL?.host
            ?? ApiHost
        let handle = stub(condition: isHost(host)) { req in
            result = req
            return HTTPStubsResponse(jsonObject: response, statusCode: statusCode, headers: nil)
        }

        let opts = options ?? StatsigOptions(disableDiagnostics: true)

        TestUtils.startStatsigAndWait(key: key, user, opts)

        HTTPStubs.removeStub(handle)

        return result
    }

    static func startWithStatusAndWait(
        _ statusCode: Int32 = 200, _ key: String = "client-api-key", _ user: StatsigUser? = nil,
        options: StatsigOptions? = nil
    ) -> URLRequest? {
        var result: URLRequest? = nil
        stub(
            condition: isHost(
                options?.initializationURL?.host ?? NetworkService.defaultInitializationURL?.host
                    ?? ApiHost)
        ) { req in
            result = req
            return HTTPStubsResponse(data: Data(), statusCode: statusCode, headers: nil)
        }

        let opts = options ?? StatsigOptions(disableDiagnostics: true)
        TestUtils.startStatsigAndWait(key: key, user, opts)

        return result
    }

    static func captureLogs(
        host: String = LogEventHost,
        path: String = "/v1/rgstr",
        removeDiagnostics: Bool = true,
        onLog: @escaping ([String: Any]) -> Void
    ) {
        stub(condition: isHost(host) && isPath(path)) { request in
            var data =
                try! JSONSerialization.jsonObject(with: request.ohhttpStubs_httpBody!, options: [])
                as! [String: Any]
            if removeDiagnostics, let events = data["events"] as? [[String: Any]] {
                data["events"] = events.filter({ item in
                    return item["eventName"] as? String != "statsig::diagnostics"
                })
            }
            onLog(data)
            return HTTPStubsResponse(
                jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
        }
    }

    static func getBody(fromRequest req: URLRequest) -> [String: Any] {
        return try! JSONSerialization.jsonObject(
            with: req.ohhttpStubs_httpBody!,
            options: []) as! [String: Any]
    }

    static func makeInitializeResponse(_ configValue: String) -> [String: Any] {
        return [
            "feature_gates": [:],
            "dynamic_configs": [
                "a_config".sha256(): [
                    "name": "a_config".sha256(),
                    "rule_id": "default",
                    "value": ["key": configValue],
                ]
            ],
            "layer_configs": [:],
            "time": 111,
            "has_updates": true,
        ]
    }

    static func resetDefaultURLs() {
        NetworkService.defaultInitializationURL = URL(
            string: "https://\(ApiHost)\(Endpoint.initialize.rawValue)")
        NetworkService.defaultEventLoggingURL = URL(
            string: "https://\(LogEventHost)\(Endpoint.logEvent.rawValue)")
    }

    static func freezeThreadUntilAsyncDone(
        dispatchQueue: DispatchQueue = DispatchQueue.global(), _ callback: @escaping () -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)

        dispatchQueue.async {
            callback()

            // Unblocks calling thread
            semaphore.signal()
        }

        semaphore.wait()
    }
}

extension CompressionType {
    static func from(header: String?) -> CompressionType? {
        switch header {
        case nil: return CompressionType.none
        case "gzip": return .gzip
        default: return nil
        }
    }
}

extension URLRequest {
    public var statsig_decodedBody: Data? {
        guard let body = ohhttpStubs_httpBody else {
            return nil
        }

        let contentEncoding = self.value(forHTTPHeaderField: "Content-Encoding")
        return switch CompressionType.from(header: contentEncoding) {
        case .gzip: try! body.gunzipped()
        default: body
        }
    }

    public var statsig_body: [String: Any]? {
        guard let body = statsig_decodedBody else {
            return nil
        }

        return try? JSONSerialization.jsonObject(
            with: body,
            options: []) as? [String: Any]
    }
}
