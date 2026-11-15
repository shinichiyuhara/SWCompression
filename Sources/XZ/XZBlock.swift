// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

struct XZBlock {

    let data: Data
    let unpaddedSize: Int

    var uncompressedSize: Int {
        return data.count
    }

    init(_ blockHeaderSize: UInt8, _ byteReader: LittleEndianByteReader, _ checkSize: Int,
         limit: Int = .max) throws {
        let blockHeaderStartIndex = byteReader.offset - 1
        let realBlockHeaderSize = (blockHeaderSize.toInt() + 1) * 4

        // The whole block header is realBlockHeaderSize bytes measured from
        // blockHeaderStartIndex; the caller already consumed the 1-byte size
        // field, so realBlockHeaderSize - 1 must still be available. Every read
        // below to the end of the header — blockFlags, the multiByteDecode
        // sizes/filter IDs, the zero-padding loop, and the bytes(count:) the
        // CRC re-reads — stays inside that region, so this single check keeps
        // them all in bounds. Without it a truncated file makes those reads
        // index past the end, which is an uncatchable Swift trap.
        guard byteReader.bytesLeft >= realBlockHeaderSize - 1
            else { throw XZError.wrongField }
        // LOCAL PATCH (fork): the check above does not keep the reads inside the
        // header, contrary to what it says: the two sizes and the filter
        // fields are variable-length, so a header whose fields run past its
        // declared size read on past the end of the input — a trap from 32
        // bytes (security audit 2026-11-15, W9). Every field must end before
        // the header's CRC; the reads that may cross it (`multiByteDecode`)
        // bound themselves by the input and are checked right after.
        let headerFieldsEnd = blockHeaderStartIndex + realBlockHeaderSize - 4
        func headerFieldsFit(_ count: Int = 0) throws {
            guard realBlockHeaderSize >= 8, byteReader.offset + count <= headerFieldsEnd
                else { throw XZError.wrongField }
        }

        try headerFieldsFit(1)
        let blockFlags = byteReader.byte()
        /**
         Bit values 00, 01, 10, 11 indicate filters number from 1 to 4,
         so we actually need to add 1 to get filters' number.
         */
        let filtersCount = blockFlags & 0x03 + 1
        guard blockFlags & 0x3C == 0
            else { throw XZError.wrongField }

        /// Should match size of compressed data.
        let compressedSize = blockFlags & 0x40 != 0 ? try byteReader.multiByteDecode() : -1
        try headerFieldsFit()

        /// Should match the size of data after decompression.
        let uncompressedSize = blockFlags & 0x80 != 0 ? try byteReader.multiByteDecode() : -1
        try headerFieldsFit()

        var filters: [(LittleEndianByteReader) throws -> Data] = []
        // LOCAL PATCH (fork): as the .xz format requires, LZMA2 must be the last
        // filter and only the last. Up to four LZMA2 stages each decoded up to
        // `limit`, and a chain ending in Delta was decoded too (security audit
        // 2026-11-15, W43). With LZMA2 once at the end, the Delta stages before
        // it keep the size, so the output is bounded by `limit`.
        for filterIndex in 0..<filtersCount {
            let isLastFilter = filterIndex == filtersCount - 1
            let filterID = try byteReader.multiByteDecode()
            try headerFieldsFit()
            guard UInt64(filterID) < 0x4000000000000000
                else { throw XZError.wrongFilterID }
            // Only LZMA2 filter is supported.
            switch filterID {
            case 0x21:
                guard isLastFilter
                    else { throw XZError.wrongFilterID }
                // First, we need to check if size of LZMA2 filter's properties is equal to 1 as expected.
                let propertiesSize = try byteReader.multiByteDecode()
                guard propertiesSize == 1
                    else { throw LZMA2Error.wrongDictionarySize }
                try headerFieldsFit(1)
                /// Filter property for LZMA2 is a dictionary size.
                let filterPropeties = byteReader.byte()
                filters.append { try LZMA2.decompress($0, filterPropeties, limit: limit) }
            case 0x03:
                guard !isLastFilter
                    else { throw XZError.wrongFilterID }
                // First, we need to check if size of Delta filter's properties is equal to 1 as expected.
                let propertiesSize = try byteReader.multiByteDecode()
                guard propertiesSize == 1
                    else { throw XZError.wrongField }
                try headerFieldsFit(1)
                let distance = (byteReader.byte() &+ 1).toInt()
                filters.append { DeltaFilter.decode($0, distance) }
            default:
                throw XZError.wrongFilterID
            }
        }

        // We need to take into account 4 bytes for CRC32 so thats why "-4".
        while byteReader.offset - blockHeaderStartIndex < realBlockHeaderSize - 4 {
            let byte = byteReader.byte()
            guard byte == 0x00
                else { throw XZError.wrongPadding }
        }

        let blockHeaderCRC = byteReader.uint32()
        byteReader.offset = blockHeaderStartIndex
        guard CheckSums.crc32(byteReader.bytes(count: realBlockHeaderSize - 4)) == blockHeaderCRC
            else { throw XZError.wrongInfoCRC }
        byteReader.offset += 4

        let compressedDataStart = byteReader.offset
        let out = try filters.reversed().reduce(byteReader) { try LittleEndianByteReader(data: $1($0)) }

        guard compressedSize < 0 || compressedSize == byteReader.offset - compressedDataStart,
            uncompressedSize < 0 || uncompressedSize == out.data.count
            else { throw XZError.wrongDataSize }

        let unpaddedSize = byteReader.offset - blockHeaderStartIndex

        if unpaddedSize % 4 != 0 {
            let paddingSize = 4 - unpaddedSize % 4
            // LOCAL PATCH (fork): the padding was read without a bounds check, so
            // a block whose data ended the input trapped (security audit
            // 2026-11-15, W10).
            guard byteReader.bytesLeft >= paddingSize
                else { throw XZError.wrongPadding }
            for _ in 0..<paddingSize {
                let byte = byteReader.byte()
                guard byte == 0x00
                    else { throw XZError.wrongPadding }
            }
        }

        self.data = out.data
        self.unpaddedSize = unpaddedSize + checkSize
    }

}
