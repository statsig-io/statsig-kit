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
    let input = [UInt8](data)
    guard input.count >= 12 else {
        return .failure(StatsigError.unexpectedError("Empty response from DNS query"))
    }

    do {
        var index = 4
        let questionCount = try readUInt16(input, from: &index)
        let answerCount = try readUInt16(input, from: &index)
        let authorityCount = try readUInt16(input, from: &index)
        let additionalCount = try readUInt16(input, from: &index)

        for _ in 0..<questionCount {
            index = try skipDNSName(input, from: index)
            try advance(&index, by: 4, count: input.count)  // QTYPE + QCLASS
        }

        let totalRecords = Int(answerCount) + Int(authorityCount) + Int(additionalCount)
        var txtRecords = [String]()

        for _ in 0..<totalRecords {
            index = try skipDNSName(input, from: index)
            let type = try readUInt16(input, from: &index)
            _ = try readUInt16(input, from: &index)  // CLASS
            try advance(&index, by: 4, count: input.count)  // TTL
            let rdLength = Int(try readUInt16(input, from: &index))
            let rdataStart = index
            try advance(&index, by: rdLength, count: input.count)

            guard type == 16 else {  // TXT
                continue
            }

            let txtResult = try parseTXTRecord(input, from: rdataStart, length: rdLength)
            txtRecords.append(contentsOf: txtResult.components(separatedBy: ","))
        }

        guard !txtRecords.isEmpty else {
            return .failure(StatsigError.unexpectedError("Failed to parse TXT records from DNS"))
        }

        return .success(txtRecords)
    } catch {
        return .failure(error)
    }
}

fileprivate func advance(_ index: inout Int, by amount: Int, count: Int) throws {
    guard amount >= 0, index + amount <= count else {
        throw StatsigError.unexpectedError("DNS response out of bounds")
    }
    index += amount
}

fileprivate func readUInt16(_ input: [UInt8], from index: inout Int) throws -> UInt16 {
    guard index + 1 < input.count else {
        throw StatsigError.unexpectedError("DNS response out of bounds")
    }
    let value = (UInt16(input[index]) << 8) | UInt16(input[index + 1])
    index += 2
    return value
}

fileprivate func skipDNSName(_ input: [UInt8], from start: Int) throws -> Int {
    var index = start

    while true {
        guard index < input.count else {
            throw StatsigError.unexpectedError("Invalid DNS name")
        }

        let length = input[index]
        if length == 0 {
            return index + 1
        }

        if (length & 0xC0) == 0xC0 {
            guard index + 1 < input.count else {
                throw StatsigError.unexpectedError("Invalid DNS name pointer")
            }
            return index + 2
        }

        if (length & 0xC0) != 0 {
            throw StatsigError.unexpectedError("Invalid DNS label length")
        }

        index += 1
        guard index + Int(length) <= input.count else {
            throw StatsigError.unexpectedError("Invalid DNS label")
        }
        index += Int(length)
    }
}

fileprivate func parseTXTRecord(_ input: [UInt8], from start: Int, length: Int) throws -> String {
    let end = start + length
    guard end <= input.count else {
        throw StatsigError.unexpectedError("Invalid TXT record length")
    }

    var index = start
    var bytes = [UInt8]()
    while index < end {
        let stringLength = Int(input[index])
        index += 1
        guard index + stringLength <= end else {
            throw StatsigError.unexpectedError("Invalid TXT string length")
        }
        bytes.append(contentsOf: input[index..<(index + stringLength)])
        index += stringLength
    }

    guard let result = String(bytes: bytes, encoding: .utf8) else {
        throw StatsigError.unexpectedError("Failed to decode DNS response")
    }

    return result
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
