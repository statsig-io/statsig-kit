import Foundation

public class PrintHandler {
    private static var printHandler: ((String) -> Void)?

    static func setPrintHandler(_ handler: @escaping (String) -> Void) {
        if let existingHandler = printHandler {
            existingHandler(
                "[Statsig]: Warning - Attempting to override existing printHandler. The original handler will be preserved to prevent concurrency crashes."
            )
            return
        }
        printHandler = handler
    }

    static func log(_ message: String) {
        if let handler = printHandler {
            handler(message)
        } else {
            print(message)
        }
    }

    internal static func reset() {
        printHandler = nil
    }
}
