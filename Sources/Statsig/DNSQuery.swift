import Foundation

// DNS Wireformat Query for 'featureassets.org'
let FEATURE_ASSETS_DNS_QUERY: [UInt8] = [
    0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x0d, 0x66, 0x65, 0x61,
    0x74, 0x75, 0x72, 0x65, 0x61, 0x73, 0x73, 0x65,
    0x74, 0x73, 0x03, 0x6f, 0x72, 0x67, 0x00, 0x00,
    0x10, 0x00, 0x01,
]

let DNS_QUERY_ENDPOINT = "https://cloudflare-dns.com/dns-query"
let DOMAIN_CHARS: [Character] = ["i", "e", "d"]
let MAX_START_LOOKUP = 200

internal func fetchTxtRecords(completion: @escaping (Result<[String], Error>) -> Void) {
    guard let url = URL(string: DNS_QUERY_ENDPOINT) else {
        completion(.failure(StatsigError.unexpectedError("Invalid DNS URL")))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/dns-message", forHTTPHeaderField: "Content-Type")
    request.addValue("application/dns-message", forHTTPHeaderField: "Accept")
    request.httpBody = Data(FEATURE_ASSETS_DNS_QUERY)

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let data = data
        else {
            completion(
                .failure(StatsigError.unexpectedError("Failed to fetch TXT records from DNS")))
            return
        }

        completion(parseDNSResponse(data: data))
    }

    task.resume()
}

internal func parseDNSResponse(data: Data) -> Result<[String], Error> {
    let eqCode = UInt8(ascii: "=")
    let input = [UInt8](data)
    let lookupLength = min(MAX_START_LOOKUP, input.count)
    guard lookupLength > 0 else {
        return .failure(StatsigError.unexpectedError("Empty response from DNS query"))
    }

    // Loop until we find the first valid domain char, one of ['i', 'e', 'd']
    var startIndex: Int?
    for index in 1..<lookupLength {
        if input[index] != eqCode {
            continue
        }
        let prevChar = Character(UnicodeScalar(input[index - 1]))
        if DOMAIN_CHARS.contains(prevChar) {
            startIndex = index - 1
            break
        }
    }

    guard let start = startIndex else {
        return .failure(StatsigError.unexpectedError("Failed to parse TXT records from DNS"))
    }

    // Decode the remaining bytes as a string
    let remainingBytes = input[start..<input.count]
    guard let result = String(bytes: remainingBytes, encoding: .utf8) else {
        return .failure(StatsigError.unexpectedError("Failed to decode DNS response"))
    }

    return .success(result.components(separatedBy: ","))
}

// Usage
// fetchTxtRecords { result in
//     switch result {
//     case .success(let txtRecords):
//         print("TXT Records: \(txtRecords)")
//     case .failure(let error):
//         print("Error: \(error.localizedDescription)")
//     }
// }
