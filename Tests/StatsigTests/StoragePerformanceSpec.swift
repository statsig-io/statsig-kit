import Foundation
import OHHTTPStubs
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

let baseUser = StatsigUser(
    userID: "tore",
    email: "user-a@statsig.io",
    ip: "1.2.3.4",
    country: "US",
    locale: "en_US",
    appVersion: "3.2.1",
    custom: ["isVerified": true, "hasPaid": false],
    privateAttributes: ["age": 34, "secret": "shhh"],
    customIDs: [
        "workID": "employee-a",
        "projectID": "project-a",
        "stableID": "272DE7E1-1947-4A8D-BDFE-005751F1EC2A",
    ]
)

final class StoragePerformanceSpec: XCTestCase {
    private let sdkKey = "client-api-key"
    private let iterations = 200

    private let benchHost = "StoragePerformanceSpecBenchmark"
    private lazy var benchURL = URL(
        string: "http://\(benchHost)\(Endpoint.initialize.rawValue)"
    )!
    private let options = StatsigOptions(disableDiagnostics: true)

    private lazy var benchUser: StatsigUser = makeUser(testID: 0)
    private lazy var payload: [String: Any] = {
        let bundle = Bundle(for: type(of: self))
        if let resBundlePath = bundle.path(forResource: "Statsig_StatsigTests", ofType: "bundle"),
            let resBundle = Bundle(path: resBundlePath),
            let jsonUrl = resBundle.url(forResource: "initialize", withExtension: "json"),
            let data = try? Data(contentsOf: jsonUrl),
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        {
            return json
        }

        return TestUtils.makeInitializeResponse("bench_value")
    }()

    private func makeUser(testID: Int) -> StatsigUser {
        var custom = (baseUser.custom ?? [:]).compactMapValues { $0 }
        custom["statsig_test_id"] = String(testID)

        return StatsigUser(
            userID: baseUser.userID,
            email: baseUser.email,
            ip: baseUser.ip,
            country: baseUser.country,
            locale: baseUser.locale,
            custom: custom,
            customIDs: baseUser.customIDs,
            userAgent: baseUser.userAgent
        )
    }

    private func prefillStorage(userCount: Int, useMultiFile: Bool) {
        let storageService = StorageService(sdkKey: sdkKey)
        var cacheByID: [String: [String: Any]] = [:]

        for i in 0..<userCount {
            let prefillUser = makeUser(testID: i)
            let cacheKey = UserCacheKey.from(options, prefillUser, sdkKey)

            if useMultiFile {
                storageService.userPayload.write(key: cacheKey, payload: payload)
            }

            cacheByID[cacheKey.fullUserWithSDKKey] = payload
        }

        if !useMultiFile {
            StatsigUserDefaults.defaults.setDictionarySafe(
                cacheByID,
                forKey: UserDefaultsKeys.localStorageKey
            )
            _ = StatsigUserDefaults.defaults.synchronize()
        }
    }

    private func stubInitializeEndpoint() {
        NetworkService.defaultInitializationURL = benchURL
        stub(condition: isHost(benchHost)) { _ in
            HTTPStubsResponse(jsonObject: self.payload, statusCode: 200, headers: nil)
        }
    }

    private func stubRegisterEndpoint() {
        let logHost = NetworkService.defaultEventLoggingURL?.host ?? LogEventHost
        stub(condition: isHost(logHost) && isPath(Endpoint.logEvent.rawValue)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Ensure we start from a clean slate for each performance test.
        TestUtils.clearStorage()
        Statsig.shutdown()
        TestUtils.resetDefaultURLs()
        HTTPStubs.removeAllStubs()
    }

    override func tearDownWithError() throws {
        Statsig.shutdown()
        TestUtils.clearStorage()
        TestUtils.resetDefaultURLs()
        HTTPStubs.removeAllStubs()
        StorageService.useMultiFileStorage = false
        try super.tearDownWithError()
    }

    func testInitializePerformanceMultiFileStorage() throws {
        // Comment next line to run benchmark
        try XCTSkipIf(true, "Benchmark skipped by default")

        StorageService.useMultiFileStorage = true
        stubInitializeEndpoint()
        stubRegisterEndpoint()
        prefillStorage(userCount: 10, useMultiFile: true)

        measure {
            for _ in 0..<iterations {
                TestUtils.startStatsigAndWait(key: sdkKey, benchUser, options)
                Statsig.shutdown()
            }
        }
    }

    func testInitializePerformanceUserDefaultsStorage() throws {
        // Comment next line to run benchmark
        try XCTSkipIf(true, "Benchmark skipped by default")

        StorageService.useMultiFileStorage = false
        stubInitializeEndpoint()
        stubRegisterEndpoint()
        prefillStorage(userCount: 10, useMultiFile: false)

        measure {
            for _ in 0..<iterations {
                TestUtils.startStatsigAndWait(key: sdkKey, benchUser, options)
                Statsig.shutdown()
            }
        }
    }
}
