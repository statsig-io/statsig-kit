import Foundation

import Nimble
import OHHTTPStubs
import Quick

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

@testable import Statsig

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

class StorageProviderBasedUserDefaultsSpec: BaseSpec {
    
    override func spec() {
        super.spec()

        describe("StorageProviderBasedUserDefaults") {
            describe("strings") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    
                    defaults.set("Foo", forKey: "Bar")
                    
                    expect(defaults.string(forKey: "Bar")).to(equal("Foo")) // test in-memo dict
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData())) // test storage provider
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")

                    let defaults2 = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    expect(defaults2.string(forKey: "Bar")).to(equal("Foo"))
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }
            }

            describe("dictionaries") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set(["A": "B"], forKey: "Bar")
                    expect(defaults.dictionary(forKey: "Bar") as? [String: String]).to(equal(["A": "B"]))
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set(["A": "B"], forKey: "Bar")

                    let defaults2 = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    let result = defaults2.dictionary(forKey: "Bar") as? [String: String]
                    expect(result).to(equal(["A": "B"]))
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }
            }

            describe("arrays") {
                it("writes and reads") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set(["Foo"], forKey: "Bar")
                    expect(defaults.array(forKey: "Bar") as? [String]).to(equal(["Foo"]))
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }

                it("writes and reads across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set(["Foo"], forKey: "Bar")

                    let defaults2 = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    expect(defaults2.array(forKey: "Bar") as? [String]).to(equal(["Foo"]))
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }
            }

            describe("removing values") {
                it("removes values") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")
                    expect(defaults.string(forKey: "Bar")).to(beNil())
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }

                it("removes values across sessions") {
                    let mockStorageProvider = MockStorageProvider()
                    let defaults = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")

                    let defaults2 = StorageProviderBasedUserDefaults(storageProvider: mockStorageProvider)
                    expect(defaults2.string(forKey: "Bar")).to(beNil())
                    expect(mockStorageProvider.read("com.statsig.cache")).to(equal(defaults.dict.toData()))
                }
            }
        }
    }
}
