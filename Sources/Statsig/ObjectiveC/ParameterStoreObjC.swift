import Foundation

@objc(ParameterStore)
public final class ParameterStoreObjC: NSObject {
    internal var parameterStore: ParameterStore

    @objc public var name: String {
        parameterStore.name
    }

    @objc public var evaluationDetails: [String: String] {
        var internalDetails = [String: Any]()
        parameterStore.evaluationDetails.addToDictionary(&internalDetails)

        var externalDetails = [String: String]()
        for (key, value) in internalDetails {
            externalDetails[key] = "\(value)"
        }

        return externalDetails
    }

    init(withParameterStore: ParameterStore) {
        parameterStore = withParameterStore
    }

    @objc public func getArray(forKey key: String, defaultValue: [Any]) -> [Any] {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getBool(forKey key: String, defaultValue: Bool) -> Bool {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getDictionary(forKey key: String, defaultValue: [String: Any]) -> [String:
        Any]
    {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getDouble(forKey key: String, defaultValue: Double) -> Double {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getInt(forKey key: String, defaultValue: Int) -> Int {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getString(forKey key: String, defaultValue: String) -> String {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func getNullableString(forKey key: String, defaultValue: String?) -> String? {
        return parameterStore.getValue(forKey: key, defaultValue: defaultValue)
    }

    @objc public func toData() -> Data? {
        var evaluationDict = [String: Any]()
        parameterStore.evaluationDetails.addToDictionary(&evaluationDict)

        let dict: [String: Any] = [
            "name": parameterStore.name,
            "evaluationDetails": evaluationDict,
        ]

        return try? JSONSerialization.data(withJSONObject: dict)
    }

    @objc public static func fromData(_ data: Data) -> ParameterStoreObjC? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = dict["name"] as? String
        else {
            return nil
        }

        let evaluationDetails = EvaluationDetails(source: .Cache)

        let parameterStore = ParameterStore(name: name, evaluationDetails: evaluationDetails)

        return ParameterStoreObjC(withParameterStore: parameterStore)
    }
}
