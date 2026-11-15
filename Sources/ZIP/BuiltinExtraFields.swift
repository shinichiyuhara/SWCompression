// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

// LOCAL PATCH (fork): each built-in field is now handed a reader over its own
// `size` bytes, and reads only what is there. They read fixed amounts whatever
// the field's length said, taking the next field, the comment or the file data
// as times and ids, or reading past the end of the input (security audit
// 2026-11-15, W24). A field too short for its contents is ignored.

struct ExtendedTimestampExtraField: ZipExtraField {

    static let id: UInt16 = 0x5455

    let size: Int
    let location: ZipExtraFieldLocation

    var atime: UInt32?
    var ctime: UInt32?
    var mtime: UInt32?

    init(_ byteReader: LittleEndianByteReader, _ size: Int, location: ZipExtraFieldLocation) {
        let endOffset = byteReader.offset + size
        self.size = size
        self.location = location
        let bytesLeft = { endOffset - byteReader.offset }
        if bytesLeft() >= 1 {
            let flags = byteReader.byte()
            if flags & 0x01 != 0 && bytesLeft() >= 4 {
                self.mtime = byteReader.uint32()
            }
            if location == .localHeader {
                if flags & 0x02 != 0 && bytesLeft() >= 4 {
                    self.atime = byteReader.uint32()
                }
                if flags & 0x04 != 0 && bytesLeft() >= 4 {
                    self.ctime = byteReader.uint32()
                }
            }
        }
        // This is a workaround for non well-formed extra field present in Central Directory of ZIP files created
        // by Finder in some versions of macOS.
        byteReader.offset = endOffset
    }

}

struct NtfsExtraField: ZipExtraField {

    static let id: UInt16 = 0x000A

    let size: Int
    let location: ZipExtraFieldLocation

    let atime: UInt64
    let ctime: UInt64
    let mtime: UInt64

    init?(_ byteReader: LittleEndianByteReader, _ size: Int, location: ZipExtraFieldLocation) {
        self.size = size
        self.location = location
        guard size >= 32
            else { return nil }
        byteReader.offset += 4 // Skip reserved bytes
        let tag = byteReader.uint16() // This attribute's tag
        byteReader.offset += 2 // Skip size of this attribute
        guard tag == 0x0001
            else { return nil }
        self.mtime = byteReader.uint64()
        self.atime = byteReader.uint64()
        self.ctime = byteReader.uint64()
    }

}

struct InfoZipUnixExtraField: ZipExtraField {

    static let id: UInt16 = 0x7855

    let size: Int
    let location: ZipExtraFieldLocation

    let uid: Int
    let gid: Int

    init?(_ byteReader: LittleEndianByteReader, _ size: Int, location: ZipExtraFieldLocation) {
        self.size = size
        self.location = location
        switch location {
        case .centralDirectory:
            return nil
        case .localHeader:
            guard size >= 4
                else { return nil }
            self.uid = byteReader.int(fromBytes: 2)
            self.gid = byteReader.int(fromBytes: 2)
        }
    }

}

struct InfoZipNewUnixExtraField: ZipExtraField {

    static let id: UInt16 = 0x7875

    let size: Int
    let location: ZipExtraFieldLocation

    var uid: Int?
    var gid: Int?

    init?(_ byteReader: LittleEndianByteReader, _ size: Int, location: ZipExtraFieldLocation) {
        self.size = size
        self.location = location
        let endOffset = byteReader.offset + size
        guard size >= 1, byteReader.byte() == 1 // Version must be 1
            else { return nil }

        guard endOffset - byteReader.offset >= 1
            else { return nil }
        let uidSize = byteReader.byte().toInt()
        guard endOffset - byteReader.offset >= uidSize
            else { return nil }
        if uidSize > 8 {
            byteReader.offset += uidSize
        } else {
            self.uid = byteReader.int(fromBytes: uidSize)
        }

        guard endOffset - byteReader.offset >= 1
            else { return nil }
        let gidSize = byteReader.byte().toInt()
        guard endOffset - byteReader.offset >= gidSize
            else { return nil }
        if gidSize > 8 {
            byteReader.offset += gidSize
        } else {
            self.gid = byteReader.int(fromBytes: gidSize)
        }
    }

}
