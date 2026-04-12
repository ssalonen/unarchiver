import Foundation

/// Decompresses gzip (.gz) data using zlib
enum GZipService {

    enum Error: Swift.Error, LocalizedError {
        case invalidMagic
        case truncatedHeader
        case zlibError(Int32, String?)
        case truncatedData

        var errorDescription: String? {
            switch self {
            case .invalidMagic:      return "Not a valid gzip file"
            case .truncatedHeader:   return "Gzip header is truncated"
            case .zlibError(let code, let msg): return "Decompression failed (zlib \(code)): \(msg ?? "unknown")"
            case .truncatedData:     return "Gzip data is truncated"
            }
        }
    }

    /// Returns the embedded original filename from gzip header if available
    static func originalFilename(from data: Data) -> String? {
        guard data.count >= 10, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        let flags = data[3]
        guard flags & 0x08 != 0 else { return nil }
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { return nil }
            let extraLen = Int(data[offset]) | Int(data[offset + 1]) << 8
            offset += 2 + extraLen
        }
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 { end += 1 }
        return String(bytes: data[offset..<end], encoding: .isoLatin1)
    }

    /// Decompresses a gzip-compressed Data buffer
    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 10 else { throw Error.truncatedHeader }
        guard data[0] == 0x1f && data[1] == 0x8b else { throw Error.invalidMagic }

        // Parse gzip header to find start of compressed payload
        let flags = data[3]
        var offset = 10

        if flags & 0x04 != 0 {                     // FEXTRA
            guard offset + 2 <= data.count else { throw Error.truncatedHeader }
            let extraLen = Int(data[offset]) | Int(data[offset + 1]) << 8
            offset += 2 + extraLen
        }
        if flags & 0x08 != 0 {                     // FNAME
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {                     // FCOMMENT
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }       // FHCRC

        guard offset < data.count else { throw Error.truncatedData }

        return try inflateRawDeflate(data.subdata(in: offset..<data.count))
    }

    /// Inflate raw DEFLATE-compressed bytes (no zlib/gzip framing)
    static func inflateRawDeflate(_ compressed: Data) throws -> Data {
        var stream = z_stream()
        // windowBits = -15 → raw deflate (no header/trailer)
        var ret = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard ret == Z_OK else { throw Error.zlibError(ret, nil) }
        defer { inflateEnd(&stream) }

        var output = Data()
        var bufSize = max(compressed.count * 4, 65536)
        var buf = [UInt8](repeating: 0, count: bufSize)

        try compressed.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) throws in
            guard let base = inPtr.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in  = UnsafeMutablePointer<Bytef>(mutating: base)
            stream.avail_in = uInt(compressed.count)

            repeat {
                if stream.avail_out == 0 {
                    bufSize = bufSize * 2
                    buf = [UInt8](repeating: 0, count: bufSize)
                }
                ret = buf.withUnsafeMutableBufferPointer { outBuf -> Int32 in
                    stream.next_out  = outBuf.baseAddress
                    stream.avail_out = uInt(outBuf.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = bufSize - Int(stream.avail_out)
                output.append(contentsOf: buf.prefix(produced))
                buf = [UInt8](repeating: 0, count: bufSize)

                guard ret != Z_STREAM_ERROR && ret != Z_DATA_ERROR && ret != Z_MEM_ERROR else {
                    throw Error.zlibError(ret, nil)
                }
            } while ret != Z_STREAM_END
        }

        return output
    }
}
