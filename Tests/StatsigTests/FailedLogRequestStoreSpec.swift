import Foundation
import Nimble
import Quick

@testable import Statsig

class FailedLogRequestStoreSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("FailedLogRequestStore") {
            let sdkKey = "client-key"

            var provider: MockStorageProvider!
            var storageAdapter: StorageAdapter!
            var defaults: MockDefaults!
            var originalDefaults: DefaultsLike!

            func makeStore(
                maxStoreSizeBytes: Int = FailedLogRequestStore.defaultMaxStoreSizeBytes
            ) -> FailedLogRequestStore {
                FailedLogRequestStore.forSDKKey(
                    sdkKey,
                    storageAdapter: storageAdapter,
                    maxStoreSizeBytes: maxStoreSizeBytes
                )
            }

            func makeData(size: Int, marker: UInt8) -> Data {
                var bytes = Data(repeating: marker, count: max(size, 1))
                bytes[0] = marker
                return bytes
            }

            func makeUserDefaultsRequestBody(payloadEventCount: Int) -> Data {
                let payload = [
                    "events": (0..<payloadEventCount).map { index in
                        ["eventName": "event_\(index)"]
                    }
                ]
                return try! JSONSerialization.data(withJSONObject: payload, options: [])
            }

            beforeEach {
                provider = MockStorageProvider()
                storageAdapter = StorageProviderToAdapter(storageProvider: provider)
                defaults = MockDefaults()
                originalDefaults = StatsigUserDefaults.defaults
                StatsigUserDefaults.defaults = defaults
                FailedLogRequestStore.clearCachedInstances()
                FailedLogRequestStore.deleteLocalStorage(
                    sdkKey: sdkKey,
                    storageAdapter: storageAdapter
                )
            }

            afterEach {
                FailedLogRequestStore.clearCachedInstances()
                provider.storage = [:]
                StatsigUserDefaults.defaults = originalDefaults
            }

            it("persists requests to the storage adapter") {
                let store = makeStore()

                store.addRequests(
                    [
                        FailedLogRequest(
                            body: Data([1, 2, 3]),
                            lastFailedAtMs: 123,
                            requestEventCount: 2
                        )
                    ]
                )

                let persistedStore = decodeFailedLogRequestStore(
                    storageAdapter: storageAdapter,
                    sdkKey: sdkKey
                )

                expect(persistedStore?.requests.count).to(equal(1))
                expect(persistedStore?.requests.first?.requestEventCount).to(equal(2))
            }

            it("migrates user defaults requests into the store and clears the old key") {
                let persistedRequest = FailedLogRequest(
                    body: makeData(size: 10, marker: 7),
                    lastFailedAtMs: 456,
                    requestEventCount: 5
                )
                storageAdapter.write(
                    FailedLogRequestStoreData(
                        requests: [persistedRequest],
                        pendingDroppedRequestSummary: nil
                    ).encode()!,
                    FailedLogRequestStore.storagePath(sdkKey: sdkKey),
                    options: .createFolderIfNeeded
                )

                let firstUserDefaultsRequest = makeUserDefaultsRequestBody(payloadEventCount: 2)
                let secondUserDefaultsRequest = makeUserDefaultsRequestBody(payloadEventCount: 1)
                defaults.set(
                    [firstUserDefaultsRequest, secondUserDefaultsRequest],
                    forKey: UserDefaultsKeys.getFailedEventsStorageKey(sdkKey)
                )

                let store = makeStore()

                expect(store.requests.map(\.body)).to(
                    equal([
                        firstUserDefaultsRequest,
                        secondUserDefaultsRequest,
                        persistedRequest.body,
                    ])
                )
                expect(store.requests.map(\.requestEventCount)).to(equal([0, 0, 5]))
                expect(store.requests[0].lastFailedAtMs).to(beGreaterThan(0))
                expect(store.requests[1].lastFailedAtMs).to(beGreaterThan(0))
                expect(defaults.array(forKey: UserDefaultsKeys.getFailedEventsStorageKey(sdkKey)))
                    .to(beNil())
                expect(
                    decodeFailedLogRequestStore(
                        storageAdapter: storageAdapter,
                        sdkKey: sdkKey
                    )?.requests.map(\.body)
                ).to(
                    equal([
                        firstUserDefaultsRequest,
                        secondUserDefaultsRequest,
                        persistedRequest.body,
                    ]))
            }

            it("loads user defaults requests once, then continues from the failed request store") {
                let userDefaultsRequest = makeUserDefaultsRequestBody(payloadEventCount: 2)
                defaults.set(
                    [userDefaultsRequest],
                    forKey: UserDefaultsKeys.getFailedEventsStorageKey(sdkKey)
                )

                let firstStore = makeStore()
                let migratedRequest = firstStore.requests.first

                expect(firstStore.requests.map(\.body)).to(equal([userDefaultsRequest]))
                expect(defaults.array(forKey: UserDefaultsKeys.getFailedEventsStorageKey(sdkKey)))
                    .to(beNil())

                FailedLogRequestStore.clearCachedInstances()

                let secondStore = makeStore()

                expect(secondStore.requests.map(\.body)).to(equal([userDefaultsRequest]))
                expect(secondStore.requests.first?.lastFailedAtMs).to(
                    equal(migratedRequest?.lastFailedAtMs))
            }

            describe("addRequests") {
                var store: FailedLogRequestStore!
                let limit = 1000

                beforeEach {
                    store = makeStore(maxStoreSizeBytes: limit)
                }

                it("accepts requests under the limit") {
                    let data = makeData(size: 100, marker: 1)
                    store.addRequests(
                        FailedLogRequest.makeRequests(
                            from: [data, data, data],
                            lastFailedAtMs: 0,
                            requestEventCount: 0
                        )
                    )

                    expect(store.requests.count).to(equal(3))
                    expect(store.pendingDroppedRequestSummary).to(beNil())
                }

                it("addOrUpdateRequest updates an existing request instead of duplicating it") {
                    let data = makeData(size: 100, marker: 1)
                    store.addRequest(
                        data,
                        lastFailedAtMs: 123,
                        requestEventCount: 4
                    )

                    store.addOrUpdateRequest(
                        data,
                        lastFailedAtMs: 456,
                        requestEventCount: 9
                    )

                    expect(store.requests.count).to(equal(1))
                    expect(store.requests.first?.lastFailedAtMs).to(equal(456))
                    expect(store.requests.first?.requestEventCount).to(equal(4))
                }

                it("takeRequest dequeues the matching request") {
                    let first = makeData(size: 100, marker: 1)
                    let second = makeData(size: 100, marker: 2)
                    store.addRequests(
                        FailedLogRequest.makeRequests(
                            from: [first, second],
                            lastFailedAtMs: 123,
                            requestEventCount: 4
                        )
                    )

                    let takenRequest = store.takeRequest(first)

                    expect(takenRequest?.body).to(equal(first))
                    expect(store.requests.map(\.body)).to(equal([second]))
                }

                it("clears first queue items until the store fits the limit") {
                    let small1 = makeData(size: 100, marker: 1)
                    let small2 = makeData(size: 100, marker: 2)
                    let small3 = makeData(size: 100, marker: 3)
                    let small4 = makeData(size: 100, marker: 4)
                    let small5 = makeData(size: 100, marker: 5)
                    let small6 = makeData(size: 100, marker: 6)
                    let medium1 = makeData(size: limit / 2 + 100, marker: 7)
                    let medium2 = makeData(size: limit / 2 + 100, marker: 8)

                    store.addRequests(
                        FailedLogRequest.makeRequests(
                            from: [small1, small2, small3],
                            lastFailedAtMs: 0,
                            requestEventCount: 0
                        )
                    )
                    store.addRequests(
                        FailedLogRequest.makeRequests(
                            from: [medium1],
                            lastFailedAtMs: 0,
                            requestEventCount: 0
                        )
                    )
                    store.addRequests(
                        FailedLogRequest.makeRequests(
                            from: [small4, small5, small6, medium2],
                            lastFailedAtMs: 0,
                            requestEventCount: 0
                        )
                    )

                    expect(store.requests.map(\.body)).to(
                        equal([small4, small5, small6, medium2])
                    )
                }

                it("persists dropped request summaries to disk") {
                    store.addRequests(
                        [
                            FailedLogRequest(
                                body: makeData(size: limit + 100, marker: 9),
                                lastFailedAtMs: 123,
                                requestEventCount: 7
                            )
                        ]
                    )

                    let persistedStore = decodeFailedLogRequestStore(
                        storageAdapter: storageAdapter,
                        sdkKey: sdkKey
                    )

                    expect(persistedStore?.requests).to(beEmpty())
                    expect(persistedStore?.pendingDroppedRequestSummary?.eventCount).to(
                        equal(7))
                    expect(persistedStore?.pendingDroppedRequestSummary?.lastFailedAtMs).to(
                        equal(123))
                }

                it("tracks the latest lastFailedAtMs across multiple dropped requests") {
                    store.addRequests(
                        [
                            FailedLogRequest(
                                body: makeData(size: limit + 100, marker: 10),
                                lastFailedAtMs: 123,
                                requestEventCount: 7
                            )
                        ]
                    )
                    store.addRequests(
                        [
                            FailedLogRequest(
                                body: makeData(size: limit + 100, marker: 11),
                                lastFailedAtMs: 456,
                                requestEventCount: 9
                            )
                        ]
                    )

                    expect(store.pendingDroppedRequestSummary?.eventCount).to(equal(16))
                    expect(store.pendingDroppedRequestSummary?.lastFailedAtMs).to(equal(456))
                }

                it("takes a dropped request summary event from the pending summary") {
                    store.addRequests(
                        [
                            FailedLogRequest(
                                body: makeData(size: limit + 100, marker: 10),
                                lastFailedAtMs: 123,
                                requestEventCount: 7
                            )
                        ]
                    )

                    let droppedSummary = store.takePendingDroppedRequestSummary()
                    let droppedEvent = droppedSummary?.makeEvent()

                    expect(droppedEvent?.name).to(equal("dropped_log_event.count"))
                    expect(droppedEvent?.value as? Double).to(equal(7))
                    expect(droppedEvent?.metadata).to(beNil())
                    expect(droppedEvent?.time).to(equal(123))
                    expect(store.pendingDroppedRequestSummary).to(beNil())
                }

                it("accumulates dropped eventCount when trimming part of the queue") {
                    store.addRequests(
                        [
                            FailedLogRequest(
                                body: makeData(size: 100, marker: 1),
                                lastFailedAtMs: 123,
                                requestEventCount: 7
                            ),
                            FailedLogRequest(
                                body: makeData(size: limit / 2, marker: 2),
                                lastFailedAtMs: 234,
                                requestEventCount: 11
                            ),
                            FailedLogRequest(
                                body: makeData(size: limit / 2 + 100, marker: 3),
                                lastFailedAtMs: 345,
                                requestEventCount: 13
                            ),
                        ]
                    )

                    expect(store.requests.map(\.requestEventCount)).to(equal([13]))
                    expect(store.pendingDroppedRequestSummary?.eventCount).to(equal(18))
                    expect(store.pendingDroppedRequestSummary?.lastFailedAtMs).to(equal(234))
                }
            }
        }
    }
}
