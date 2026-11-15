// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

/// Provides decompression function for LZMA.
public class LZMA: DecompressionAlgorithm {

    /**
     Decompresses `data` using LZMA.

     - Note: It is assumed that the first nine bytes of `data` represent standard LZMA properties (so called "lc", "lp"
     and "pb"), dictionary size, and uncompressed size all encoded with standard encoding scheme of LZMA format.

     - Parameter data: Data compressed with LZMA.

     - Throws: `LZMAError` if unexpected byte (bit) sequence was encountered in `data`. It may indicate that either data
     is damaged or it might not be compressed with LZMA at all.

     - Returns: Decompressed data.
     */
    public static func decompress(data: Data) throws -> Data {
        // Valid LZMA "archive" must contain at least 13 bytes of data with properties and uncompressed size.
        guard data.count >= 13
            else { throw LZMAError.wrongProperties }

        let byteReader = LittleEndianByteReader(data: data)
        let properties = try LZMAProperties(byteReader)
        let uncompSize = try headerUncompressedSize(byteReader)
        return try decompress(byteReader, properties, uncompSize)
    }

    /**
     LOCAL PATCH (fork). Decompresses LZMA `data`, refusing to produce more than `limit` bytes. The size in the header
     is not trusted: it can be absent, and it can lie.

     - Throws: as `decompress(data:)` does, or `DecompressionLimitExceeded` once the output passes `limit`.
     */
    public static func decompress(data: Data, limit: Int) throws -> Data {
        guard data.count >= 13
            else { throw LZMAError.wrongProperties }
        let byteReader = LittleEndianByteReader(data: data)
        let properties = try LZMAProperties(byteReader)
        let uncompSize = try headerUncompressedSize(byteReader)
        do {
            return try decompress(byteReader, properties, uncompSize, limit: limit)
        } catch is OutputLimitExceeded {
            throw DecompressionLimitExceeded(limit: limit)
        }
    }

    /**
     Decompresses `data` using LZMA with specified algorithm's `properties`, and, optionally, output's
     `uncompressedSize`. If `uncompressedSize` is nil, then `data` must contain finish marker.

     - Note: It is assumed that `data` begins immediately with LZMA compressed bytes with no LZMA properties at the
     beginning.

     - Warning: There is no validation performed for properties of `properties` argument. This API is intended to be
     used by advanced users.

     - Parameter data: Data compressed with LZMA.
     - Parameter properties: Properties of LZMA (such as lc, lp, etc.)
     - Parameter uncompressedSize: Size of uncompressed data; `nil` if it is unknown. In case of `nil`, finish marker
     must be present in `data`.

     - Throws: `LZMAError` if unexpected byte (bit) sequence was encountered in `data`. It may indicate that either data
     is damaged or it might not be compressed with LZMA at all.

     - Returns: Decompressed data.
     */
    public static func decompress(data: Data,
                                  properties: LZMAProperties,
                                  uncompressedSize: Int? = nil) throws -> Data {
        let byteReader = LittleEndianByteReader(data: data)
        return try decompress(byteReader, properties, uncompressedSize)
    }

    static func decompress(_ byteReader: LittleEndianByteReader,
                           _ properties: LZMAProperties,
                           _ uncompSize: Int?,
                           limit: Int = .max) throws -> Data {
        var decoder = LZMADecoder(byteReader)
        decoder.limit = limit
        decoder.properties = properties
        decoder.resetStateAndDecoders()
        decoder.uncompressedSize = uncompSize ?? -1

        try decoder.decode()
        return Data(decoder.out)
    }

    /// LOCAL PATCH (fork): the .lzma header's size, 8 bytes little-endian, where
    /// all ones means "unknown, look for the end marker". Read as `Int`, any
    /// other value with the top bit set came out negative: 2^63 became
    /// `Int.min` and the first `uncompressedSize -= 1` overflowed (a trap), and
    /// the rest disabled the size check. Such sizes are refused (security audit
    /// 2026-11-15, W11).
    private static func headerUncompressedSize(_ byteReader: LittleEndianByteReader) throws -> Int {
        let raw = byteReader.uint64()
        if raw == UInt64.max {
            return -1
        }
        guard let size = Int(exactly: raw)
            else { throw LZMAError.wrongProperties }
        return size
    }

}
