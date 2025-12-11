import Foundation

class NetworkMarker: MarkerBase {
    let step = "network_request"

    convenience init(_ recorder: MarkerAtomicDict, key: String) {
        self.init(recorder, context: .initialize, markerKey: key)
    }

    func start(attempt: Int) {
        super.start([
            "step": step,
            "attempt": attempt,
        ])
    }

    func end(_ attempt: Int, _ data: Data?, _ response: URLResponse?, _ error: Error?) {
        let isSuccess = error == nil && response?.isOK == true

        var args: [String: Any] = [
            "step": step,
            "success": isSuccess,
            "attempt": attempt,
        ]

        if let status = response?.status {
            args["statusCode"] = status
        }

        if let region = response?.statsigRegion {
            args["sdkRegion"] = region
        }

        if !isSuccess, let details = getFormattedNetworkError(error: error, data: data) {
            args["error"] = details
        }

        super.end(args)
    }

    private func getFormattedNetworkError(error: Error?, data: Data?) -> [String: Any]? {
        guard let message = error?.localizedDescription ?? data?.text else {
            return nil
        }

        var code: String? = nil
        var name = "unknown"
        if let error = error as? NSError {
            name = error.domain
            code = "\(error.code)"
        } else if error != nil {
            name = String(describing: type(of: error))
        }

        var args = [
            "name": name,
            "message": message,
        ]

        if let code = code {
            args["code"] = code
        }

        return args
    }
}
