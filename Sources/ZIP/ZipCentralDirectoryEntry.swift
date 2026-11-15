// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

struct ZipCentralDirectoryEntry {

    let versionMadeBy: UInt16
    let versionNeeded: UInt16
    let generalPurposeBitFlags: UInt16
    let compressionMethod: UInt16
    let lastModFileTime: UInt16
    let lastModFileDate: UInt16
    let crc32: UInt32
    private(set) var compSize: UInt64
    private(set) var uncompSize: UInt64

    let fileName: String
    /// LOCAL PATCH (fork): the name's bytes as stored, before decoding and before
    /// any Unicode Path field; compared with the local header's.
    let rawFileName: Data
    let fileComment: String

    private(set) var diskNumberStart: UInt32

    let internalFileAttributes: UInt16
    let externalFileAttributes: UInt32

    private(set) var localHeaderOffset: UInt64

    // 0x5455 extra field.
    private(set) var extendedTimestampExtraField: ExtendedTimestampExtraField?

    /// 0x000a extra field.
    private(set) var ntfsExtraField: NtfsExtraField?

    // 0x7855 extra field doesn't have any information in Central Directory.

    /// 0x7875 extra field.
    private(set) var infoZipNewUnixExtraField: InfoZipNewUnixExtraField?

    let customExtraFields: [ZipExtraField]

    let nextEntryOffset: Int

    init(_ byteReader: LittleEndianByteReader) throws {
        // LOCAL PATCH (fork): the fixed part is 46 bytes (W16).
        try byteReader.zipNeed(46)
        // Check signature.
        guard byteReader.uint32() == 0x02014b50
            else { throw ZipError.wrongSignature }

        self.versionMadeBy = byteReader.uint16()
        self.versionNeeded = byteReader.uint16()

        self.generalPurposeBitFlags = byteReader.uint16()
        let useUtf8 = generalPurposeBitFlags & 0x800 != 0

        self.compressionMethod = byteReader.uint16()

        self.lastModFileTime = byteReader.uint16()
        self.lastModFileDate = byteReader.uint16()

        self.crc32 = byteReader.uint32()

        self.compSize = byteReader.uint64(fromBytes: 4)
        self.uncompSize = byteReader.uint64(fromBytes: 4)

        let fileNameLength = byteReader.int(fromBytes: 2)
        let extraFieldLength = byteReader.int(fromBytes: 2)
        let fileCommentLength = byteReader.int(fromBytes: 2)

        self.diskNumberStart = byteReader.uint32(fromBytes: 2)

        self.internalFileAttributes = byteReader.uint16()
        self.externalFileAttributes = byteReader.uint32()

        self.localHeaderOffset = byteReader.uint64(fromBytes: 4)

        // LOCAL PATCH (fork): the name, extra fields and comment must be in the
        // input (W16).
        try byteReader.zipNeed(fileNameLength + extraFieldLength + fileCommentLength)
        let rawFileName = Data(byteReader.data[byteReader.offset..<byteReader.offset + fileNameLength])
        guard let fileName = byteReader.zipString(fileNameLength, useUtf8)
            else { throw ZipError.wrongTextField }
        self.rawFileName = rawFileName

        var uncompSize = self.uncompSize
        var compSize = self.compSize
        var localHeaderOffset = self.localHeaderOffset
        var diskNumberStart = self.diskNumberStart
        var extendedTimestampExtraField: ExtendedTimestampExtraField?
        var ntfsExtraField: NtfsExtraField?
        var infoZipNewUnixExtraField: InfoZipNewUnixExtraField?
        var unicodePath: String?
        self.customExtraFields = try ZipContainer.readExtraFields(byteReader, length: extraFieldLength,
                                                                  location: .centralDirectory) { headerID, size in
            // There are a lot of possible extra fields.
            switch headerID {
            case 0x0001: // Zip64
                // Zip64 extra field is a special case, because it requires knowledge about central directory fields.
                // LOCAL PATCH (fork): each value is present only if its field above
                // is all ones, and only if the extra field holds it (W24).
                var left = size
                func next(_ count: Int) throws {
                    guard left >= count else { throw ZipError.wrongSize }
                    left -= count
                }
                if uncompSize == 0xFFFFFFFF {
                    try next(8)
                    uncompSize = byteReader.uint64()
                }
                if compSize == 0xFFFFFFFF {
                    try next(8)
                    compSize = byteReader.uint64()
                }
                if localHeaderOffset == 0xFFFFFFFF {
                    try next(8)
                    localHeaderOffset = byteReader.uint64()
                }
                if diskNumberStart == 0xFFFF {
                    try next(4)
                    diskNumberStart = byteReader.uint32()
                }
            case 0x5455: // Extended Timestamp
                extendedTimestampExtraField = ExtendedTimestampExtraField(byteReader, size, location: .centralDirectory)
            case 0x000a: // NTFS Extra Fields
                ntfsExtraField = NtfsExtraField(byteReader, size, location: .centralDirectory)
            case 0x7855: // Info-ZIP Unix Extra Field
                // If there is any data for Info-ZIP Unix extra field in central directory (`size != 0`), skip it.
                // However, according to definition of this extra field it shouldn't have any data in CD.
                break
            case 0x7875: // Info-ZIP New Unix Extra Field
                infoZipNewUnixExtraField = InfoZipNewUnixExtraField(byteReader, size, location: .centralDirectory)
            case 0x7075: // Info-ZIP Unicode Path
                // LOCAL PATCH (fork): Info-ZIP, 7-Zip and libarchive show this
                // UTF-8 name when its CRC matches the plain name's bytes; this
                // reader showed the plain name, another name than they do (W36).
                if size >= 5, byteReader.byte() == 1 {
                    let nameCRC = byteReader.uint32()
                    if nameCRC == CheckSums.crc32(rawFileName) {
                        unicodePath = String(data: Data(byteReader.bytes(count: size - 5)), encoding: .utf8)
                    }
                }
            default:
                return false
            }
            return true
        }
        self.fileName = unicodePath ?? fileName
        self.uncompSize = uncompSize
        self.compSize = compSize
        self.localHeaderOffset = localHeaderOffset
        self.diskNumberStart = diskNumberStart
        self.extendedTimestampExtraField = extendedTimestampExtraField
        self.ntfsExtraField = ntfsExtraField
        self.infoZipNewUnixExtraField = infoZipNewUnixExtraField

        guard let fileComment = byteReader.zipString(fileCommentLength, useUtf8)
            else { throw ZipError.wrongTextField }
        self.fileComment = fileComment

        self.nextEntryOffset = byteReader.offset
    }

}
