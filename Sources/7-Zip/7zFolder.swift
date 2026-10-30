// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

class SevenZipFolder {

    struct BindPair {

        let inIndex: Int
        let outIndex: Int

        init(_ bitReader: MsbBitReader) throws {
            inIndex = try bitReader.szMbd()
            outIndex = try bitReader.szMbd()
        }

    }

    let numCoders: Int
    private(set) var coders = [SevenZipCoder]()

    let numBindPairs: Int
    private(set) var bindPairs = [BindPair]()

    let numPackedStreams: Int
    private(set) var packedStreams = [Int]()

    private(set) var totalOutputStreams = 0
    private(set) var totalInputStreams = 0

    // These properties are stored in CoderInfo.
    var crc: UInt32?
    var unpackSizes = [Int]()

    // This property is stored in SubstreamInfo.
    var numUnpackSubstreams = 1

    lazy var orderedCompressionMethods: [CompressionMethod] = {
        self.orderedCoders().map { $0.compressionMethod }
    }()

    init(_ bitReader: MsbBitReader) throws {
        numCoders = try bitReader.szMbd()
        for _ in 0..<numCoders {
            let coder = try SevenZipCoder(bitReader)
            coders.append(coder)
            totalOutputStreams += coder.numOutStreams
            totalInputStreams += coder.numInStreams
        }

        guard totalOutputStreams != 0
            else { throw SevenZipError.internalStructureError }

        numBindPairs = totalOutputStreams - 1
        if numBindPairs > 0 {
            for _ in 0..<numBindPairs {
                bindPairs.append(try BindPair(bitReader))
            }
        }

        guard totalInputStreams >= numBindPairs
            else { throw SevenZipError.internalStructureError }

        numPackedStreams = totalInputStreams - numBindPairs
        if numPackedStreams == 1 {
            var i = 0
            while i < totalInputStreams {
                if self.bindPairForInStream(i) < 0 {
                    break
                }
                i += 1
            }
            if i == totalInputStreams {
                throw SevenZipError.internalStructureError
            }
            packedStreams.append(i)
        } else {
            for _ in 0..<numPackedStreams {
                packedStreams.append(try bitReader.szMbd())
            }
        }
    }

    func orderedCoders() -> [SevenZipCoder] {
        var result = [SevenZipCoder]()
        var current = 0
        while current != -1 {
            result.append(coders[current])
            let pair = bindPairForOutStream(current)
            current = pair != -1 ? bindPairs[pair].inIndex : -1
        }
        return result
    }

    func bindPairForInStream(_ index: Int) -> Int {
        for i in 0..<bindPairs.count {
            if bindPairs[i].inIndex == index {
                return i
            }
        }
        return -1
    }

    func bindPairForOutStream(_ index: Int) -> Int {
        for i in 0..<bindPairs.count {
            if bindPairs[i].outIndex == index {
                return i
            }
        }
        return -1
    }

    func unpackSize() -> Int {
        if totalOutputStreams == 0 {
            return 0
        }
        for i in stride(from: totalOutputStreams - 1, through: 0, by: -1) {
            if bindPairForOutStream(i) < 0 {
                return unpackSizes[i]
            }
        }
        return 0
    }

    func unpackSize(for coder: SevenZipCoder) -> Int {
        for i in 0..<coders.count {
            if coders[i] == coder {
                return unpackSizes[i]
            }
        }
        return 0
    }

    func unpack(data: Data) throws -> Data {
        var decodedData = data
        for coder in self.orderedCoders() {
            guard coder.numInStreams == 1 || coder.numOutStreams == 1
                else { throw SevenZipError.multiStreamNotSupported }

            let unpackSize = self.unpackSize(for: coder)

            switch coder.compressionMethod {
            case .copy:
                continue
            case .deflate:
                decodedData = try Self.limited { try Deflate.decompress(LsbBitReader(data: decodedData), limit: unpackSize) }
            case .bzip2:
                decodedData = try Self.limited { try BZip2.decompress(MsbBitReader(data: decodedData), limit: unpackSize) }
            case .lzma2:
                // Dictionary size is stored in coder's properties.
                guard let properties = coder.properties,
                    properties.count == 1
                    else { throw LZMA2Error.wrongDictionarySize }

                // LOCAL PATCH (fork): try the system decoder first. It is several
                // times faster than the pure-Swift one below. Framing can fail on
                // stream shapes LZMAFraming does not model, so the original path
                // stays as the fallback — and 7z's per-entry CRC-32 catches a
                // mis-framed decode, so a wrong answer here cannot pass silently.
                #if canImport(Compression)
                if let fast = try? LZMAFraming.decodeLZMA2(decodedData,
                                                          dictionarySizeProperty: properties[0],
                                                          uncompressedSize: unpackSize) {
                    decodedData = fast
                } else {
                    DecodeProgress.noteFallback("LZMA2")
                    decodedData = try Self.limited {
                        try LZMA2.decompress(LittleEndianByteReader(data: decodedData), properties[0], limit: unpackSize)
                    }
                }
                #else
                decodedData = try Self.limited {
                    try LZMA2.decompress(LittleEndianByteReader(data: decodedData), properties[0], limit: unpackSize)
                }
                #endif
            case .lzma:
                // Both properties' byte (lp, lc, pb) and dictionary size are stored in coder's properties.
                guard let properties = coder.properties,
                    properties.count == 5
                    else { throw LZMAError.wrongProperties }

                var dictionarySize = 0
                for i in 1..<5 {
                    dictionarySize |= properties[i].toInt() << (8 * (i - 1))
                }
                // LOCAL PATCH (fork): same as LZMA2 above, but wrapped in the
                // legacy `.lzma` framing — the xz container cannot carry LZMA1 by
                // specification, and real archives do use it (`Method = LZMA:24`).
                #if canImport(Compression)
                if let fast = try? LZMAFraming.decodeLZMA1(decodedData,
                                                          properties: Data(properties),
                                                          uncompressedSize: unpackSize) {
                    decodedData = fast
                } else {
                    DecodeProgress.noteFallback("LZMA")
                    let lzmaProperties = try LZMAProperties(lzmaByte: properties[0], dictionarySize)
                    decodedData = try LZMA.decompress(data: decodedData,
                                                      properties: lzmaProperties,
                                                      uncompressedSize: unpackSize)
                }
                #else
                let lzmaProperties = try LZMAProperties(lzmaByte: properties[0], dictionarySize)
                decodedData = try LZMA.decompress(data: decodedData,
                                                  properties: lzmaProperties,
                                                  uncompressedSize: unpackSize)
                #endif
            default:
                if coder.id == [0x03] {
                    guard let properties = coder.properties,
                        properties.count == 1
                        else { throw SevenZipError.internalStructureError }

                    decodedData = DeltaFilter.decode(LittleEndianByteReader(data: decodedData), (properties[0] &+ 1).toInt())
                } else if coder.id == [0x04, 0xF7, 0x11, 0x04] {
                    decodedData = try LZ4.decompress(data: decodedData)
                } else if let branchDecode = BranchFilter.decoder(for: coder.id) {
                    // LOCAL PATCH (fork): branch converters ("BCJ"). 7-Zip
                    // applies these to executables by default, so without them
                    // any .7z holding a binary fails outright. See
                    // 7-Zip/BranchFilters.swift and README.md.
                    //
                    // A branch filter does not change the length, so the
                    // `unpackSize` check after this loop still applies. It is
                    // the LAST coder in the chain (data flows LZMA2 -> BCJ),
                    // which `orderedCoders()` already guarantees.
                    var bytes = [UInt8](decodedData)
                    branchDecode(&bytes)
                    decodedData = Data(bytes)
                } else if coder.isEncryptionMethod {
                    throw SevenZipError.encryptionNotSupported
                } else {
                    throw SevenZipError.compressionNotSupported
                }
            }

            guard decodedData.count == unpackSize
                else { throw SevenZipError.wrongSize }
        }
        return decodedData
    }

    /// LOCAL PATCH (fork): run a decoder held to the coder's declared unpack
    /// size. Going over means the header lied about the size, which is what
    /// the `wrongSize` check after each coder reports — only now it is
    /// reported before the excess has been decoded rather than after.
    private static func limited(_ decode: () throws -> Data) throws -> Data {
        do {
            return try decode()
        } catch is OutputLimitExceeded {
            throw SevenZipError.wrongSize
        }
    }

}
