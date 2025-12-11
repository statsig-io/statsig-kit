import Foundation

enum StatsigError: Error {
    case invalidJSONParam(String)
    case invalidRequestURL(String)
    case tooManyRequests(String)
    case unexpectedError(String)
}

extension StatsigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidJSONParam(let paramName):
            return NSLocalizedString(
                "The param \(paramName) is not a valid JSON object.", comment: "")
        case .invalidRequestURL(let requestType):
            return NSLocalizedString(
                "The request URL for \(requestType) is not valid.", comment: "")
        case .tooManyRequests(let requestURL):
            return NSLocalizedString("Too many requests made to \(requestURL).", comment: "")
        case .unexpectedError(let context):
            return NSLocalizedString("An unexpected error occured -- \(context)", comment: "")
        }
    }
}
