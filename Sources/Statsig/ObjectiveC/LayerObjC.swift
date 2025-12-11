import Foundation

@objc(Layer)
public final class LayerObjC: NSObject {
    internal var layer: Layer

    @objc public var name: String {
        layer.name
    }

    @objc public var ruleID: String {
        layer.ruleID
    }

    @objc public var groupName: String? {
        layer.groupName
    }

    @objc public var isUserInExperiment: Bool {
        layer.isUserInExperiment
    }

    @objc public var isExperimentActive: Bool {
        layer.isExperimentActive
    }

    @objc public var hashedName: String {
        layer.hashedName
    }

    @objc public var allocatedExperimentName: String {
        layer.allocatedExperimentName
    }

    @objc public var evaluationDetails: [String: String] {
        var internalDetails = [String: Any]()
        layer.evaluationDetails.addToDictionary(&internalDetails)

        var externalDetails = [String: String]()
        for (key, value) in internalDetails {
            externalDetails[key] = "\(value)"
        }

        return externalDetails
    }

    init(_ layer: Layer) {
        self.layer = layer
    }

    @objc public func getArray(forKey: String, defaultValue: [Any]) -> [Any] {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getBool(forKey: String, defaultValue: Bool) -> Bool {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getDictionary(forKey: String, defaultValue: [String: Any]) -> [String: Any] {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getDouble(forKey: String, defaultValue: Double) -> Double {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getInt(forKey: String, defaultValue: Int) -> Int {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getString(forKey: String, defaultValue: String) -> String {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getNullableString(forKey: String, defaultValue: String?) -> String? {
        return layer.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func toData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(layer)
    }

    @objc public static func fromData(_ data: Data) -> LayerObjC? {
        let decoder = JSONDecoder()
        let swiftLayer = try? decoder.decode(Layer.self, from: data)
        guard let swiftLayer = swiftLayer else {
            return nil
        }

        return LayerObjC(swiftLayer)
    }
}
