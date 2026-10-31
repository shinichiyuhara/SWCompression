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
            definedBits = try self.szBits(count: count)
        } else {
            // LOCAL PATCH (fork): every caller reads at least 4 bytes per
            // defined item, so a count beyond the remaining bytes is a lie, and
            // honouring it would allocate `count` bytes from a few header bytes.
            guard count <= self.bytesLeft
                else { throw SevenZipError.internalStructureError }
            definedBits = Array(repeating: 1, count: count)
        }
        return definedBits
    }

    // LOCAL PATCH (fork): checked forms of BitByteData's reads. Those index the
    // buffer directly, so running off the end is an uncatchable trap. The header
    // parsers read fields whose positions are decided by earlier header fields,
    // so all of them go through these.

    func szByte() throws -> UInt8 {
        guard !self.isFinished else { throw SevenZipError.internalStructureError }
        return self.byte()
    }

    func szUint32() throws -> UInt32 {
        guard self.bytesLeft >= 4 else { throw SevenZipError.internalStructureError }
        return self.uint32()
    }

    func szUint64() throws -> UInt64 {
        guard self.bytesLeft >= 8 else { throw SevenZipError.internalStructureError }
        return self.uint64()
    }

    func szBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, count <= self.bytesLeft
            else { throw SevenZipError.internalStructureError }
        return self.bytes(count: count)
    }

    /// `count` is compared in bits rather than rounded up to bytes, which would
    /// overflow on a count near `Int.max`.
    func szBits(count: Int) throws -> [UInt8] {
        guard count >= 0, count <= self.bytesLeft * 8
            else { throw SevenZipError.internalStructureError }
        return self.bits(count: count)
    }

}
