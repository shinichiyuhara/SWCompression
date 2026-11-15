// LOCAL PATCH (fork): regression tests, security audit 2026-11-15.

import Foundation
import XCTest
import SWCompression

final class ArchiveHardeningTests: XCTestCase {

    // MARK: - GZip

    /// W2: FEXTRA with XLEN 9 — one 6-byte subfield ("AB", length 2), then a
    /// 3-byte remainder whose four-byte subfield header ran past the end of
    /// the input.
    static let gzipShortSubfield = hex("1f8b0804000000000003 0900 4142 0200 5858 434445")

    func testGzipExtraFieldRemainderThrows() {
        assertThrows(try GzipArchive.unarchive(archive: Self.gzipShortSubfield))
        assertThrows(try GzipArchive.unarchive(archive: Self.gzipShortSubfield, limit: 1000))
        assertThrows(try GzipArchive.multiUnarchive(archive: Self.gzipShortSubfield))
        assertThrows(try GzipHeader(archive: Self.gzipShortSubfield))
    }

    /// A member with two well-formed extra subfields still decodes.
    func testGzipExtraFieldsRoundTrip() throws {
        let input = Data("extra fields are fine\n".utf8)
        var member = try GzipArchive.archive(data: input)
        XCTAssertEqual(member[3], 0, "expected no flags from archive(data:)")
        member[3] = 0x04
        let extra = cat(bytes(0x41, 0x42, 0x02, 0x00, 0x01, 0x02), bytes(0x43, 0x44, 0x00, 0x00))
        member.insert(contentsOf: le(UInt64(extra.count), 2) + extra, at: 10)
        XCTAssertEqual(try GzipArchive.unarchive(archive: member), input)
        XCTAssertEqual(try GzipArchive.unarchive(archive: member, limit: input.count), input)
        XCTAssertEqual(try GzipHeader(archive: member).extraFields.count, 2)
    }

    // MARK: - XZ

    /// W9: a block header of declared size 8 whose two 9-byte sizes run on to
    /// the end of the input; the filter ID was then read past it.
    static let xzHeaderOverrun = hex("fd377a585a000000ff12d941 01c0ffffffffffffffff01ffffffffffffff012101")

    /// W10: a block whose data ends the input where three bytes of padding
    /// were due.
    static let xzMissingPadding = hex("fd377a585a000000ff12d941 0200210100000000 372797d6 0100044142434445 00")

    func testXZBlockHeaderOverrunThrows() {
        assertThrows(try XZArchive.unarchive(archive: Self.xzHeaderOverrun))
        assertThrows(try XZArchive.unarchive(archive: Self.xzHeaderOverrun, limit: 1000))
        assertThrows(try XZArchive.splitUnarchive(archive: Self.xzHeaderOverrun))
    }

    func testXZMissingPaddingThrows() {
        assertThrows(try XZArchive.unarchive(archive: Self.xzMissingPadding))
        assertThrows(try XZArchive.unarchive(archive: Self.xzMissingPadding, limit: 1000))
        assertThrows(try XZArchive.splitUnarchive(archive: Self.xzMissingPadding))
    }

    /// `printf 'hello, xz\n' | xz -9 -C crc32` — its block is padded.
    static let xzHello = hex("""
        fd377a585a0000016922de3604c00e0a21011c0000000000000000008396ba3201000968656c6c6f2c20787a0a\
        00000042ea5ace0001260a11df8d039042990d010000000001595a
        """)

    func testXZRoundTrip() throws {
        let expected = Data("hello, xz\n".utf8)
        XCTAssertEqual(try XZArchive.unarchive(archive: Self.xzHello), expected)
        XCTAssertEqual(try XZArchive.unarchive(archive: Self.xzHello, limit: expected.count), expected)
        XCTAssertEqual(try XZArchive.splitUnarchive(archive: Self.xzHello), [expected])
    }

    // MARK: - .lzma

    /// W11: the header's size is 2^63, read as `Int.min`; the decoder's
    /// `uncompressedSize -= 1` overflowed on the first byte.
    static let lzmaSizeIntMin = hex("5d00100000 0000000000000080 0020c1fbffffffe0000000")

    func testLzmaNegativeSizeThrows() {
        assertThrows(try LZMA.decompress(data: Self.lzmaSizeIntMin))
        assertThrows(try LZMA.decompress(data: Self.lzmaSizeIntMin, limit: 1000))
    }

    /// `printf 'hello, xz\n' | xz --format=lzma` — size "unknown" (all ones),
    /// ended by the end marker.
    static let lzmaHello = hex("5d00008000ffffffffffffffff00341949ee8def8c6bed37ac31d7fffffd987000")

    func testLzmaRoundTrip() throws {
        let expected = Data("hello, xz\n".utf8)
        XCTAssertEqual(try LZMA.decompress(data: Self.lzmaHello), expected)
        XCTAssertEqual(try LZMA.decompress(data: Self.lzmaHello, limit: expected.count), expected)
    }
}
