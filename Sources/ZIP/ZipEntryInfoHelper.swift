// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

/**
 The purpose of this struct is to accompany `ZipEntryInfo` instances while processing a `ZipContainer` and to store
 information which is necessary for reading entry's data later.
 */
struct ZipEntryInfoHelper {

    let entryInfo: ZipEntryInfo

    let hasDataDescriptor: Bool
    let zip64FieldsArePresent: Bool
    let nextCdEntryOffset: Int
    let localHeaderOffset: Int
    let dataOffset: Int
    /// LOCAL PATCH (fork): the central directory's sizes — what `info()` reports
    /// — checked to be representable and, for the compressed size, present in
    /// the input (security audit 2026-11-15, W16, W22, W23).
    let compSize: Int
    let uncompSize: Int

    init(_ byteReader: LittleEndianByteReader, _ currentDiskNumber: UInt32) throws {
        // Read Central Directory entry.
        let cdEntry = try ZipCentralDirectoryEntry(byteReader)

        // Move to the location of Local Header.
        // LOCAL PATCH (fork): checked (W16, W23).
        let localHeaderOffset = try LittleEndianByteReader.zipInt(cdEntry.localHeaderOffset)
        guard localHeaderOffset <= byteReader.size
            else { throw ZipError.wrongSize }
        self.localHeaderOffset = localHeaderOffset
        byteReader.offset = localHeaderOffset
        // Read Local Header.
        let localHeader = try ZipLocalHeader(byteReader)
        try localHeader.validate(with: cdEntry, currentDiskNumber)

        // If file has data descriptor, then some properties are only present in CD entry.
        self.hasDataDescriptor = localHeader.generalPurposeBitFlags & 0x08 != 0

        // Save some properties from CD entry and Local Header.
        // LOCAL PATCH (fork): the central directory's sizes in both cases; without
        // a data descriptor `validate` has checked that the local header agrees.
        let compSize = try LittleEndianByteReader.zipInt(cdEntry.compSize)
        let uncompSize = try LittleEndianByteReader.zipInt(cdEntry.uncompSize)
        guard compSize <= byteReader.size - localHeader.dataOffset
            else { throw ZipError.wrongSize }
        self.compSize = compSize
        self.uncompSize = uncompSize

        self.entryInfo = ZipEntryInfo(byteReader, cdEntry, localHeader, hasDataDescriptor, size: uncompSize)

        self.zip64FieldsArePresent = localHeader.zip64FieldsArePresent
        self.nextCdEntryOffset = cdEntry.nextEntryOffset
        self.dataOffset = localHeader.dataOffset
    }

}
