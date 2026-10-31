// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

class SevenZipCoder {

    let idSize: Int
    let isComplex: Bool
    let hasAttributes: Bool

    let id: [UInt8]
    let compressionMethod: CompressionMethod
    let isEncryptionMethod: Bool

    let numInStreams: Int
    let numOutStreams: Int

    var propertiesSize: Int?
    var properties: [UInt8]?

    init(_ bitReader: MsbBitReader) throws {
        let flags = try bitReader.szByte()
        guard flags & 0xC0 == 0
            else { throw SevenZipError.internalStructureError }
        idSize = (flags & 0x0F).toInt()
        isComplex = flags & 0x10 != 0
        hasAttributes = flags & 0x20 != 0

        // A coder id is 1–15 bytes; it must be present and non-empty (id[0] is
        // read below, which traps on an empty array).
        guard idSize >= 1, idSize <= bitReader.bytesLeft
            else { throw SevenZipError.internalStructureError }
        id = try bitReader.szBytes(count: idSize)
        compressionMethod = CompressionMethod(id)
        isEncryptionMethod = id[0] == 0x06

        numInStreams = isComplex ? try bitReader.szMbd() : 1
        numOutStreams = isComplex ? try bitReader.szMbd() : 1

        if hasAttributes {
            let size = try bitReader.szMbd()
            // `size` is taken from the header; larger than what remains would
            // make bytes(count:) read past the buffer and trap.
            guard size >= 0, size <= bitReader.bytesLeft
                else { throw SevenZipError.internalStructureError }
            propertiesSize = size
            properties = try bitReader.szBytes(count: size)
        }
    }

}
