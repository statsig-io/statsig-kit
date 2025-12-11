import Foundation
import Nimble
import Quick

@testable import Statsig

class InternalStoreFileBasedUserDefaultsSpec: InternalStoreSpec {
    override func shouldResetUserDefaultsBeforeSuite() -> Bool {
        return false
    }

    override func spec() {
        super.spec()

        beforeSuite {
            StatsigUserDefaults.defaults = FileBasedUserDefaults()
        }

        self.specImpl()
    }
}
