import Foundation

/// Decompresses bzip2 data using libbz2
enum BZip2Service {

    enum Error: Swift.Error, LocalizedError {
        case bzipError(Int32)
        case truncatedData

        var errorDescription: String? {
            switch self {
            case .bzipError(let code): return "BZip2 decompression failed (code \(code))"
            case .truncatedData:       return "BZip2 data is truncated"
            }
        }
    }

    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 4 else { throw Error.truncatedData }

        var stream = bz_stream()
        var ret = BZ2_bzDecompressInit(&stream, 0, 0)
        guard ret == BZ_OK else { throw Error.bzipError(ret) }
        defer { BZ2_bzDecompressEnd(&stream) }

        var output = Data()
        let bufSize = 65536
        var buf = [CChar](repeating: 0, count: bufSize)

        try data.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) throws in
            guard let base = inPtr.baseAddress else { return }
            stream.next_in   = UnsafeMutablePointer<CChar>(mutating: base.assumingMemoryBound(to: CChar.self))
            stream.avail_in  = UInt32(data.count)

            repeat {
                ret = buf.withUnsafeMutableBufferPointer { outBuf -> Int32 in
                    stream.next_out  = outBuf.baseAddress
                    stream.avail_out = UInt32(bufSize)
                    return BZ2_bzDecompress(&stream)
                }
                let produced = bufSize - Int(stream.avail_out)
                output.append(contentsOf: buf[0..<produced].map { UInt8(bitPattern: $0) })

                guard ret == BZ_OK || ret == BZ_STREAM_END else {
                    throw Error.bzipError(ret)
                }
            } while ret != BZ_STREAM_END
        }

        return output
    }
}
