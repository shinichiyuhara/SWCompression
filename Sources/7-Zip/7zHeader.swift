// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

class SevenZipHeader {

    var archiveProperties: [SevenZipProperty]?
    var additionalStreams: SevenZipStreamInfo?
    var mainStreams: SevenZipStreamInfo?
    var fileInfo: SevenZipFileInfo?

    init(_ bitReader: MsbBitReader) throws {
        var type = bitReader.byte()

        if type == 0x02 {
            archiveProperties = try SevenZipProperty.getProperties(bitReader)
            type = bitReader.byte()
        }

        if type == 0x03 {
            throw SevenZipError.additionalStreamsNotSupported
        }

        if type == 0x04 {
            mainStreams = try SevenZipStreamInfo(bitReader)
            type = bitReader.byte()
        }

        if type == 0x05 {
            fileInfo = try SevenZipFileInfo(bitReader)
            type = bitReader.byte()
        }

        guard type == 0x00
            else { throw SevenZipError.internalStructureError }
    }

    convenience init(_ bitReader: MsbBitReader, using streamInfo: SevenZipStreamInfo) throws {
        // All three lookups below index arrays that a corrupt header can leave
        // empty, and the offset/size can point outside the buffer — each an
        // uncatchable trap. Validate before use.
        guard let packInfo = streamInfo.packInfo,
              !streamInfo.coderInfo.folders.isEmpty,
              !packInfo.packSizes.isEmpty
            else { throw SevenZipError.internalStructureError }
        let folder = streamInfo.coderInfo.folders[0]

        let folderOffset = SevenZipContainer.signatureHeaderSize + packInfo.packPosition
        let packSize = packInfo.packSizes[0]
        guard folderOffset >= 0, packSize >= 0,
              folderOffset <= bitReader.size,
              packSize <= bitReader.size - folderOffset
            else { throw SevenZipError.internalStructureError }
        bitReader.offset = folderOffset

        let packedHeaderData = Data(bitReader.bytes(count: packSize))
        let headerData = try folder.unpack(data: packedHeaderData)

        guard headerData.count == folder.unpackSize()
            else { throw SevenZipError.wrongSize }
        if let crc = folder.crc {
            guard CheckSums.crc32(headerData) == crc
                else { throw SevenZipError.wrongCRC }
        }

        let headerBitReader = MsbBitReader(data: headerData)

        guard headerBitReader.byte() == 0x01
            else { throw SevenZipError.internalStructureError }
        try self.init(headerBitReader)
    }

}
