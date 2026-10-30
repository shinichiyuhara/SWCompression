// LOCAL ADDITION — not part of upstream SWCompression.
// See README.md ("Differences from upstream").
//
// Copyright (c) 2026 Shinichi Yuhara.
// Contributed under the same MIT License as the surrounding project.
//
// ---------------------------------------------------------------------------
// LZMAFraming — decode 7z's LZMA1 / LZMA2 streams with Apple's Compression
// framework, by wrapping them in the container framing that framework requires.
//
// ## Why this exists
//
// A 7z archive stores its compressed payload as a RAW codec stream: no container,
// no framing, because the sizes and codec parameters live in the 7z header. Apple's
// `COMPRESSION_LZMA` will not read that (measured: `COMPRESSION_STATUS_ERROR`).
// It reads two *containers*:
//
//   - `.xz`    — which holds LZMA2, and by specification cannot hold LZMA1
//   - `.lzma`  — the legacy "alone" format, which holds LZMA1
//
// Both containers are, in the shapes 7z produces, a fixed preamble around the very
// same raw bytes. Measured on a real stream: an `.xz` file is 32 bytes of header +
// the identical raw LZMA2 payload + 32 bytes of footer. So the payload never has to
// be transformed — only framed.
//
// That framing is what this file builds. The gain is worth the ~200 lines: the
// pure-Swift decoder in this library runs at roughly 23–62 MB/s, while the system
// decoder measured 368 MB/s in memory, and end-to-end extraction (bounded by disk
// writes) improves by 2–3x.
//
// ## Why not bring in a C decoder instead
//
// Because nothing has to be brought in. This links a system framework, so there is
// no third-party source added to the repository and no second upstream to track for
// CVEs. macOS does ship liblzma, but without public headers — that is private API
// and off-limits; `Compression` is the public route to the same code.
//
// ## Contract
//
// Framing can fail to apply — an unusual dictionary size, a coder chain this does
// not model, a stream shape not seen yet. Callers MUST keep their existing decoder
// and fall back to it. A wrong decode is not silent here: 7z stores a CRC-32 per
// entry, so a mis-framed stream fails verification rather than producing plausible
// garbage. Use that; do not assume this path is correct because it returned bytes.
//
// Placed inside the library rather than in a consuming app because the call sites
// are in 7zFolder.swift, and this module cannot import back up the dependency
// graph. Availability is therefore a property of the library, not of any host.

// `Compression` is an Apple-platform framework. On Linux / Windows / Android /
// WASI this file compiles to nothing and the call sites in 7zFolder.swift take
// their `#else` branch — the pure-Swift decoder, i.e. upstream's behaviour.
#if canImport(Compression)

import Foundation
import Compression

enum LZMAFraming {

    // MARK: - Errors

    enum Failure: Error, CustomStringConvertible {
        case decoderInitFailed
        case decodeFailed
        case sizeMismatch(got: Int, expected: Int)

        var description: String {
            switch self {
            case .decoderInitFailed:      return "Compression framework refused to start"
            case .decodeFailed:           return "Compression framework reported an error"
            case let .sizeMismatch(g, e): return "decoded \(g) bytes, expected \(e)"
            }
        }
    }

    // MARK: - Public entry points

    /// Decode a raw LZMA2 stream as 7z stores it.
    ///
    /// - Parameters:
    ///   - stream: the packed bytes for one folder / coder.
    ///   - dictionarySizeProperty: the single properties byte 7z records for an
    ///     LZMA2 coder. It encodes the dictionary size; it is passed through
    ///     verbatim rather than decoded, because xz's block header wants exactly
    ///     the same encoding.
    ///   - uncompressedSize: from the 7z header. Used to size the output and to
    ///     check the result — see the contract note above.
    static func decodeLZMA2(_ stream: Data,
                                   dictionarySizeProperty: UInt8,
                                   uncompressedSize: Int) throws -> Data {
        let framed = xzContainer(around: stream,
                                 dictionaryProperty: dictionarySizeProperty,
                                 uncompressedSize: uncompressedSize)
        return try decodeContainer(framed, expecting: uncompressedSize)
    }

    /// Decode a raw LZMA1 stream as 7z stores it.
    ///
    /// - Parameter properties: the 5 properties bytes 7z records for an LZMA1
    ///   coder — one packed lc/lp/pb byte followed by the dictionary size as
    ///   little-endian UInt32. The `.lzma` "alone" header begins with exactly
    ///   those five bytes, so they are copied straight through; only the 8-byte
    ///   size field has to be appended.
    static func decodeLZMA1(_ stream: Data,
                                   properties: Data,
                                   uncompressedSize: Int) throws -> Data {
        guard properties.count >= 5 else { throw Failure.decodeFailed }
        var framed = Data(properties.prefix(5))
        framed.append(contentsOf: withUnsafeBytes(of: UInt64(uncompressedSize).littleEndian,
                                                  Array.init))
        framed.append(stream)
        return try decodeContainer(framed, expecting: uncompressedSize)
    }

    // MARK: - Container construction

    /// Build the smallest `.xz` stream that carries `payload` as its only block.
    ///
    /// The check field is set to NONE. xz's own integrity check would duplicate
    /// work: 7z already stores a CRC-32 per entry and the caller verifies that, so
    /// computing a second checksum here would cost a pass over the output to
    /// re-detect what the caller detects anyway.
    static func xzContainer(around payload: Data,
                            dictionaryProperty: UInt8,
                            uncompressedSize: Int) -> Data {
        let streamFlags = Data([0x00, 0x00])          // check = NONE
        var out = Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
        out.append(streamFlags)
        out.append(le32(crc32(streamFlags)))

        // Block header: one filter (LZMA2 = 0x21) whose properties are the single
        // dictionary byte. No compressed/uncompressed size fields — the LZMA2
        // end-of-stream marker terminates it, and the index below carries the sizes.
        var block = Data([0x00, 0x00, 0x21, 0x01, dictionaryProperty])
        while (block.count + 4) % 4 != 0 { block.append(0x00) }
        block[0] = UInt8((block.count + 4) / 4 - 1)   // size byte counts the CRC too
        block.append(le32(crc32(block)))

        out.append(block)
        out.append(payload)
        let blockPadding = (4 - payload.count % 4) % 4
        out.append(Data(repeating: 0x00, count: blockPadding))

        // Index: one record, holding the unpadded block size and the real output
        // size. "Unpadded" means header + payload + check, before 4-byte alignment.
        var index = Data([0x00])
        index.append(vli(1))
        index.append(vli(block.count + payload.count))
        index.append(vli(uncompressedSize))
        while index.count % 4 != 0 { index.append(0x00) }
        index.append(le32(crc32(index)))
        out.append(index)

        // Footer: CRC of (backward size + flags), then those fields, then "YZ".
        var footerCore = le32(UInt32(index.count / 4 - 1))
        footerCore.append(streamFlags)
        out.append(le32(crc32(footerCore)))
        out.append(footerCore)
        out.append(Data([0x59, 0x5A]))
        return out
    }

    // MARK: - Decoding

    private static func decodeContainer(_ framed: Data, expecting: Int) throws -> Data {
        var out = Data()
        out.reserveCapacity(expecting)
        let bufferSize = 1 << 18
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var stream = compression_stream(dst_ptr: buffer, dst_size: bufferSize,
                                        src_ptr: buffer, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE,
                                      COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw Failure.decoderInitFailed
        }
        defer { compression_stream_destroy(&stream) }

        var status = COMPRESSION_STATUS_OK
        try framed.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw Failure.decodeFailed
            }
            stream.src_ptr = base
            stream.src_size = framed.count
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            repeat {
                status = compression_stream_process(
                    &stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    // LOCAL PATCH (fork): stop as soon as the decoder passes
                    // the size the caller expects, rather than letting the
                    // stream run on and comparing at the end.
                    guard produced <= expecting - out.count else {
                        throw Failure.sizeMismatch(got: out.count + produced, expected: expecting)
                    }
                    out.append(buffer, count: produced)
                    // Report from here, not only from LZMA2Decoder's chunk loop.
                    // This path decodes a whole folder inside one framework call
                    // and never enters that loop, so without this line making 7z
                    // FASTER made a host app's progress bar stop moving — the
                    // exact failure DecodeProgress was written to prevent.
                    DecodeProgress.tick(out.count)
                }
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize
            } while status == COMPRESSION_STATUS_OK
        }
        guard status != COMPRESSION_STATUS_ERROR else { throw Failure.decodeFailed }
        guard out.count == expecting else {
            throw Failure.sizeMismatch(got: out.count, expected: expecting)
        }
        return out
    }

    // MARK: - Primitives

    /// xz's variable-length integer: 7 bits per byte, high bit marks continuation.
    private static func vli(_ value: Int) -> Data {
        var v = UInt64(value)
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    private static func le32(_ v: UInt32) -> Data {
        Data(withUnsafeBytes(of: v.littleEndian, Array.init))
    }

    /// CRC-32 (IEEE), which xz uses for its header and index checks.
    ///
    /// Implemented here rather than taken from zlib so this file stays dependency
    /// free — it is meant to be copied into apps that may not link zlib, and the
    /// inputs are tens of bytes, so a table-driven loop costs nothing.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

#endif  // canImport(Compression)
