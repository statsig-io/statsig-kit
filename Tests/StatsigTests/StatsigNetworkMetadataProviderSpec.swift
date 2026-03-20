import Nimble
import Quick

@testable import Statsig

class StatsigNetworkMetadataProviderSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("StatsigEnabledNetworkMetadataProvider") {
            describe("makeNetworkType") {
                it("returns other when the path uses the other interface type") {
                    let netType = StatsigEnabledNetworkMetadataProvider.makeNetworkType(
                        hasInternet: true,
                        usesWifi: false,
                        usesCellular: false,
                        usesWiredEthernet: false,
                        usesOther: true)

                    expect(netType).to(equal("other"))
                }

                it("returns none when there is no internet even if another transport is reported") {
                    let netType = StatsigEnabledNetworkMetadataProvider.makeNetworkType(
                        hasInternet: false,
                        usesWifi: false,
                        usesCellular: false,
                        usesWiredEthernet: false,
                        usesOther: true)

                    expect(netType).to(equal("none"))
                }
            }
        }
    }
}
