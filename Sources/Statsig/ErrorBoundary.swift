import Foundation

class ErrorBoundary {
    private var clientKey: String
    private var statsigOptions: StatsigOptions
    private var seen: Set<String>
    private var url: String

    static func boundary(clientKey: String, statsigOptions: StatsigOptions) -> ErrorBoundary {
        let boundary = ErrorBoundary(
            clientKey: clientKey,
            statsigOptions: statsigOptions,
            seen: Set<String>(),
            url: "https://statsigapi.net/v1/sdk_exception"
        )
        return boundary
    }

    private init(clientKey: String, statsigOptions: StatsigOptions, seen: Set<String>, url: String)
    {
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
            guard let url = URL(string: self.url) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-type")

            let body: [String: Any] = [
                "exception": errorDetails.name,
                "info": errorDetails.info,
                "statsigMetadata": self.statsigOptions.environment,
                "tag": tag,
                "statsigOptions": self.statsigOptions.getDictionaryForLogging(),
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: body)

            if !clientKey.isEmpty {
                request.setValue(clientKey, forHTTPHeaderField: "STATSIG-API-KEY")
            }

            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request).resume()
        } catch {}
    }
}
