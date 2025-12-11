import Foundation

public protocol StatsigDynamicConfigValue {}

extension Array: StatsigDynamicConfigValue {}

extension Array where Element: StatsigDynamicConfigValue {}

extension Bool: StatsigDynamicConfigValue {}

extension Dictionary: StatsigDynamicConfigValue {}

extension Double: StatsigDynamicConfigValue {}

extension Int: StatsigDynamicConfigValue {}

extension String: StatsigDynamicConfigValue {}

extension String?: StatsigDynamicConfigValue {}

fileprivate struct TypeString {
    static let boolean = "boolean"
    static let number = "number"
    static let string = "string"
    static let array = "array"
    static let object = "object"
}

func getTypeOf<T: StatsigDynamicConfigValue>(_ value: T) -> String? {
    switch value {
    case is Bool:
        return TypeString.boolean
    case is Int, is Double:
        return TypeString.number
    case is String, is String?:
        return TypeString.string
    case is [StatsigDynamicConfigValue]:
        return TypeString.array
    case is [String: StatsigDynamicConfigValue]:
        return TypeString.object
    default:
        return nil
    }
}

func getTypeOfValue(_ value: Any) -> String? {
    switch value {
    case is Bool:
        return TypeString.boolean
    case is Int, is Double:
        return TypeString.number
    case is String, is String?:
        return TypeString.string
    case is [StatsigDynamicConfigValue]:
        return TypeString.array
    case is [String: StatsigDynamicConfigValue]:
        return TypeString.object
    default:
        return nil
    }
}

func getTypeOf<T: StatsigDynamicConfigValue>(type: T.Type = T.self) -> String? {

    if type == Bool.self {
        return TypeString.boolean
    } else if type == Int.self || type == Double.self {
        return TypeString.number
    } else if type == String.self || type == Optional<String>.self {
        return TypeString.string
    } else if let arr = [] as? T, arr is [StatsigDynamicConfigValue] {
        return TypeString.array
    } else if let dict = [:] as? T, dict is [String: StatsigDynamicConfigValue] {
        return TypeString.object
    }
    return nil
}
