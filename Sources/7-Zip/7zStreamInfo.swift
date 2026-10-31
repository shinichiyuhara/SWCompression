// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

class SevenZipStreamInfo {

    var packInfo: SevenZipPackInfo?
    var coderInfo: SevenZipCoderInfo
    var substreamInfo: SevenZipSubstreamInfo?

    init(_ bitReader: MsbBitReader) throws {
        var type = try bitReader.szByte()

        if type == 0x06 {
            packInfo = try SevenZipPackInfo(bitReader)
            type = try bitReader.szByte()
        }

        if type == 0x07 {
            coderInfo = try SevenZipCoderInfo(bitReader)
            type = try bitReader.szByte()
        } else {
            coderInfo = SevenZipCoderInfo()
        }

        if type == 0x08 {
            substreamInfo = try SevenZipSubstreamInfo(bitReader, coderInfo)
            type = try bitReader.szByte()
        }

        guard type == 0x00
            else { throw SevenZipError.internalStructureError }
    }

}
