import Foundation
import Nimble
import Quick

@testable import Statsig

class InternalStoreAppleUserDefaultsSpec: InternalStoreSpec {
    override func spec() {
        super.spec()

        beforeSuite {
            StatsigUserDefaults.defaults = UserDefaults.standard
        }

        self.specImpl()
    }
}
