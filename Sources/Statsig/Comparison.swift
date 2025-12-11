import Foundation

enum Comparison {
    static func numbers(
        _ left: JsonValue?,
        _ right: JsonValue?,
        _ op: String?
    ) -> Bool {
        guard let left = left?.asDouble(),
            let right = right?.asDouble()
        else {
            return false
        }

        switch op {
        case "gt":
            return left > right
        case "gte":
            return left >= right
        case "lt":
            return left < right
        case "lte":
            return left <= right
        default:
            return false
        }
    }

    static func versions(
        _ left: JsonValue?,
        _ right: JsonValue?,
        _ op: String?
    ) -> Bool {
        guard var leftStr = left?.asString(),
            var rightStr = right?.asString()
        else {
            return false
        }

        if let index = leftStr.firstIndex(of: "-") {
            leftStr = String(leftStr[..<index])
        }

        if let index = rightStr.firstIndex(of: "-") {
            rightStr = String(rightStr[..<index])
        }

        func comparison(leftStr: String, rightStr: String) -> Int {
            let leftParts = leftStr.split(separator: ".").map { String($0) }
            let rightParts = rightStr.split(separator: ".").map { String($0) }

            var i = 0
            while i < max(leftParts.count, rightParts.count) {
                var leftCount = 0
                var rightCount = 0

                if i < leftParts.count, let leftCountParsed = Int(leftParts[i]) {
                    leftCount = leftCountParsed
                }

                if i < rightParts.count, let rightCountParsed = Int(rightParts[i]) {
                    rightCount = rightCountParsed
                }

                if leftCount < rightCount {
                    return -1
                }

                if leftCount > rightCount {
                    return 1
                }

                i += 1
            }
            return 0

        }

        let result = comparison(leftStr: leftStr, rightStr: rightStr)
        switch op {
        case "version_gt": return result > 0
        case "version_gte": return result >= 0
        case "version_lt": return result < 0
        case "version_lte": return result <= 0
        case "version_eq": return result == 0
        case "version_neq": return result != 0
        default: return false
        }
    }

    static func stringInArray(
        _ value: JsonValue?,
        _ array: JsonValue?,
        _ op: String?,
        ignoreCase: Bool
    ) -> Bool {
        let result =
            array?.asJsonArray()?.contains(where: { current in
                guard let value = value?.asString() else {
                    return false
                }

                guard let current = current.asString() else {
                    return false
                }

                let left = ignoreCase ? value.lowercased() : value
                let right = ignoreCase ? current.lowercased() : current

                switch op {
                case "any", "none", "any_case_sensitive", "none_case_sensitive":
                    return left == right
                case "str_starts_with_any":
                    return left.hasPrefix(right)
                case "str_ends_with_any":
                    return left.hasSuffix(right)
                case "str_contains_any", "str_contains_none":
                    return left.contains(right)

                default:
                    return false
                }
            }) ?? false

        switch op {
        case "none", "none_case_sensitive", "str_contains_none":
            return !result
        default: return result
        }
    }

    static func stringWithRegex(
        _ value: JsonValue?,
        _ target: JsonValue?
    ) -> Bool {
        guard let value = value?.asString(),
            let target = target?.asString()
        else {
            return false
        }

        do {
            let regex = try NSRegularExpression(pattern: target)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let matches = regex.matches(in: value, range: range)
            return !matches.isEmpty
        } catch {
            return false
        }
    }

    static func time(
        _ left: JsonValue?,
        _ right: JsonValue?,
        _ op: String?
    ) -> Bool {
        guard let left = left?.asDouble(),
            let right = right?.asDouble()
        else {
            return false
        }

        switch op {
        case "before":
            return left < right
        case "after":
            return left > right
        case "on":
            return startOfDay(left) == startOfDay(right)
        default:
            return false
        }
    }
}

func startOfDay(_ time: Double) -> Double {
    let calendar = Calendar.current
    let date = Date(timeIntervalSince1970: time)
    let startOfDay = calendar.startOfDay(for: date)
    return startOfDay.timeIntervalSince1970
}
