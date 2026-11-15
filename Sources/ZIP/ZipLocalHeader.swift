// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

struct ZipLocalHeader {

    let versionNeeded: UInt16
    let generalPurposeBitFlags: UInt16
    let compressionMethod: UInt16
    let lastModFileTime: UInt16
    let lastModFileDate: UInt16

    let crc32: UInt32
    private(set) var compSize: UInt64
    private(set) var uncompSize: UInt64

    private(set) var zip64FieldsArePresent: Bool = false

    let fileName: String
    /// LOCAL PATCH (fork): the name's bytes as stored.
    let rawFileName: Data

    /// 0x5455 extra field.
    private(set) var extendedTimestampExtraField: ExtendedTimestampExtraField?

    /// 0x000a extra field.
    private(set) var ntfsExtraField: NtfsExtraField?

    /// 0x7855 extra field.
    private(set) var infoZipUnixExtraField: InfoZipUnixExtraField?

    /// 0x7875 extra field.
    private(set) var infoZipNewUnixExtraField: InfoZipNewUnixExtraField?

    let customExtraFields: [ZipExtraField]

    let dataOffset: Int

    init(_ byteReader: LittleEndianByteReader) throws {
        // LOCAL PATCH (fork): the fixed part is 30 bytes (W16).
        try byteReader.zipNeed(30)
        // Check signature.
        guard byteReader.uint32() == 0x04034b50
            else { throw ZipError.wrongSignature }

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

        // LOCAL PATCH (fork): the name and extra fields must be in the input (W16).
        try byteReader.zipNeed(fileNameLength + extraFieldLength)
        self.rawFileName = Data(byteReader.data[byteReader.offset..<byteReader.offset + fileNameLength])
        guard let fileName = byteReader.zipString(fileNameLength, useUtf8)
            else { throw ZipError.wrongTextField }
        self.fileName = fileName

        var uncompSize = self.uncompSize
        var compSize = self.compSize
        var zip64FieldsArePresent = false
        var extendedTimestampExtraField: ExtendedTimestampExtraField?
        var ntfsExtraField: NtfsExtraField?
        var infoZipUnixExtraField: InfoZipUnixExtraField?
        var infoZipNewUnixExtraField: InfoZipNewUnixExtraField?
        self.customExtraFields = try ZipContainer.readExtraFields(byteReader, length: extraFieldLength,
                                                                  location: .localHeader) { headerID, size in
            // There are a lot of possible extra fields.
            switch headerID {
            case 0x0001: // Zip64
                // Zip64 extra field is a special case, because it requires knowledge about local header fields,
                // in particular, uncompressed and compressed sizes.
                // In the local header both uncompressed size and compressed size fields are required.
                // LOCAL PATCH (fork): read both when the field holds both (as the
                // format requires); otherwise only those marked all ones, and only
                // as far as the field goes (W24). Its presence alone says that a
                // data descriptor has 8-byte sizes.
                zip64FieldsArePresent = true
                if size >= 16 {
                    uncompSize = byteReader.uint64()
                    compSize = byteReader.uint64()
                } else {
                    var left = size
                    if uncompSize == 0xFFFFFFFF {
                        guard left >= 8 else { throw ZipError.wrongSize }
                        uncompSize = byteReader.uint64()
                        left -= 8
                    }
                    if compSize == 0xFFFFFFFF {
                        guard left >= 8 else { throw ZipError.wrongSize }
                        compSize = byteReader.uint64()
                    }
                }
            case 0x5455: // Extended Timestamp
                extendedTimestampExtraField = ExtendedTimestampExtraField(byteReader, size, location: .localHeader)
            case 0x000a: // NTFS Extra Fields
                ntfsExtraField = NtfsExtraField(byteReader, size, location: .localHeader)
            case 0x7855: // Info-ZIP Unix Extra Field
                infoZipUnixExtraField = InfoZipUnixExtraField(byteReader, size, location: .localHeader)
            case 0x7875: // Info-ZIP New Unix Extra Field
                infoZipNewUnixExtraField = InfoZipNewUnixExtraField(byteReader, size, location: .localHeader)
            default:
                return false
            }
            return true
        }
        self.uncompSize = uncompSize
        self.compSize = compSize
        self.zip64FieldsArePresent = zip64FieldsArePresent
        self.extendedTimestampExtraField = extendedTimestampExtraField
        self.ntfsExtraField = ntfsExtraField
        self.infoZipUnixExtraField = infoZipUnixExtraField
        self.infoZipNewUnixExtraField = infoZipNewUnixExtraField

        self.dataOffset = byteReader.offset
    }

    func validate(with cdEntry: ZipCentralDirectoryEntry, _ currentDiskNumber: UInt32) throws {
        // Check Local Header for unsupported features.
        guard self.versionNeeded & 0xFF <= 63
            else { throw ZipError.wrongVersion }
        guard self.generalPurposeBitFlags & 0x2000 == 0 &&
            self.generalPurposeBitFlags & 0x40 == 0 &&
            self.generalPurposeBitFlags & 0x01 == 0
            else { throw ZipError.encryptionNotSupported }
        guard self.generalPurposeBitFlags & 0x20 == 0
            else { throw ZipError.patchingNotSupported }

        // Check Central Directory record for unsupported features.
        guard cdEntry.versionNeeded & 0xFF <= 63
            else { throw ZipError.wrongVersion }
        guard cdEntry.diskNumberStart == currentDiskNumber
            else { throw ZipError.multiVolumesNotSupported }

        // Check if Local Header is consistent with Central Directory record.
        // LOCAL PATCH (fork): the name too, and — without a data descriptor —
        // the sizes and CRC. Readers that stream through local headers (and
        // `open`, which decoded by the local sizes) saw another entry than
        // `info()`, which reports the central directory's (security audit
        // 2026-11-15, W36).
        guard self.rawFileName == cdEntry.rawFileName
            else { throw ZipError.wrongLocalHeader }
        if self.generalPurposeBitFlags & 0x08 == 0 {
            guard self.crc32 == cdEntry.crc32 &&
                self.compSize == cdEntry.compSize &&
                self.uncompSize == cdEntry.uncompSize
                else { throw ZipError.wrongLocalHeader }
        }
        guard self.generalPurposeBitFlags == cdEntry.generalPurposeBitFlags &&
            self.compressionMethod == cdEntry.compressionMethod &&
            self.lastModFileTime == cdEntry.lastModFileTime &&
            self.lastModFileDate == cdEntry.lastModFileDate
            else { throw ZipError.wrongLocalHeader }
    }

}
