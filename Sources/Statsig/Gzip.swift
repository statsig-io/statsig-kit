import Compression
import Foundation

let BUFFER_SIZE = 1 << 15  // 32 kb

enum GzipError: Error {
    case streamInitError
    case srcBufferPointerError
    case streamProcessError
}

func gzipped(_ input: Data) -> Result<Data, GzipError> {
    guard !input.isEmpty else { return .success(Data()) }

    // Initialize compression stream
    let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    var status = compression_stream_init(streamPointer, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
    defer {
        compression_stream_destroy(streamPointer)
        streamPointer.deallocate()
    }
    guard status != COMPRESSION_STATUS_ERROR else {
        return .failure(.streamInitError)
    }

    let sourceSize = input.count

    // Initialize data with a fixed Gzip header
    var output = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])

    let gzipError = input.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> GzipError? in
        guard let srcPointer = srcBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return .srcBufferPointerError
        }
        streamPointer.pointee.src_ptr = srcPointer
        streamPointer.pointee.src_size = sourceSize

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: BUFFER_SIZE)
        defer { destinationBuffer.deallocate() }

        repeat {
            streamPointer.pointee.dst_ptr = destinationBuffer
            streamPointer.pointee.dst_size = BUFFER_SIZE

            status = compression_stream_process(
                streamPointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            if status == COMPRESSION_STATUS_ERROR { return .streamProcessError }

            let produced = BUFFER_SIZE - streamPointer.pointee.dst_size
            if produced > 0 {
                output.append(destinationBuffer, count: produced)
            }
        } while status == COMPRESSION_STATUS_OK

        return nil
    }

    if let gzipError = gzipError {
        return .failure(gzipError)
    }

    // Append trailer: CRC32 (4 bytes) and input size mod 2^32 (4 bytes), both little-endian
    let crc = crc32(input)
    var crcLE = crc.littleEndian
    var inputSizeLE = UInt32(truncating: sourceSize as NSNumber).littleEndian
    Swift.withUnsafeBytes(of: &crcLE) { output.append(contentsOf: $0) }
    Swift.withUnsafeBytes(of: &inputSizeLE) { output.append(contentsOf: $0) }

    return .success(output)
}
