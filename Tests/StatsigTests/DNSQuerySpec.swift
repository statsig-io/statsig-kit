import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class DNSQuerySpec: BaseSpec {
    override func spec() {
        super.spec()

        // Domains: ["i=assetsconfigcdn.org", "i=featureassets.org", "d=api.statsigcdn.com", "e=beyondwickedmapping.org", "e=prodregistryv2.org"]
        let sampleDNSResponse = Data([
            0, 0, 129, 128, 0, 1, 0, 1, 0, 0, 0, 0, 13, 102, 101, 97, 116, 117, 114, 101, 97, 115,
            115, 101, 116, 115, 3, 111, 114, 103, 0, 0, 16, 0, 1, 192, 12, 0, 16, 0, 1, 0, 0, 1, 44,
            0, 110, 109, 105, 61, 97, 115, 115, 101, 116, 115, 99, 111, 110, 102, 105, 103, 99, 100,
            110, 46, 111, 114, 103, 44, 105, 61, 102, 101, 97, 116, 117, 114, 101, 97, 115, 115,
            101, 116, 115, 46, 111, 114, 103, 44, 100, 61, 97, 112, 105, 46, 115, 116, 97, 116, 115,
            105, 103, 99, 100, 110, 46, 99, 111, 109, 44, 101, 61, 98, 101, 121, 111, 110, 100, 119,
            105, 99, 107, 101, 100, 109, 97, 112, 112, 105, 110, 103, 46, 111, 114, 103, 44, 101,
            61, 112, 114, 111, 100, 114, 101, 103, 105, 115, 116, 114, 121, 118, 50, 46, 111, 114,
            103,
        ])

        describe("using DNSQuerySpec to interface with DNS") {

            afterEach {
                HTTPStubs.removeAllStubs()
            }

            it("parses DNS response") {
                switch parseDNSResponse(data: sampleDNSResponse) {
                case .failure(let error):
                    throw error
                case .success(let parsed):
                    expect(parsed).to(
                        equal([
                            "i=assetsconfigcdn.org", "i=featureassets.org", "d=api.statsigcdn.com",
                            "e=beyondwickedmapping.org", "e=prodregistryv2.org",
                        ]))
                }
            }
        }
    }
}
