import Foundation
import OHHTTPStubs
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class CacheByFileInstanceTests: XCTestCase {
    private var previousDefaults: DefaultsLike!
    private var suiteName: String!
    private var suite: UserDefaults!
    private var clients: [StatsigClient] = []

    override func setUp() {
        super.setUp()
        previousDefaults = StatsigUserDefaults.defaults
        suiteName = "CacheByFileInstanceTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        StatsigUserDefaults.defaults = suite
        clearFileCache()
        StorageServiceMigrationStatus.resetState(migrationStatus: .legacy, hasStateBeenSet: true)
    }

    override func tearDown() {
        Statsig.shutdown()
        HTTPStubs.removeAllStubs()
        clients.forEach { $0.shutdown() }
        clients = []
        clearFileCache()
        suite.removePersistentDomain(forName: suiteName)
        StatsigUserDefaults.defaults = previousDefaults
        StorageServiceMigrationStatus.resetState(migrationStatus: .legacy, hasStateBeenSet: true)
        super.tearDown()
    }

    private func clearFileCache() {
        let file = StatsigUserDefaults.fileDefaults
        for key in file.keys() {
            file.removeObject(forKey: key)
        }
        _ = file.synchronize()
        FileBasedUserDefaults.clearLocalStorage()
    }

    private func options(file: Bool = false, provider: StorageProvider? = nil) -> StatsigOptions {
        StatsigOptions(
            enableCacheByFile: file,
            EXPERIMENTAL_storageType: .legacy,
            initializeOffline: true,
            eventLoggingEnabled: false,
            disableDiagnostics: true,
            storageProvider: provider)
    }

    @discardableResult
    private func makeClient(_ key: String, file: Bool = false, provider: StorageProvider? = nil)
        -> StatsigClient
    {
        let client = StatsigClient(sdkKey: key, options: options(file: file, provider: provider))
        clients.append(client)
        return client
    }

    func testInstanceFileCachePersistsOverridesWithoutWritingUserDefaults() {
        let client = makeClient("client-file-instance", file: true)
        client.overrideGate("file_gate", value: true)
        XCTAssertEqual(client.getAllOverrides().gates["file_gate"], true)

        let key = UserDefaultsKeys.localOverridesKey
        let fileValues = StatsigUserDefaults.fileDefaults.dictionarySafe(forKey: key)
        XCTAssertNotNil(fileValues)
        XCTAssertNil(suite.dictionarySafe(forKey: key))
        XCTAssertTrue(StatsigUserDefaults.fileDefaults.synchronize())
        XCTAssertNotNil(FileBasedUserDefaults().dictionarySafe(forKey: key))

        let reloaded = makeClient("client-file-reloaded", file: true)
        XCTAssertEqual(reloaded.getAllOverrides().gates["file_gate"], true)
    }

    func testPublicInstanceFileOptionWritesOverrideToDisk() {
        let client = StatsigClient(sdkKey: "client-public-file-probe", options: options(file: true))
        clients.append(client)
        client.overrideGate("public_probe_gate", value: true)
        _ = client.getAllOverrides()
        var gates: [String: Bool]?
        for _ in 0..<100 {
            let overrides = FileBasedUserDefaults().dictionarySafe(
                forKey: UserDefaultsKeys.localOverridesKey)
            gates = overrides?[InternalStore.gatesKey] as? [String: Bool]
            if gates?["public_probe_gate"] == true { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(gates?["public_probe_gate"], true)
        XCTAssertNil(suite.dictionarySafe(forKey: UserDefaultsKeys.localOverridesKey))
    }

    func testStaticProviderKeepsCallerStableIDAndCopiesItToProvider() {
        let key = UserDefaultsKeys.stableIDKey
        suite.setValue("old-provider-id", forKey: key)
        let user = StatsigUser(userID: "provider-user")
        let provider = MockStorageProvider()
        let initialized = expectation(description: "static provider initialization")
        Statsig.initialize(
            sdkKey: "client-static-provider", user: user, options: options(provider: provider)
        ) { _ in initialized.fulfill() }
        wait(for: [initialized], timeout: 5)
        XCTAssertEqual(Statsig.getStableID(), "old-provider-id")
        XCTAssertEqual(StatsigUserDefaults.defaults.string(forKey: key), "old-provider-id")
        XCTAssertTrue(StatsigUserDefaults.defaults.synchronize())
        XCTAssertEqual(
            StorageProviderBasedUserDefaults(storageProvider: provider).string(forKey: key),
            "old-provider-id")
    }

    func testStaticFileUpdatePreservesSessionIDAndCallerStableID() {
        let key = UserDefaultsKeys.stableIDKey
        suite.setValue("old-static-id", forKey: key)
        StatsigUserDefaults.fileDefaults.setValue("file-static-id", forKey: key)
        let user = StatsigUser(userID: "static-user")
        let initialized = expectation(description: "static file initialization")
        Statsig.initialize(sdkKey: "client-static-user", user: user, options: options(file: true)) {
            _ in initialized.fulfill()
        }
        wait(for: [initialized], timeout: 5)
        XCTAssertEqual(Statsig.getStableID(), "old-static-id")
        let session = Statsig.getSessionID()
        let updated = expectation(description: "static user update")
        Statsig.updateUserWithResult(user) { _ in updated.fulfill() }
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(Statsig.getSessionID(), session)
    }

    func testFlagFalseClientUsesUserDefaultsAfterStaticFileSelection() {
        let initialized = expectation(description: "static file initialization")
        Statsig.initialize(sdkKey: "client-static-before-default", options: options(file: true)) {
            _ in initialized.fulfill()
        }
        wait(for: [initialized], timeout: 5)
        let client = makeClient("client-default-after-static")
        XCTAssertTrue((client.userDefaults as AnyObject) === UserDefaults.standard)
        client.overrideGate("default_after_file", value: true)
        XCTAssertEqual(client.getAllOverrides().gates["default_after_file"], true)
        XCTAssertNotNil(
            UserDefaults.standard.dictionarySafe(forKey: UserDefaultsKeys.localOverridesKey))
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.localOverridesKey)
    }

    func testConcurrentClientsShareStableIDWithinEachBackend() {
        let provider = MockStorageProvider()
        let lock = NSLock()
        var created: [(StatsigClient, Int)] = []
        DispatchQueue.concurrentPerform(iterations: 48) { index in
            let backend = index % 3
            let client = StatsigClient(
                sdkKey: "client-concurrent-\(index)",
                options: options(file: backend == 0, provider: backend == 2 ? provider : nil))
            client.overrideGate("gate_\(index)", value: true)
            _ = client.checkGate("gate_\(index)")
            lock.withLock { created.append((client, backend)) }
        }
        clients.append(contentsOf: created.map { $0.0 })
        for backend in 0..<3 {
            let group = created.filter { $0.1 == backend }
            XCTAssertEqual(group.count, 16)
            XCTAssertEqual(Set(group.compactMap { $0.0.getStableID() }).count, 1)
        }
        let providerAdapters = created.filter { $0.1 == 2 }.map { $0.0.userDefaults as AnyObject }
        XCTAssertTrue(providerAdapters.allSatisfy { $0 === providerAdapters[0] })
    }

    func testInitializationDiagnosticsFlushWithCacheMarker() {
        let logs = expectation(description: "diagnostics and event flushed")
        let lock = NSLock()
        var matched = false
        stub(condition: isHost(LogEventHost) && isPath("/v1/rgstr")) { request in
            let body = request.statsig_body ?? [:]
            let events = body["events"] as? [[String: Any]] ?? []
            lock.withLock {
                if !matched
                    && events.contains(where: { $0["eventName"] as? String == "marker_event" })
                {
                    matched = true
                    logs.fulfill()
                }
            }
            return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
        }
        let initialized = expectation(description: "instance initialized")
        let client = StatsigClient(
            sdkKey: "client-diagnostics-file",
            options: StatsigOptions(
                enableCacheByFile: true, initializeOffline: true, eventLoggingEnabled: true),
            completionWithResult: { _ in initialized.fulfill() })
        clients.append(client)
        wait(for: [initialized], timeout: 5)
        client.logEvent("marker_event")
        client.logger.flush()
        wait(for: [logs], timeout: 5)
    }

    func testErrorBoundaryUsesClientDeviceEnvironment() {
        let received = expectation(description: "exception metadata received")
        let lock = NSLock()
        var metadata: [String: Any]?
        stub(condition: isPath("/v1/sdk_exception")) { request in
            lock.withLock {
                metadata = request.statsig_body?["statsigMetadata"] as? [String: Any]
            }
            received.fulfill()
            return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
        }
        let client = makeClient("client-error-boundary-file", file: true)
        let deviceEnvironment: [String: String?] = [
            StatsigMetadata.STABLE_ID_KEY: client.getStableID(),
            StatsigMetadata.SESSION_ID_KEY: client.getSessionID(),
        ]
        let boundary = ErrorBoundary.boundary(
            clientKey: "client-error-boundary-file", statsigOptions: options(file: true),
            deviceEnvironment: deviceEnvironment)
        boundary.logException(tag: "cache_file_probe", error: StatsigError.unexpectedError("probe"))
        wait(for: [received], timeout: 5)
        XCTAssertEqual(
            lock.withLock { metadata?[StatsigMetadata.STABLE_ID_KEY] as? String },
            client.getStableID())
        XCTAssertEqual(
            lock.withLock { metadata?[StatsigMetadata.SESSION_ID_KEY] as? String },
            client.getSessionID())
    }

    func testStaticInitializationStillSelectsFileCache() {
        let initialized = expectation(description: "static initialization")
        Statsig.initialize(sdkKey: "client-static-file", options: options(file: true)) { _ in
            initialized.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertTrue(
            (StatsigUserDefaults.defaults as AnyObject) === StatsigUserDefaults.fileDefaults)
    }

    func testConcurrentClientsWithDifferentOptionsRetainSeparateCaches() {
        let fileClient = makeClient("client-file-mixed", file: true)
        let defaultsClient = makeClient("client-defaults-mixed")
        fileClient.overrideGate("file_gate", value: true)
        defaultsClient.overrideGate("defaults_gate", value: true)
        _ = fileClient.getAllOverrides()
        _ = defaultsClient.getAllOverrides()

        let key = UserDefaultsKeys.localOverridesKey
        let fileValues =
            StatsigUserDefaults.fileDefaults.dictionarySafe(forKey: key)?[
                InternalStore.gatesKey] as? [String: Bool]
        let defaultsValues =
            suite.dictionarySafe(forKey: key)?[
                InternalStore.gatesKey] as? [String: Bool]
        XCTAssertEqual(fileValues?["file_gate"], true)
        XCTAssertNil(fileValues?["defaults_gate"])
        XCTAssertEqual(defaultsValues?["defaults_gate"], true)
        XCTAssertNil(defaultsValues?["file_gate"])
    }

    func testTwoFileClientsKeepBothCachedUserPayloads() {
        let selectedOptions = options(file: true)
        let file = StatsigUserDefaults.resolve(selectedOptions).defaults
        let userA = StatsigUser(userID: "a")
        let userB = StatsigUser(userID: "b")
        let keyA = UserCacheKey.from(selectedOptions, userA, "client-file-a")
        let keyB = UserCacheKey.from(selectedOptions, userB, "client-file-b")
        let storeA = InternalStore(
            "client-file-a", userA, options: selectedOptions, userDefaults: file)
        let storeB = InternalStore(
            "client-file-b", userB, options: selectedOptions, userDefaults: file)

        let savedA = expectation(description: "saved A")
        storeA.saveValues(
            ["has_updates": true, "time": 1, "feature_gates": ["a_gate": ["value": true]]],
            keyA, nil, { savedA.fulfill() })
        wait(for: [savedA], timeout: 5)
        let savedB = expectation(description: "saved B")
        storeB.saveValues(
            ["has_updates": true, "time": 2, "feature_gates": ["b_gate": ["value": true]]],
            keyB, nil, { savedB.fulfill() })
        wait(for: [savedB], timeout: 5)
        _ = file.synchronize()

        let persisted =
            file.dictionarySafe(forKey: UserDefaultsKeys.localStorageKey)
            as? [String: [String: Any]]
        XCTAssertNotNil(persisted?[keyA.fullUserWithSDKKey])
        XCTAssertNotNil(persisted?[keyB.fullUserWithSDKKey])
        let reloadedA = InternalStore(
            "client-file-a", userA, options: selectedOptions, userDefaults: file)
        let reloadedB = InternalStore(
            "client-file-b", userB, options: selectedOptions, userDefaults: file)
        XCTAssertNotNil(reloadedA.cache.cacheByID[keyA.fullUserWithSDKKey])
        XCTAssertNotNil(reloadedB.cache.cacheByID[keyB.fullUserWithSDKKey])
    }

    func testStorageProviderAndFilePrecedence() {
        let provider = MockStorageProvider()
        let providerClient = makeClient("client-provider", provider: provider)
        XCTAssertTrue(providerClient.userDefaults is StorageProviderBasedUserDefaults)
        providerClient.overrideGate("provider_gate", value: true)
        _ = providerClient.getAllOverrides()
        _ = providerClient.userDefaults.synchronize()
        XCTAssertNotNil(provider.read("com.statsig.cache"))

        let fileClient = makeClient("client-file-precedence", file: true, provider: provider)
        XCTAssertTrue(fileClient.userDefaults is FileBasedUserDefaults)
        fileClient.overrideGate("file_gate", value: true)
        _ = fileClient.getAllOverrides()
        XCTAssertNotNil(
            StatsigUserDefaults.fileDefaults.dictionarySafe(
                forKey: UserDefaultsKeys.localOverridesKey))
    }

    func testFreshClientRehydratesCustomProviderState() {
        let sdkKey = "client-provider-rehydration"
        let gate = "persisted_provider_gate"
        let originalProvider = MockStorageProvider()
        let selectedOptions = options(provider: originalProvider)
        selectedOptions.initializeOffline = false
        selectedOptions.initializationURL = URL(
            string: "https://cache-provider-test.example/v1/initialize")
        stub(condition: isHost("cache-provider-test.example") && isPath("/v1/initialize")) { _ in
            HTTPStubsResponse(
                jsonObject: [
                    "feature_gates": [gate.sha256(): ["value": true]],
                    "dynamic_configs": [:],
                    "layer_configs": [:],
                    "time": 321,
                    "has_updates": true,
                ], statusCode: 200, headers: nil)
        }

        let initialized = expectation(description: "provider client fetched values")
        var initializationError: StatsigClientError?
        let first = StatsigClient(sdkKey: sdkKey, options: selectedOptions) { error in
            initializationError = error
            initialized.fulfill()
        }
        clients.append(first)
        wait(for: [initialized], timeout: 5)
        XCTAssertNil(initializationError)
        XCTAssertTrue(first.checkGate(gate))
        XCTAssertTrue(first.userDefaults.synchronize())
        XCTAssertNotNil(originalProvider.read("com.statsig.cache"))

        // Use a new provider object so the second client must load persisted bytes,
        // rather than reuse the first client's in-memory adapter.
        let reloadedProvider = MockStorageProvider()
        reloadedProvider.storage = originalProvider.storage
        let reloaded = makeClient(sdkKey, provider: reloadedProvider)
        XCTAssertTrue(reloaded.checkGate(gate))
        XCTAssertNil(suite.dictionarySafe(forKey: UserDefaultsKeys.localStorageKey))
        XCTAssertNil(
            StatsigUserDefaults.fileDefaults.dictionarySafe(
                forKey: UserDefaultsKeys.localStorageKey))
    }

    func testConcurrentConstructionWithDistinctProvidersKeepsStateIsolated() {
        let providers = [MockStorageProvider(), MockStorageProvider()]
        let lock = NSLock()
        var constructed: [StatsigClient?] = [nil, nil]

        DispatchQueue.concurrentPerform(iterations: providers.count) { index in
            let client = StatsigClient(
                sdkKey: "client-distinct-provider-\(index)",
                options: options(provider: providers[index]))
            client.overrideGate("provider_gate_\(index)", value: true)
            _ = client.getAllOverrides()
            _ = client.userDefaults.synchronize()
            lock.withLock { constructed[index] = client }
        }

        clients.append(contentsOf: constructed.compactMap { $0 })
        for index in providers.indices {
            guard let client = constructed[index] else {
                XCTFail("Client \(index) was not constructed")
                continue
            }
            XCTAssertTrue(client.checkGate("provider_gate_\(index)"))
            XCTAssertFalse(client.checkGate("provider_gate_\(1 - index)"))
            let persisted = StorageProviderBasedUserDefaults(storageProvider: providers[index])
            let gates =
                persisted.dictionarySafe(forKey: UserDefaultsKeys.localOverridesKey)?[
                    InternalStore.gatesKey] as? [String: Bool]
            XCTAssertEqual(gates?["provider_gate_\(index)"], true)
            XCTAssertNil(gates?["provider_gate_\(1 - index)"])
        }
        XCTAssertNil(suite.dictionarySafe(forKey: UserDefaultsKeys.localOverridesKey))
    }

    func testColdFileCacheFetchesNetworkValuesAndPersistsThem() {
        let sdkKey = "client-cold-network-file"
        let gate = "network_file_gate"
        let selectedOptions = options(file: true)
        selectedOptions.initializeOffline = false
        selectedOptions.initializationURL = URL(
            string: "https://cache-file-test.example/v1/initialize")
        XCTAssertNil(
            StatsigUserDefaults.fileDefaults.dictionarySafe(
                forKey: UserDefaultsKeys.localStorageKey))

        stub(condition: isHost("cache-file-test.example") && isPath("/v1/initialize")) { _ in
            HTTPStubsResponse(
                jsonObject: [
                    "feature_gates": [gate.sha256(): ["value": true]],
                    "dynamic_configs": [:],
                    "layer_configs": [:],
                    "time": 321,
                    "has_updates": true,
                ], statusCode: 200, headers: nil)
        }

        let initialized = expectation(description: "cold file client fetched values")
        var initializationError: StatsigClientError?
        let client = StatsigClient(sdkKey: sdkKey, options: selectedOptions) { error in
            initializationError = error
            initialized.fulfill()
        }
        clients.append(client)
        wait(for: [initialized], timeout: 5)
        XCTAssertNil(initializationError)
        XCTAssertTrue(client.checkGate(gate))
        XCTAssertTrue(StatsigUserDefaults.fileDefaults.synchronize())
        XCTAssertNotNil(
            FileBasedUserDefaults().dictionarySafe(forKey: UserDefaultsKeys.localStorageKey))
        XCTAssertNil(suite.dictionarySafe(forKey: UserDefaultsKeys.localStorageKey))

        let reloaded = makeClient(sdkKey, file: true)
        XCTAssertTrue(reloaded.checkGate(gate))
    }

    func testSwitchToFileStartsWithColdEvaluationCache() {
        suite.setDictionarySafe(
            ["old-user": ["feature_gates": ["cached_gate": ["value": true]]]],
            forKey: UserDefaultsKeys.localStorageKey)
        let client = makeClient("client-cold-file", file: true)
        XCTAssertNil(client.userDefaults.dictionarySafe(forKey: UserDefaultsKeys.localStorageKey))
        XCTAssertNotNil(suite.dictionarySafe(forKey: UserDefaultsKeys.localStorageKey))
    }

    func testStableIDMovesFromUserDefaultsOnlyWhenFileLacksOne() {
        let key = UserDefaultsKeys.stableIDKey
        suite.setValue("old-stable-id", forKey: key)
        let client = makeClient("client-stable-copy", file: true)
        XCTAssertEqual(client.getStableID(), "old-stable-id")
        XCTAssertEqual(StatsigUserDefaults.fileDefaults.string(forKey: key), "old-stable-id")

        clearFileCache()
        StatsigUserDefaults.fileDefaults.setValue("file-stable-id", forKey: key)
        let suppliedUser = StatsigUser(userID: "supplied-user")
        let fileWins = StatsigClient(
            sdkKey: "client-stable-file-wins", user: suppliedUser, options: options(file: true))
        clients.append(fileWins)
        XCTAssertEqual(fileWins.getStableID(), "file-stable-id")
        XCTAssertEqual(suite.string(forKey: key), "old-stable-id")

        clearFileCache()
        suite.removeObject(forKey: key)
        let generated = makeClient("client-stable-generated", file: true)
        let newID = generated.getStableID()
        XCTAssertNotNil(newID)
        XCTAssertFalse(newID!.isEmpty)
        XCTAssertEqual(StatsigUserDefaults.fileDefaults.string(forKey: key), newID)
        XCTAssertNil(suite.string(forKey: key))
    }
}
