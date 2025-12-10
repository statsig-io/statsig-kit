import Foundation

import XCTest
import Nimble
import OHHTTPStubs
import Quick
@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class ManualFlushSpec: BaseSpec {
    override func spec() {
        super.spec()

    
        it("flushes the logger") {
            let opts = StatsigOptions()
            NetworkService.defaultEventLoggingURL = URL(string: "http://ManualFlushSpec/v1/rgstr")

            _ = TestUtils.startWithResponseAndWait([:], options: opts)
            Statsig.logEvent("my_event")

            var logs: [[String: Any]] = []
            TestUtils.captureLogs(host: "ManualFlushSpec") { captured in
                logs = captured["events"] as! [[String: Any]]
            }

            waitUntil { done in Statsig.flush(completion: done) }
            expect(logs).to(haveCount(1))
            expect(logs[0]["eventName"]as? String).to(equal("my_event"))

            Statsig.shutdown()
            TestUtils.resetDefaultURLs()
        }
    }
}
