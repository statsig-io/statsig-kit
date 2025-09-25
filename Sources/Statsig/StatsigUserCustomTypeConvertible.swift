import Foundation

public protocol StatsigUserCustomTypeConvertible: Sendable {}

extension Bool: StatsigUserCustomTypeConvertible {}

extension Double: StatsigUserCustomTypeConvertible {}

extension String: StatsigUserCustomTypeConvertible {}

extension Array: StatsigUserCustomTypeConvertible where Element == String {}

func convertToUserCustomType(_ value: Any) -> StatsigUserCustomTypeConvertible? {
    if let array = value as? [String] {
        return array
    }
    // Need to cast to Bool BEFORE trying to cast to Double, otherwise Bool from objective-c will be casted to Double as 1/0
    if let boolean = value as? Bool {
        return boolean
    }
    if let double = value as? Double {
        return double
    }
    if let string = value as? String {
        return string
    }
    return nil
}
