import Foundation
import Nimble
import Quick

@testable import Statsig

class DeviceEnvironmentSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("getting the environment info about current device") {
            StatsigUserDefaults.defaults.removeObject(
                forKey: "com.Statsig.InternalStore.stableIDKey")
            let env1 = DeviceEnvironment.get()
            let env2 = DeviceEnvironment.get()
            let env3 = DeviceEnvironment.get("12345")
            let env4 = DeviceEnvironment.get()

            it("gets the same value across multiple times") {
                for (key, value) in env1 {
                    if key == StatsigMetadata.SESSION_ID_KEY {
                        expect(value) != env2[key]
                    } else {
                        expect(value) == env2[key]
                    }
                }
                expect(env1.count) == env2.count
            }

            it("has all the fields and non-nil values for required ones") {
                expect(env1.count) == 12
                expect(env1[StatsigMetadata.SESSION_ID_KEY]).toNot(beNil())
                expect(env1[StatsigMetadata.STABLE_ID_KEY]).toNot(beNil())
                expect(env1[StatsigMetadata.DEVICE_OS_KEY]).toNot(beNil())
                expect(env1[StatsigMetadata.SDK_VERSION_KEY]).toNot(beNil())
                expect(env1[StatsigMetadata.SDK_TYPE_KEY]).toNot(beNil())
            }

            it("has the same stable ID if no override, otherwise override is used") {
                expect(env1[StatsigMetadata.STABLE_ID_KEY])
                    .to(equal(env2[StatsigMetadata.STABLE_ID_KEY]))
                expect(env1[StatsigMetadata.STABLE_ID_KEY])
                    .toNot(equal(env3[StatsigMetadata.STABLE_ID_KEY]))
                expect(env3[StatsigMetadata.STABLE_ID_KEY]).to(equal("12345"))
                expect(env3[StatsigMetadata.STABLE_ID_KEY])
                    .to(equal(env4[StatsigMetadata.STABLE_ID_KEY]))
            }
        }
    }
}
