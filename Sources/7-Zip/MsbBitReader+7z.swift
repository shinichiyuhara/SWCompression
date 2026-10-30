// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

extension MsbBitReader {

    /// Abbreviation for "sevenZipMultiByteDecode".
    ///
    /// Reads 1–9 bytes. Every read is bounds-checked: reading past the end of
    /// the buffer is a Swift trap, not a throwable error, so a truncated or
    /// corrupt 7z header would crash the process. Because each call consumes at
    /// least one byte, making this throw also bounds the count-driven loops in
    /// the header parsers — a corrupt count that would iterate past the end
    /// throws here instead of trapping.
    func szMbd() throws -> Int {
        self.align()
        guard !self.isFinished else { throw SevenZipError.internalStructureError }
        let firstByte = self.byte().toInt()
        var mask = 0x80
        var value = 0
        for i in 0..<8 {
            if firstByte & mask == 0 {
                value |= ((firstByte & (mask &- 1)) << (8 * i))
                break
            }
            guard !self.isFinished else { throw SevenZipError.internalStructureError }
            value |= self.byte().toInt() << (8 * i)
            mask >>= 1
        }
        // LOCAL PATCH (fork): the 9-byte form puts its last byte at bit 56, so
        // a top bit of 1 comes out as a negative Int. Every caller uses the
        // value as a size, count or index, and a negative one traps later
        // (`UInt64(_:)`, ranges) where it can no longer be thrown. No real 7z
        // field needs 2^63 or more.
        guard value >= 0 else { throw SevenZipError.internalStructureError }
        return value
    }

    func defBits(count: Int) throws -> [UInt8] {
        self.align()
        guard count >= 0, !self.isFinished else { throw SevenZipError.internalStructureError }
        let allDefined = self.byte()
        let definedBits: [UInt8]
        if allDefined == 0 {
            // `bits(count:)` reads ceil(count/8) bytes; a corrupt `count` from
            // the header must not read past the buffer.
            guard (count + 7) / 8 <= self.bytesLeft
                else { throw SevenZipError.internalStructureError }
            definedBits = self.bits(count: count)
        } else {
            definedBits = Array(repeating: 1, count: count)
        }
        return definedBits
    }

}
