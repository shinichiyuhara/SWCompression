// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

class SevenZipCoderInfo {

    let numFolders: Int

    let external: UInt8
    private(set) var folders = [SevenZipFolder]()

    init() {
        numFolders = 0
        external = 0
    }

    init(_ bitReader: MsbBitReader) throws {
        var type = try bitReader.szByte()
        guard type == 0x0B else { throw SevenZipError.internalStructureError }

        numFolders = try bitReader.szMbd()
        // LOCAL PATCH (fork): each folder is a class with coder arrays,
        // hundreds of bytes per few header bytes (security audit 2026-11-15, W12).
        guard numFolders <= SevenZipLimits.maxFolders
            else { throw SevenZipError.internalStructureError }
        external = try bitReader.szByte()

        guard external == 0
            else { throw SevenZipError.externalNotSupported }

        for _ in 0..<numFolders {
            folders.append(try SevenZipFolder(bitReader))
        }

        type = try bitReader.szByte()
        guard type == 0x0C else { throw SevenZipError.internalStructureError }

        for folder in folders {
            for _ in 0..<folder.totalOutputStreams {
                folder.unpackSizes.append(try bitReader.szMbd())
            }
        }

        type = try bitReader.szByte()

        if type == 0x0A {
            let definedBits = try bitReader.defBits(count: numFolders)
            bitReader.align()

            for i in 0..<numFolders where definedBits[i] == 1 {
                folders[i].crc = try bitReader.szUint32()
            }

            type = try bitReader.szByte()
        }

        guard type == 0x00
            else { throw SevenZipError.internalStructureError }
    }
}
