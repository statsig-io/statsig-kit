import Foundation
import Gzip
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class GzipSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("GzipSpec") {
            it("compresses a sample event payload") {

                let payload = #"{"events": [],"user": {"userID": "jkw"},"statsigMetadata": {}}"#

                guard let data = payload.data(using: .utf8) else {
                    fail("Failed to create data from string")
                    return
                }

                // Use internal gzip compression
                let compressedInternal = try gzipped(data).get()

                // Use library gunzip decompression
                let decompressed = try compressedInternal.gunzipped()

                let decompressedString = String(data: decompressed, encoding: .utf8)

                expect(decompressedString).toNot(beNil())
                expect(decompressedString).to(equal(payload))
            }

            it("compresses multiple chunks") {

                let largeData = Data.random(length: 1024 * 1024)  // ~20 chunks

                // Use internal gzip compression
                let compressedInternal = try gzipped(largeData).get()

                // Use library gunzip decompression
                let decompressed = try compressedInternal.gunzipped()

                expect(decompressed).to(equal(largeData))
            }

            it("compresses empty data") {

                let empty = Data()  // ~20 chunks

                // Use internal gzip compression
                let compressedInternal = try gzipped(empty).get()

                expect(compressedInternal.count).to(equal(0))

                // Use library gunzip decompression
                let decompressed = try compressedInternal.gunzipped()

                expect(decompressed).to(equal(empty))
            }
        }
    }
}

extension Data {
    /// Returns random data
    ///
    /// - Parameter length: Length of the data in bytes.
    /// - Returns: Generated data of the specified length.
    fileprivate static func random(length: Int) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }
}
