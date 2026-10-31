// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

class SevenZipPackInfo {

    let packPosition: Int
    let numPackStreams: Int
    private(set) var packSizes = [Int]()
    private(set) var digests = [UInt32?]()

    init(_ bitReader: MsbBitReader) throws {
        packPosition = try bitReader.szMbd()
        numPackStreams = try bitReader.szMbd()

        var type = try bitReader.szByte()

        if type == 0x09 {
            for _ in 0..<numPackStreams {
                packSizes.append(try bitReader.szMbd())
            }
            type = try bitReader.szByte()
        }

        if type == 0x0A {
            let definedBits = try bitReader.defBits(count: numPackStreams)
            bitReader.align()

            for bit in definedBits {
                if bit == 1 {
                    digests.append(try bitReader.szUint32())
                } else {
                    digests.append(nil)
                }
            }

            type = try bitReader.szByte()
        }

        guard type == 0x00
            else { throw SevenZipError.internalStructureError }
    }

}
