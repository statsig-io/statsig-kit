import Foundation

class ErrorBoundary {
    private static let defaultExceptionURL = URL(string: "https://statsigapi.net/v1/sdk_exception")

    private var clientKey: String
    private var statsigOptions: StatsigOptions
    private var seen: Set<String>
    private var url: URL?

    static func boundary(clientKey: String, statsigOptions: StatsigOptions) -> ErrorBoundary {
        let boundary = ErrorBoundary(
            clientKey: clientKey,
            statsigOptions: statsigOptions,
            seen: Set<String>(),
            url: statsigOptions.sdkExceptionDiagnosticsURL ?? defaultExceptionURL
        )
        return boundary
    }

    private init(clientKey: String, statsigOptions: StatsigOptions, seen: Set<String>, url: URL?) {
        self.clientKey = clientKey
        self.statsigOptions = statsigOptions
        self.seen = seen
        self.url = url
    }

    func capture(_ tag: String, task: () throws -> Void, recovery: (() -> Void)? = nil) {
        do {
            try task()
        } catch let error {
            PrintHandler.log("[Statsig]: An unexpected exception occurred.")

            logException(tag: tag, error: error)

            recovery?()
        }
    }

    private func getErrorDetails(_ error: any Error) -> (name: String, info: String) {
        if let statsigError = error as? LocalizedError {
            return (
                name: String(describing: type(of: error)),
                info: statsigError.localizedDescription
            )
        }
        return (
            name: String(describing: type(of: error)),
            info: String(describing: error)
        )
    }

    func logException(tag: String, error: any Error) {
        let errorDetails = getErrorDetails(error)
        let key = "\(tag):\(errorDetails.name)"
        if seen.contains(key) {
            return
        }
        seen.insert(key)

        do {
            guard let url = self.url else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-type")

            let body: [String: Any] = [
                "exception": errorDetails.name,
                "info": errorDetails.info,
                // TODO: Use user.deviceEnvironment instead of DeviceEnvironment.getSDKMetadata().
                "statsigMetadata": DeviceEnvironment.getSDKMetadata().merging(
                    self.statsigOptions.environment, uniquingKeysWith: { $1 }
                ),
                "tag": tag,
                "statsigOptions": self.statsigOptions.getDictionaryForLogging(),
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: body)

            if !clientKey.isEmpty {
                request.setValue(clientKey, forHTTPHeaderField: "STATSIG-API-KEY")
            }

            request.httpBody = jsonData

            statsigOptions.urlSession.dataTask(with: request).resume()
        } catch {}
    }
}
