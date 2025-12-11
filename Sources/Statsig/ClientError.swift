import Foundation

@objcMembers public class StatsigClientError: NSObject, Error {
    public let code: StatsigClientErrorCode
    public let message: String
    public let cause: (any Error)?

    init(_ code: StatsigClientErrorCode, message: String? = nil, cause: (any Error)? = nil) {
        self.code = code
        self.message = message ?? cause?.localizedDescription ?? defaultDescription(code)
        self.cause = cause
    }
}

@objc public enum StatsigClientErrorCode: Int {
    case alreadyStarted = 1
    case invalidClientSDKKey
    case clientUnstarted
    case failedToFetchValues
    case initTimeoutExpired
}

func defaultDescription(_ code: StatsigClientErrorCode) -> String {
    switch code {
    case .alreadyStarted:
        return "Statsig has already started!"
    case .invalidClientSDKKey:
        return "Must use a valid client SDK key."
    case .initTimeoutExpired:
        return "initTimeout Expired"

    // The clientUnstarted error code always has a custom message
    case .clientUnstarted:
        return "Must start Statsig first and wait for it to complete."

    // The failedToFetchValues error code often has a custom message
    case .failedToFetchValues:
        return "Failed to fetch values."
    }
}
