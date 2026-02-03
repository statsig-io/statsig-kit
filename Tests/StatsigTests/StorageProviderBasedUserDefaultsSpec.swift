import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class MockStorageProvider: StorageProvider {
    var storage: [String: Data] = [:]

    func write(_ value: Data, _ key: String) {
        storage[key] = value
    }

    func read(_ key: String) -> Data? {
        return storage[key]
    }

    func remove(_ key: String) {
        storage[key] = nil
    }
}

class MockLockedStorageProvider: StorageProvider {
    var storage: [String: Data] = [:]
    public let writeLock = NSLock()
    var doneWriting = false

    func write(_ value: Data, _ key: String) {
        writeLock.withLock {
            storage[key] = value
            doneWriting = true
        }
    }

    func read(_ key: String) -> Data? {
        return storage[key]
    }

    func remove(_ key: String) {
        storage[key] = nil
    }
}

class StorageProviderBasedUserDefaultsSpec: BaseSpec {

    override func spec() {
        super.spec()

        describe("StorageProviderBasedUserDefaults") {
            describe("strings") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)

                    defaults.set("Foo", forKey: "Bar")

                    expect(defaults.string(forKey: "Bar")).to(equal("Foo"))  // test in-memo dict

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))  // test storage provider
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")

                    expect(
                        StorageProviderBasedUserDefaults(
                            storageProvider: mockStorageProvider
                        ).string(forKey: "Bar")
                    ).toEventually(equal("Foo"))

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }
            }

            describe("dictionaries") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set(["A": "B"], forKey: "Bar")
                    expect(defaults.dictionary(forKey: "Bar") as? [String: String]).to(
                        equal(["A": "B"]))

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set(["A": "B"], forKey: "Bar")

                    expect(
                        StorageProviderBasedUserDefaults(
                            storageProvider: mockStorageProvider
                        ).dictionary(forKey: "Bar") as? [String: String]
                    ).toEventually(equal(["A": "B"]))

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }
            }

            describe("arrays") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set(["Foo"], forKey: "Bar")
                    expect(defaults.array(forKey: "Bar") as? [String]).to(equal(["Foo"]))

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set(["Foo"], forKey: "Bar")

                    expect(
                        StorageProviderBasedUserDefaults(
                            storageProvider: mockStorageProvider
                        ).array(forKey: "Bar") as? [String]
                    ).toEventually(equal(["Foo"]))

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }
            }

            describe("removing values") {
                it("removes values") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")
                    expect(defaults.string(forKey: "Bar")).to(beNil())

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }

                it("removes values across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")

                    expect(
                        StorageProviderBasedUserDefaults(
                            storageProvider: mockStorageProvider
                        ).string(forKey: "Bar")
                    ).toEventually(beNil())

                    expect(mockStorageProvider.read("com.statsig.cache")).toEventually(
                        equal(defaults.dict.toData()))
                }
            }

            describe("async write") {
                it("can set and read back even though the provider didn't finish writing") {
                    let mockLockedStorageProvider = MockLockedStorageProvider()
                    mockLockedStorageProvider.writeLock.lock()
                    let defaults = StorageProviderBasedUserDefaults(
                        storageProvider: mockLockedStorageProvider)

                    defaults.set("foo", forKey: "key")

                    expect(mockLockedStorageProvider.doneWriting).to(beFalse())

                    let value = defaults.string(forKey: "key")

                    expect(value).to(equal("foo"))

                    mockLockedStorageProvider.writeLock.unlock()

                    expect(mockLockedStorageProvider.doneWriting).toEventually(beTrue())
                }
            }
        }
    }
}
