import Foundation

extension URLResponse {
    var asHttpResponse: HTTPURLResponse? {
        return self as? HTTPURLResponse
    }

    var status: Int? {
        return self.asHttpResponse?.statusCode
    }

    var statsigRegion: String? {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            return self.asHttpResponse?.value(forHTTPHeaderField: "x-statsig-region")
        }

        return nil
    }

    var isOK: Bool {
        let code = self.status ?? 0
        return code >= 200 && code < 300
    }
}
