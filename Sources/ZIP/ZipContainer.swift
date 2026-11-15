// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

/// Provides functions for work with ZIP containers.
public class ZipContainer: Container {

    /**
     Contains user-defined extra fields. When either `ZipContainer.info(container:)` or `ZipContainer.open(container:)`
     function encounters extra field without built-in support, it uses this dictionary and tries to find a corresponding
     user-defined extra field. If an approriate custom extra field is found and successfully processed, then the result
     is stored in `ZipEntryInfo.customExtraFields`.

     To enable support of custom extra field one must add a new entry to this dictionary. The value of this entry must
     be a user-defined type which conforms to `ZipExtraField` protocol. The key must be equal to the ID of user-defined
     extra field and type's `id` property.

     - Warning: Modifying this dictionary while either `info(container:)` or `open(container:)` function is being
     executed may cause undefined behavior.
     */
    public static var customExtraFields = [UInt16: ZipExtraField.Type]()

    /**
     Processes ZIP container and returns an array of `ZipEntry` with information and data for all entries.

     - Important: The order of entries is defined by ZIP container and, particularly, by the creator of a given ZIP
     container. It is likely that directories will be encountered earlier than files stored in those directories, but no
     particular order is guaranteed.

     - Parameter container: ZIP container's data.

     - Throws: `ZipError` or any other error associated with compression type, depending on the type of the problem.
     It may indicate that either container is damaged or it might not be ZIP container at all.

     - Returns: Array of `ZipEntry`.
     */
    public static func open(container data: Data) throws -> [ZipEntry] {
        let data = data.zeroBased // LOCAL PATCH (fork): W39
        return try open(data, limit: .max)
    }

    /**
     LOCAL PATCH (fork). Opens the ZIP container in `data`, as `open(container:)` does, refusing to produce more than
     `limit` bytes of entry data in all.

     Each entry is decoded up to the size the central directory declares for it (the size `info()` reports) and no
     further, so the sum of `info()` sizes bounds what `open` produces either way; `limit` checks that sum before any
     entry is decoded (security audit 2026-11-15, W17).

     - Throws: as `open(container:)` does, or `DecompressionLimitExceeded` when the declared sizes add up to more than
     `limit`.
     */
    public static func open(container data: Data, limit: Int) throws -> [ZipEntry] {
        try open(data.zeroBased, limit: limit)
    }

    private static func open(_ data: Data, limit: Int) throws -> [ZipEntry] {
        let helpers = try infoWithHelper(data)
        var entries = [ZipEntry]()

        var declared = 0
        for helper in helpers where helper.entryInfo.type != .directory {
            guard helper.uncompSize <= limit - declared
                else { throw DecompressionLimitExceeded(limit: limit) }
            declared += helper.uncompSize
        }

        for helper in helpers {
            if helper.entryInfo.type == .directory {
                entries.append(ZipEntry(helper.entryInfo, nil))
            } else {
                let entryDataResult = try ZipContainer.getEntryData(data, helper)
                entries.append(ZipEntry(helper.entryInfo, entryDataResult.data))
                guard !entryDataResult.crcError
                    else { throw ZipError.wrongCRC(entries) }
            }
        }

        return entries
    }

    private static func getEntryData(_ data: Data, _ helper: ZipEntryInfoHelper) throws -> (data: Data, crcError: Bool) {
        // LOCAL PATCH (fork): the decoder sees only the entry's compressed bytes
        // (checked to be in the input when the entry was read) and may produce
        // only the size the central directory declares. Deflate and BZip2 ran
        // to the end of their stream whatever the size said, and the stored
        // method copied a local-header size from anywhere (security audit
        // 2026-11-15, W16, W17).
        let uncompSize = helper.uncompSize
        let compSize = helper.compSize
        let compressed = Data(data[helper.dataOffset..<helper.dataOffset + compSize])

        let fileData: Data
        let realCompSize: Int
        do {
            switch helper.entryInfo.compressionMethod {
            case .copy:
                guard compSize == uncompSize
                    else { throw ZipError.wrongSize }
                fileData = compressed
                realCompSize = compSize
            case .deflate:
                let bitReader = LsbBitReader(data: compressed)
                fileData = try Deflate.decompress(bitReader, limit: uncompSize)
                // Sometimes bitReader is misaligned after Deflate decompression, so we need to align before getting
                // end index back.
                bitReader.align()
                realCompSize = bitReader.offset
            case .bzip2:
                // BZip2 algorithm uses different bit numbering scheme.
                let bitReader = MsbBitReader(data: compressed)
                fileData = try BZip2.decompress(bitReader, limit: uncompSize)
                // Sometimes bitReader is misaligned after BZip2 decompression, so we need to align before getting end
                // index back.
                bitReader.align()
                realCompSize = bitReader.offset
            case .lzma:
                // LZMA SDK version (2 bytes), size of properties (2 bytes, always 5), then the properties.
                let byteReader = LittleEndianByteReader(data: compressed)
                try byteReader.zipNeed(9)
                byteReader.offset += 2
                guard byteReader.uint16() == 5
                    else { throw LZMAError.wrongProperties }
                fileData = try LZMA.decompress(byteReader, LZMAProperties(byteReader), uncompSize, limit: uncompSize)
                realCompSize = byteReader.offset
            default:
                throw ZipError.compressionNotSupported
            }
        } catch is OutputLimitExceeded {
            throw ZipError.wrongSize
        }
        guard compSize == realCompSize && uncompSize == fileData.count
            else { throw ZipError.wrongSize }

        if helper.hasDataDescriptor {
            // Now we need to parse data descriptor itself.
            // LOCAL PATCH (fork): its values must match the central directory's,
            // which `info()` reports and the data was just checked against. They
            // used to replace them silently, so `open` could return far more than
            // `info()` promised with a matching CRC (security audit 2026-11-15,
            // W22).
            let byteReader = LittleEndianByteReader(data: data)
            byteReader.offset = helper.dataOffset + compSize
            let fieldsSize = helper.zip64FieldsArePresent ? 20 : 12
            try byteReader.zipNeed(fieldsSize)
            // First, it might or might not have signature.
            if byteReader.uint32() == 0x08074b50 {
                try byteReader.zipNeed(fieldsSize)
            } else {
                byteReader.offset -= 4
            }
            let descriptorCRC = byteReader.uint32()
            let descriptorCompSize: UInt64
            let descriptorUncompSize: UInt64
            if helper.zip64FieldsArePresent {
                descriptorCompSize = byteReader.uint64()
                descriptorUncompSize = byteReader.uint64()
            } else {
                descriptorCompSize = byteReader.uint64(fromBytes: 4)
                descriptorUncompSize = byteReader.uint64(fromBytes: 4)
            }
            guard descriptorCRC == helper.entryInfo.crc,
                  descriptorCompSize == UInt64(compSize),
                  descriptorUncompSize == UInt64(uncompSize)
                else { throw ZipError.wrongLocalHeader }
        }

        let crcError = helper.entryInfo.crc != CheckSums.crc32(fileData)

        return (fileData, crcError)
    }

    /**
     Processes ZIP container and returns an array of `ZipEntryInfo` with information about entries in this container.

     - Important: The order of entries is defined by ZIP container and, particularly, by the creator of a given ZIP
     container. It is likely that directories will be encountered earlier than files stored in those directories, but no
     particular order is guaranteed.

     - Parameter container: ZIP container's data.

     - Throws: `ZipError`, which may indicate that either container is damaged or it might not be ZIP container at all.

     - Returns: Array of `ZipEntryInfo`.
     */
    public static func info(container data: Data) throws -> [ZipEntryInfo] {
        let data = data.zeroBased // LOCAL PATCH (fork): W39
        return try infoWithHelper(data).map { $0.entryInfo }
    }

    private static func infoWithHelper(_ data: Data) throws -> [ZipEntryInfoHelper] {
        // Valid ZIP container must contain at least an End of Central Directory record, which is at least 22 bytes long.
        guard data.count >= 22
            else { throw ZipError.notFoundCentralDirectoryEnd }

        let byteReader = LittleEndianByteReader(data: data)
        var entries = [ZipEntryInfoHelper]()

        // First, we are looking for End of Central Directory record, specifically, for its signature.
        // LOCAL PATCH (fork): only in the last 22 + 65,535 bytes, where the
        // record must be (its comment is at most 65,535 bytes); the search went
        // back byte by byte to the start of any input (security audit
        // 2026-11-15, W37). The first signature found from the end was taken,
        // which may be bytes inside the real record's comment, read as another
        // directory than other tools use (W36). Now, as libarchive does, a
        // record is ranked: best when its comment ends the input and its central
        // directory ends where it starts (or defers to ZIP64), then when its
        // comment ends the input, then when its comment fits. Within a rank the
        // last one wins.
        func le(_ at: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | Int(data[at + $1]) << (8 * $1) }
        }
        let lowestStart = max(0, data.count - 22 - 0xFFFF)
        var best: (rank: Int, start: Int)?
        var start = data.count - 22
        while start >= lowestStart {
            if data[start] == 0x50 && data[start + 1] == 0x4b && data[start + 2] == 0x05 && data[start + 3] == 0x06 {
                let commentEnd = start + 22 + le(start + 20, 2)
                let cdSize = le(start + 12, 4)
                let cdOffset = le(start + 16, 4)
                let consistent = cdOffset + cdSize == start || cdOffset == 0xFFFF_FFFF || cdSize == 0xFFFF_FFFF
                let rank = commentEnd == data.count ? (consistent ? 3 : 2) : (commentEnd < data.count ? 1 : 0)
                if rank > (best?.rank ?? 0) {
                    best = (rank, start)
                    if rank == 3 { break }
                }
            }
            start -= 1
        }
        guard let recordStart = best?.start
            else { throw ZipError.notFoundCentralDirectoryEnd }
        byteReader.offset = recordStart + 4

        // Then we are reading End of Central Directory record.
        let endOfCD = try ZipEndOfCentralDirectory(byteReader)
        let cdEntries = endOfCD.cdEntries

        // Now we are ready to read Central Directory itself.
        // But first, we should check for "Archive extra data record" and skip it if present.
        // LOCAL PATCH (fork): the offsets must be in the input (W16, W23).
        let cdOffset = try LittleEndianByteReader.zipInt(endOfCD.cdOffset)
        guard cdOffset <= byteReader.size
            else { throw ZipError.wrongSize }
        byteReader.offset = cdOffset
        if byteReader.bytesLeft >= 8 && byteReader.uint32() == 0x08064b50 {
            let recordLength = byteReader.int(fromBytes: 4)
            try byteReader.zipNeed(recordLength)
            byteReader.offset += recordLength
        } else {
            byteReader.offset = cdOffset
        }

        for _ in 0..<cdEntries {
            let entry = try ZipEntryInfoHelper(byteReader, endOfCD.currentDiskNumber)
            entries.append(entry)
            // Move to the next Central Directory entry.
            byteReader.offset = entry.nextCdEntryOffset
        }

        // LOCAL PATCH (fork): entries must not share bytes. Many central
        // directory entries pointing at one local header made `open` decode the
        // same data once per entry, an amplification `info()` sizes do not show
        // (security audit 2026-11-15, W17).
        let regions = entries.map { ($0.localHeaderOffset, $0.dataOffset + $0.compSize) }.sorted { $0.0 < $1.0 }
        for i in regions.indices.dropFirst() {
            guard regions[i].0 >= regions[i - 1].1
                else { throw ZipError.wrongLocalHeader }
        }

        return entries
    }

}
