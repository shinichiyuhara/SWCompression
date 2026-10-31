// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

// While it is tempting to make the parser conform to `IteratorProtocol` and `Sequence` protocols, it is in fact
// impossible to do so, since `TarHeader.init(_)` is throwing and `IteratorProtocol.next()` cannot be throwing.
struct TarParser {

    enum ParsingResult {
        case truncated
        case eofMarker
        case finished
        case specialEntry(TarHeader.SpecialEntryType)
        case entryInfo(TarEntryInfo, Int, TarContainer.Format)
    }

    private let reader: LittleEndianByteReader
    private var lastGlobalExtendedHeader: TarExtendedHeader?
    private var lastLocalExtendedHeader: TarExtendedHeader?
    private var longLinkName: String?
    private var longName: String?

    init(_ data: Data) {
        self.reader = LittleEndianByteReader(data: data)
        self.lastGlobalExtendedHeader = nil
        self.lastLocalExtendedHeader = nil
        self.longLinkName = nil
        self.longName = nil
    }

    mutating func next() throws -> ParsingResult {
        if reader.isFinished {
            return .finished
        } else if reader.bytesLeft >= 1024 && reader.data[reader.offset..<reader.offset + 1024] == Data(count: 1024) {
            return .eofMarker
        } else if reader.bytesLeft < 512 {
            return .truncated
        }

        let header = try TarHeader(reader)
        // For header we read at most 512 bytes.
        assert(reader.offset - header.blockStartIndex <= 512)
        // Check, just in case, since we use blockStartIndex = -1 when creating TAR containers.
        assert(header.blockStartIndex >= 0)
        let dataStartIndex = header.blockStartIndex + 512

        // `header.size` is taken from the attacker-controlled header. A value
        // that pushes the entry's data region past the end of the buffer, or a
        // negative size, makes the `reader.data[dataStartIndex..<dataEndIndex]`
        // slices and the `tarCString` reads below index out of range — a Swift
        // trap, not a throwable error, which crashes the host process and can
        // never be caught by `try?`. The parser already models a short buffer
        // as `.truncated`; treat an out-of-range declared size the same way.
        // Subtraction (not addition) avoids overflowing on a huge base-256 size.
        guard header.size >= 0,
              dataStartIndex >= 0,
              dataStartIndex <= reader.size,
              header.size <= reader.size - dataStartIndex
            else { return .truncated }

        if case .special(let specialEntryType) = header.type {
            switch specialEntryType {
            case .globalExtendedHeader:
                let dataEndIndex = dataStartIndex + header.size
                lastGlobalExtendedHeader = try TarExtendedHeader(reader.data[dataStartIndex..<dataEndIndex])
            case .sunExtendedHeader:
                fallthrough
            case .localExtendedHeader:
                let dataEndIndex = dataStartIndex + header.size
                lastLocalExtendedHeader = try TarExtendedHeader(reader.data[dataStartIndex..<dataEndIndex])
            case .longLinkName:
                reader.offset = dataStartIndex
                longLinkName = reader.tarCString(maxLength: header.size)
            case .longName:
                reader.offset = dataStartIndex
                longName = reader.tarCString(maxLength: header.size)
            }
            reader.offset = dataStartIndex + header.size.roundTo512()
            return .specialEntry(specialEntryType)
        } else {
            let info = TarEntryInfo(header, lastGlobalExtendedHeader, lastLocalExtendedHeader, longName, longLinkName)
            // LOCAL PATCH (fork): a PAX record replaces `header.size`, so the
            // check above did not cover this value. `TarContainer.open` slices
            // the entry's data with it, and a negative or overflowing size traps.
            if let size = info.size {
                guard size >= 0, size <= reader.size - dataStartIndex else { return .truncated }
            }
            // Skip file data.
            reader.offset = dataStartIndex + header.size.roundTo512()
            lastLocalExtendedHeader = nil
            longName = nil
            longLinkName = nil
            return .entryInfo(info, header.blockStartIndex, header.format)
        }
    }

}
