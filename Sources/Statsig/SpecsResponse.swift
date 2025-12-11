import Foundation

struct SpecsResponse: Decodable {
    let featureGates: [Spec]
    let dynamicConfigs: [Spec]
    let layerConfigs: [Spec]
    let paramStores: [String: ParamStoreSpec]?
    let time: UInt64

    private enum CodingKeys: String, CodingKey {
        case featureGates = "feature_gates"
        case dynamicConfigs = "dynamic_configs"
        case layerConfigs = "layer_configs"
        case paramStores = "param_stores"
        case time
    }
}

struct ParamStoreSpec: Decodable {
    let targetAppIDs: [String]?
    let parameters: JsonValue
}

typealias SpecMap = [SpecType: [String: Spec]]

enum SpecType {
    case gate
    case config
    case layer
}

struct Spec: Decodable {
    let name: String
    let type: String
    let salt: String
    let defaultValue: JsonValue
    let enabled: Bool
    let idType: String
    let explicitParameters: [String]?
    let rules: [SpecRule]
    let isActive: Bool?
    let version: Int32?
}

struct SpecRule: Decodable {
    let name: String
    let passPercentage: Double
    let conditions: [SpecCondition]
    let returnValue: JsonValue
    let id: String
    let salt: String
    let idType: String
    let configDelegate: String?
    let isExperimentGroup: Bool?
    let groupName: String?
}

struct SpecCondition: Decodable {
    let type: String
    let targetValue: JsonValue?
    let `operator`: String?
    let field: String?
    let additionalValues: [String: JsonValue]?
    let idType: String
}

func parseSpecs(data: Data) -> Result<SpecsResponse, Error> {
    do {
        let decoded = try JSONDecoder()
            .decode(SpecsResponse.self, from: data)
        return .success(decoded)
    } catch {
        return .failure(error)
    }
}

func parseSpecs(string: String) -> Result<SpecsResponse, Error> {
    let data = Data(string.utf8)
    return parseSpecs(data: data)
}
