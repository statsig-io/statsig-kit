import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class StatsigOptionsSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("StatsigOptions") {
            it("can be constructed via the constructor") {
                let opts = StatsigOptions(
                    initTimeout: 1.23,
                    disableCurrentVCLogging: true,
                    environment: StatsigEnvironment(tier: "test"),
                    enableAutoValueUpdate: true,
                    overrideStableID: "an-override-id",
                    enableCacheByFile: true,
                    initializeValues: ["foo": 1],
                    disableDiagnostics: true,
                    disableHashing: true
                )

                expect(opts.initTimeout).to(equal(1.23))
                expect(opts.disableCurrentVCLogging).to(beTrue())
                expect(opts.environment).to(equal(["tier": "test"]))
                expect(opts.enableAutoValueUpdate).to(beTrue())
                expect(opts.overrideStableID).to(equal("an-override-id"))
                expect(opts.enableCacheByFile).to(beTrue())
                expect(opts.initializeValues as? [String: Int]).to(equal(["foo": 1]))
                expect(opts.disableDiagnostics).to(beTrue())
                expect(opts.disableHashing).to(beTrue())
            }

            it("can be constructed via assignment") {
                let opts = StatsigOptions()

                opts.initTimeout = 1.23
                opts.disableCurrentVCLogging = true
                opts.environment = ["tier": "test"]
                opts.enableAutoValueUpdate = true
                opts.overrideStableID = "an-override-id"
                opts.enableCacheByFile = true
                opts.initializeValues = ["foo": 1]
                opts.disableDiagnostics = true
                opts.disableHashing = true

                expect(opts.initTimeout).to(equal(1.23))
                expect(opts.disableCurrentVCLogging).to(beTrue())
                expect(opts.environment).to(equal(["tier": "test"]))
                expect(opts.enableAutoValueUpdate).to(beTrue())
                expect(opts.overrideStableID).to(equal("an-override-id"))
                expect(opts.enableCacheByFile).to(beTrue())
                expect(opts.initializeValues as? [String: Int]).to(equal(["foo": 1]))
                expect(opts.disableDiagnostics).to(beTrue())
                expect(opts.disableHashing).to(beTrue())
            }

            describe("getDictionaryForLogging") {

                // This object should set every non-computed option to a non-default value
                let options = StatsigOptions(
                    initTimeout: 11,
                    disableCurrentVCLogging: true,
                    environment: StatsigEnvironment(
                        tier: StatsigEnvironment.EnvironmentTier.Development,
                        additionalParams: [:]
                    ),
                    enableAutoValueUpdate: true,
                    autoValueUpdateIntervalSec: 24 * 3600,
                    overrideStableID: "test-stable-id",
                    enableCacheByFile: true,
                    initializeValues: [:],
                    initializeOffline: true,
                    eventLoggingEnabled: false,
                    disableDiagnostics: true,
                    disableHashing: true,
                    disableCompression: true,
                    shutdownOnBackground: false,
                    initializationURL: URL(string: "http://ErrorBoundarySpec/v1/initialize"),
                    eventLoggingURL: URL(string: "http://ErrorBoundarySpec/v1/rgstr"),
                    evaluationCallback: { (_) in },
                    userValidationCallback: { $0 },
                    customCacheKey: { (_, _) in "cache_key" },
                    storageProvider: MockStorageProvider(),
                    urlSession: URLSession.init(
                        configuration: .background(withIdentifier: "ErrorBoundarySpec")),
                    disableEventNameTrimming: true,
                    overrideAdapter: OnDeviceEvalAdapter(
                        stringPayload:
                            "{\"feature_gates\":[],\"dynamic_configs\":[],\"layer_configs\":[],\"time\":0}"
                    )
                )

                it("doesn't include default options") {
                    let dict = StatsigOptions().getDictionaryForLogging()
                    expect(Set(dict.keys)).to(equal(Set(["environment"])))
                }

                it("sets callback options to the string `set`") {
                    let dict = options.getDictionaryForLogging()
                    expect(dict["evaluationCallback"] as? String).to(equal("set"))
                    expect(dict["userValidationCallback"] as? String).to(equal("set"))
                    expect(dict["customCacheKey"] as? String).to(equal("set"))
                }

                it("sets complex objects to the string `set`") {
                    let dict = options.getDictionaryForLogging()
                    expect(dict["storageProvider"] as? String).to(equal("set"))
                    expect(dict["urlSession"] as? String).to(equal("set"))
                    expect(dict["overrideAdapter"] as? String).to(equal("set"))
                }

                it("creates a dictionary with every option") {
                    let ignoredKeys = [
                        "getDictionaryForLogging",
                        "api",
                        "eventLoggingApi",
                        "printHandler",
                    ]

                    let dict = options.getDictionaryForLogging()

                    let mirror = Mirror(reflecting: options)
                    let mirrorKeys = Set(
                        mirror.children
                            .compactMap { $0.label?.replacingPrefix("_") }
                            .filter { !ignoredKeys.contains($0) })
                    let dictKeys = Set(dict.keys)
                    expect(dictKeys).to(equal(mirrorKeys))
                }
            }
        }
    }
}

extension String {
    fileprivate func replacingPrefix(_ prefix: String) -> String {
        if self.starts(with: prefix) {
            return String(self.dropFirst(prefix.count))
        }
        return self
    }
}
