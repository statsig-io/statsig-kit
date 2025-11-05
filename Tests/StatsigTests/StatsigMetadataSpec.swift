import Foundation

import Nimble
import Quick
@testable import Statsig

class StatsigMetadataSpec: BaseSpec {
    override func spec() {
        super.spec()
        
        describe("constructing from deviceEnvironment.get()") {
            let envData = DeviceEnvironment.get()
            let metadata = StatsigMetadata.buildMetadataFromEnvironmentDict(deviceEnvironment: envData)
            it("has all expected fields") {
                expect(metadata.sdkVersion).to(equal(DeviceEnvironment.sdkVersion))
                expect(metadata.sdkType).to(equal(DeviceEnvironment.sdkType))
                expect(metadata.deviceOS).to(equal(DeviceEnvironment.deviceOS))
                expect(metadata.deviceModel).to(equal(envData[StatsigMetadata.DEVICE_MODEL_KEY]))
                expect(metadata.language).to(equal(envData[StatsigMetadata.LANGUAGE_KEY]))
                expect(metadata.locale).to(equal(envData[StatsigMetadata.LOCALE_KEY]))
                expect(metadata.systemName).to(equal(envData[StatsigMetadata.SYS_NAME_KEY]))
                expect(metadata.systemVersion).to(equal(envData[StatsigMetadata.SYS_VERSION_KEY]))
                expect(metadata.stableID).to(equal(envData[StatsigMetadata.STABLE_ID_KEY]))
                expect(metadata.sessionID).to(equal(envData[StatsigMetadata.SESSION_ID_KEY]))
            }
        }
    }
}

