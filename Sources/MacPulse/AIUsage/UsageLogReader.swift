import Foundation
import CZstd

/// Streams plain and Zstandard JSONL without unpacking private conversations to disk.
/// Memory is bounded by a decoder window, a 128 KiB output buffer and one metering line.
enum UsageLogReader {
    enum Failure: Error { case corruptArchive, oversizedArchive }
    static let maxLineBytes = 32 * 1024 * 1024
    static let maxDecodedBytes = 2 * 1024 * 1024 * 1024

    static func forEachLine(at url: URL, _ consume: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var droppingOversizedLine = false
        var decodedBytes = 0
        func accept(_ data: Data) throws {
            decodedBytes += data.count
            guard decodedBytes <= maxDecodedBytes else { throw Failure.oversizedArchive }
            var start = data.startIndex
            while let end = data[start...].firstIndex(of: 10) {
                if !droppingOversizedLine && pending.count + end - start <= maxLineBytes {
                    pending.append(data[start..<end])
                    if !pending.isEmpty { consume(pending) }
                }
                pending.removeAll(keepingCapacity: true)
                droppingOversizedLine = false
                start = end + 1
            }
            if !droppingOversizedLine && start < data.endIndex {
                if pending.count + data.endIndex - start <= maxLineBytes {
                    pending.append(data[start...])
                } else {
                    pending.removeAll(keepingCapacity: true)
                    droppingOversizedLine = true
                }
            }
        }

        if ["zst", "zstd"].contains(url.pathExtension) {
            guard let decoder = ZSTD_createDStream() else { throw Failure.corruptArchive }
            defer { ZSTD_freeDStream(decoder) }
            guard ZSTD_isError(ZSTD_initDStream(decoder)) == 0,
                  ZSTD_isError(ZSTD_DCtx_setParameter(decoder, ZSTD_d_windowLogMax, 27)) == 0 else {
                throw Failure.corruptArchive
            }
            var output = [UInt8](repeating: 0, count: 128 * 1024)
            var remaining = 1
            var readAny = false
            while let chunk = try handle.read(upToCount: 128 * 1024), !chunk.isEmpty {
                readAny = true
                try chunk.withUnsafeBytes { inputBytes in
                    var input = ZSTD_inBuffer(src: inputBytes.baseAddress, size: inputBytes.count, pos: 0)
                    var drainOutput = false
                    repeat {
                        let before = input.pos
                        let decoded: Data = try output.withUnsafeMutableBytes { buffer in
                            var out = ZSTD_outBuffer(dst: buffer.baseAddress, size: buffer.count, pos: 0)
                            remaining = ZSTD_decompressStream(decoder, &out, &input)
                            guard ZSTD_isError(remaining) == 0 else { throw Failure.corruptArchive }
                            if input.pos == before && out.pos == 0 && input.pos < input.size { throw Failure.corruptArchive }
                            drainOutput = out.pos == buffer.count && remaining != 0
                            return Data(bytes: buffer.baseAddress!, count: out.pos)
                        }
                        try accept(decoded)
                    } while input.pos < input.size || drainOutput
                }
            }
            // Truncated files must not be accepted as a smaller, complete history.
            guard readAny && remaining == 0 else { throw Failure.corruptArchive }
        } else {
            while let chunk = try handle.read(upToCount: 128 * 1024), !chunk.isEmpty {
                try accept(chunk)
            }
        }
        if !droppingOversizedLine && !pending.isEmpty { consume(pending) }
    }
}
