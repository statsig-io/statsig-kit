import XCTest

@testable import Statsig

class EvaluationDetailSpec: XCTestCase {
    func testEvaluationDetailsConversion() {
        let evalDetails = EvaluationDetails(
            source: EvaluationSource.Network, reason: EvaluationReason.Recognized, lcut: 123456)
        let dynamicConfig = DynamicConfig(
            name: "testConfig", configObj: [:], evalDetails: evalDetails)
        var evaluationDetails: [String: Any] = [
            "intKey": 42,
            "boolKey": true,
            "floatKey": 3.14,
            "arrayKey": [1, 2, 3],
            "nilKey": NSNull(),
            "dictKey": ["subKey": "subValue"],
        ]

        dynamicConfig.evaluationDetails.addToDictionary(&evaluationDetails)
        let dynamicConfigObjC = DynamicConfigObjC(withConfig: dynamicConfig)

        let details = dynamicConfigObjC.evaluationDetails
        XCTAssertEqual(details["reason"], "Network:Recognized")
        XCTAssertEqual(details["lcut"], "123456")
    }
}
