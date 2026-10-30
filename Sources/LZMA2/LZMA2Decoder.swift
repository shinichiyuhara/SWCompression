// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

struct LZMA2Decoder {

    private let byteReader: LittleEndianByteReader
    private var decoder: LZMADecoder

    /// LOCAL PATCH (fork): output ceiling, checked against each chunk header
    /// before the chunk is decoded (see `LZMA2.decompress(_:_:limit:)`).
    var limit = Int.max

    var out: [UInt8] {
        return self.decoder.out
    }

    init(_ byteReader: LittleEndianByteReader, _ dictSizeByte: UInt8) throws {
        self.byteReader = byteReader
        self.decoder = LZMADecoder(byteReader)

        guard dictSizeByte & 0xC0 == 0
            else { throw LZMA2Error.wrongDictionarySize }
        let bits = (dictSizeByte & 0x3F).toInt()
        guard bits < 40
            else { throw LZMA2Error.wrongDictionarySize }

        let dictSize = bits == 40 ? UInt32.max :
            (UInt32(truncatingIfNeeded: 2 | (bits & 1)) << UInt32(truncatingIfNeeded: bits / 2 + 11))

        self.decoder.properties.dictionarySize = dictSize.toInt()
    }

    /// Main LZMA2 decoder function.
    mutating func decode() throws {
        mainLoop: while true {
            // LOCAL PATCH (fork): one call per LZMA2 chunk (<=2 MB), so a
            // long solid decode can drive a progress bar instead of appearing
            // hung. No-op unless a sink is installed. See Common/DecodeProgress.swift.
            DecodeProgress.tick(self.decoder.out.count)
            // A well-formed LZMA2 stream ends with a 0x00 control byte; if the
            // input runs out before it, reading the next control byte would
            // trap. Treat a missing end marker as truncation.
            guard byteReader.bytesLeft >= 1
                else { throw LZMA2Error.wrongControlByte }
            let controlByte = byteReader.byte()
            switch controlByte {
            case 0:
                break mainLoop
            case 1:
                self.decoder.resetDictionary()
                try self.decodeUncompressed()
            case 2:
                try self.decodeUncompressed()
            case 3...0x7F:
                throw LZMA2Error.wrongControlByte
            case 0x80...0xFF:
                try self.dispatch(controlByte)
            default:
                fatalError("Incorrect control byte.") // This statement is never executed.
            }
        }
    }

    /// Function which dispatches LZMA2 decoding process based on `controlByte`.
    private mutating func dispatch(_ controlByte: UInt8) throws {
        let uncompressedSizeBits = controlByte & 0x1F
        let reset = (controlByte & 0x60) >> 5
        // The chunk header is 4 more bytes (two 16-bit sizes); a compressed
        // chunk with reset >= 2 then reads a 1-byte properties field, and the
        // compressed data itself follows. Verify each region is present before
        // reading it, so a truncated chunk throws rather than trapping.
        guard self.byteReader.bytesLeft >= 4
            else { throw LZMA2Error.wrongSizes }
        let unpackSize = (uncompressedSizeBits.toInt() << 16) +
            self.byteReader.byte().toInt() << 8 + self.byteReader.byte().toInt() + 1
        let compressedSize = self.byteReader.byte().toInt() << 8 + self.byteReader.byte().toInt() + 1
        switch reset {
        case 0:
            break
        case 1:
            self.decoder.resetStateAndDecoders()
        case 2:
            try self.updateProperties()
        case 3:
            try self.updateProperties()
            self.decoder.resetDictionary()
        default:
            throw LZMA2Error.wrongReset
        }
        guard unpackSize <= self.limit - self.decoder.out.count
            else { throw OutputLimitExceeded() }
        self.decoder.uncompressedSize = unpackSize
        // The declared compressed data must be present in full. normalize()
        // pads with 0 past end as a backstop, but bounding the chunk here turns
        // a truncated file into a precise LZMA2Error rather than relying on the
        // downstream consumption check.
        guard self.byteReader.bytesLeft >= compressedSize
            else { throw LZMA2Error.wrongSizes }
        let outStartIndex = self.decoder.out.count
        let inStartIndex = self.byteReader.offset
        try self.decoder.decode()
        guard unpackSize == self.decoder.out.count - outStartIndex &&
            self.byteReader.offset - inStartIndex == compressedSize
            else { throw LZMA2Error.wrongSizes }
    }

    private mutating func decodeUncompressed() throws {
        // 2-byte size then that many literal bytes; both must be present.
        guard self.byteReader.bytesLeft >= 2
            else { throw LZMA2Error.wrongSizes }
        let dataSize = self.byteReader.byte().toInt() << 8 + self.byteReader.byte().toInt() + 1
        guard self.byteReader.bytesLeft >= dataSize
            else { throw LZMA2Error.wrongSizes }
        guard dataSize <= self.limit - self.decoder.out.count
            else { throw OutputLimitExceeded() }
        for _ in 0..<dataSize {
            self.decoder.put(self.byteReader.byte())
        }
    }

    /**
     Sets `lc`, `pb` and `lp` properties of LZMA decoder with a single `byte` using standard LZMA properties encoding
     scheme and resets decoder's state and sub-decoders.
     */
    private mutating func updateProperties() throws {
        guard byteReader.bytesLeft >= 1
            else { throw LZMA2Error.wrongSizes }
        self.decoder.properties = try LZMAProperties(lzmaByte: byteReader.byte(),
                                                     self.decoder.properties.dictionarySize)
        self.decoder.resetStateAndDecoders()
    }

}
