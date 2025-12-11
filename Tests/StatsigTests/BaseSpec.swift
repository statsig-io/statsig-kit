import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class BaseSpec: QuickSpec {

    override func spec() {
        beforeSuite {
            NetworkService.disableCompression = true

            if self.shouldResetUserDefaultsBeforeSuite() {
                BaseSpec.resetUserDefaults()
            }

            let stubs = HTTPStubs.allStubs()
            if !stubs.isEmpty {
                fatalError(
                    "Stubs not cleared. This likely means a previous test was not cleaned up (Possibly because it failed)"
                )
            }

            if Statsig.client != nil {
                fatalError("Statsig.client not cleared")
            }

            waitUntil { done in
                while Statsig.client != nil {}
                done()
            }
        }

        afterSuite {
            Statsig.client?.shutdown()
            Statsig.client = nil

            BaseSpec.resetUserDefaults()
            HTTPStubs.removeAllStubs()
            TestUtils.resetDefaultURLs()
        }
    }

    static func resetUserDefaults() {
        let random = Int.random(in: 1..<100)
        let name = "Test User Defaults \(random)"
        let userDefaults = UserDefaults(suiteName: name)!
        userDefaults.removePersistentDomain(forName: name)
        StatsigUserDefaults.defaults = userDefaults

        BaseSpec.verifyStorage()
    }

    func shouldResetUserDefaultsBeforeSuite() -> Bool {
        return true
    }

    private static func verifyStorage() {
        let keys = StatsigUserDefaults.defaults.keys()
        for key in keys {
            if key.starts(with: "com.Statsig") {
                fatalError("User Defaults not cleared")
            }
        }
    }

}
