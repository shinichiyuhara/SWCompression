// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

class SevenZipSubstreamInfo {

    var numUnpackStreamsInFolders = [Int]()
    var unpackSizes = [Int]()
    var digests = [UInt32?]()

    init(_ bitReader: MsbBitReader, _ coderInfo: SevenZipCoderInfo) throws {
        var totalUnpackStreams = coderInfo.folders.count

        var type = try bitReader.szByte()

        if type == 0x0D {
            totalUnpackStreams = 0
            for folder in coderInfo.folders {
                let numStreams = try bitReader.szMbd()
                folder.numUnpackSubstreams = numStreams
                let (total, overflow) = totalUnpackStreams.addingReportingOverflow(numStreams)
                guard !overflow else { throw SevenZipError.internalStructureError }
                totalUnpackStreams = total
            }
            type = try bitReader.szByte()
        }

        for folder in coderInfo.folders {
            if folder.numUnpackSubstreams == 0 {
                continue
            }
            var sum = 0
            if type == 0x09 {
                for _ in 0..<folder.numUnpackSubstreams - 1 {
                    let size = try bitReader.szMbd()
                    unpackSizes.append(size)
                    let (newSum, overflow) = sum.addingReportingOverflow(size)
                    guard !overflow else { throw SevenZipError.internalStructureError }
                    sum = newSum
                }
            }
            // The last substream's size is what remains; substreams that
            // already claim more than the folder holds leave a negative size,
            // which traps once it is used to slice the output.
            guard sum <= folder.unpackSize()
                else { throw SevenZipError.internalStructureError }
            unpackSizes.append(folder.unpackSize() - sum)
        }
        if type == 0x09 {
            type = try bitReader.szByte()
        }

        var totalDigests = 0
        for folder in coderInfo.folders {
            if folder.numUnpackSubstreams != 1 || folder.crc == nil {
                let (total, overflow) = totalDigests.addingReportingOverflow(folder.numUnpackSubstreams)
                guard !overflow else { throw SevenZipError.internalStructureError }
                totalDigests = total
            }
        }

        if type == 0x0A {
            let definedBits = try bitReader.defBits(count: totalDigests)
            bitReader.align()

            var missingCrcs = [UInt32?]()
            for i in 0..<totalDigests {
                if definedBits[i] == 1 {
                    missingCrcs.append(try bitReader.szUint32())
                } else {
                    missingCrcs.append(nil)
                }
            }

            var nextMissingCrc = 0
            for folder in coderInfo.folders {
                if folder.numUnpackSubstreams == 1 && folder.crc != nil {
                    digests.append(folder.crc)
                } else {
                    for _ in 0..<folder.numUnpackSubstreams {
                        digests.append(missingCrcs[nextMissingCrc])
                        nextMissingCrc += 1
                    }
                }
            }

            type = try bitReader.szByte()
        }

        guard type == 0x00
            else { throw SevenZipError.internalStructureError }
    }

}
