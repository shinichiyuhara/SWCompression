// LOCAL PATCH (fork): regression tests, security audit 2026-11-15 — low
// findings and interpretation differences (W32–W36, W39–W43).

import Foundation
import XCTest
import SWCompression

final class LowHardeningTests: XCTestCase {

    // MARK: - W32: BZip2's run-length stage is held to the limit as it goes

    func testBZip2BlockHeldToLimit() throws {
        let zeros = Data(count: 800_000)
        let stream = BZip2.compress(data: zeros)
        XCTAssertThrowsError(try BZip2.decompress(data: stream, limit: 1000)) { error in
            XCTAssertTrue(error is DecompressionLimitExceeded, "\(error)")
        }
        XCTAssertEqual(try BZip2.decompress(data: stream, limit: zeros.count), zeros)
    }

    // MARK: - W33: LZ4 blocks decoded in place

    func testLZ4BlockModesRoundTrip() throws {
        var input = Data()
        var x: UInt32 = 88_172_645
        for _ in 0..<200_000 {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5
            input.append(UInt8(truncatingIfNeeded: x % 23 + 0x61))
        }
        let dictionary = input.prefix(100_000)
        for independent in [true, false] {
            for dict in [nil, Data(dictionary)] {
                let frame = LZ4.compress(data: input, independentBlocks: independent, blockChecksums: true,
                                         contentChecksum: true, contentSize: true, blockSize: 64 * 1024,
                                         dictionary: dict)
                XCTAssertEqual(try LZ4.decompress(data: frame, dictionary: dict), input,
                               "independent \(independent), dictionary \(dict != nil)")
                XCTAssertEqual(try LZ4.decompress(data: frame, dictionary: dict, limit: input.count), input)
            }
        }
    }

    // MARK: - TAR

    /// A header block with `size` written as `field` (12 bytes, as given).
    func tarHeaderRaw(name: String, sizeField field: String) -> Data {
        var h = [UInt8](SWCompressionHardeningTests.tarHeader(name: name, size: 0))
        for (i, b) in field.utf8.enumerated() { h[124 + i] = b }
        for i in 148..<156 { h[i] = 0x20 }
        let sum = h.reduce(0) { $0 + Int($1) }
        for (i, b) in String(format: "%06o", sum).utf8.enumerated() { h[148 + i] = b }
        h[154] = 0
        h[155] = 0x20
        return Data(h)
    }

    /// W34: a size of 12 octal digits with no terminator, as GNU tar writes
    /// large sizes; the last digit was dropped (013 read as 01).
    func testTwelveDigitSize() throws {
        let payload = Data("eleven byte".utf8)
        let archive = tarHeaderRaw(name: "f", sizeField: "000000000013") + tarPadded(payload) + Data(count: 1024)
        let entries = try TarContainer.open(container: archive)
        XCTAssertEqual(entries.first?.info.size, 11)
        XCTAssertEqual(entries.first?.data, payload)
    }

    /// W35: a PAX time that is not a representable whole second is ignored on
    /// reading, and the writer no longer traps on one.
    func testHugePaxTimeIgnoredAndWritable() throws {
        let archive = paxEntry(paxRecord("mtime", "1e300") + paxRecord("atime", "nan"))
            + SWCompressionHardeningTests.tarHeader(name: "f", size: 0) + Data(count: 1024)
        let entries = try TarContainer.open(container: archive)
        XCTAssertEqual(entries.count, 1)
        _ = TarContainer.create(from: entries)
        var info = TarEntryInfo(name: "g", type: .regular)
        info.modificationTime = Date(timeIntervalSince1970: 1e300)
        info.accessTime = Date(timeIntervalSince1970: .infinity)
        _ = TarContainer.create(from: [TarEntry(info: info, data: Data())])
        _ = TarContainer.create(from: [TarEntry(info: info, data: Data())], force: .pax)
        _ = TarContainer.create(from: [TarEntry(info: info, data: Data())], force: .gnu)
        _ = try GzipArchive.archive(data: Data("x".utf8), modificationTime: Date(timeIntervalSince1970: 1e300))
    }

    /// W36: a PAX `path` that is not UTF-8, or holds a NUL, is refused rather
    /// than replaced by the basic header's name or cut by file-system calls.
    func testUndecodablePaxPathRefused() {
        let records = paxRecord("path", "x") // template, then patched
        var invalid = [UInt8](records)
        invalid[invalid.count - 2] = 0xFF
        let bad = paxEntry(Data(invalid)) + SWCompressionHardeningTests.tarHeader(name: "decoy", size: 0) + Data(count: 1024)
        assertThrows(try TarContainer.info(container: bad))
        let nul = paxEntry(paxRecord("path", "safe\u{0}../evil")) + SWCompressionHardeningTests.tarHeader(name: "decoy", size: 0) + Data(count: 1024)
        assertThrows(try TarContainer.info(container: nul))
        let fine = paxEntry(paxRecord("path", "émigré")) + SWCompressionHardeningTests.tarHeader(name: "decoy", size: 0) + Data(count: 1024)
        XCTAssertEqual(try TarContainer.info(container: fine).map { $0.name }, ["émigré"])
    }

    /// W42: a link name over 100 bytes behind a short name goes into PAX.
    func testLongLinkNameWritten() throws {
        let target = String(repeating: "t", count: 150)
        var info = TarEntryInfo(name: "link", type: .symbolicLink)
        info.linkName = target
        let archive = TarContainer.create(from: [TarEntry(info: info, data: nil)], force: .pax)
        XCTAssertEqual(try TarContainer.info(container: archive).first?.linkName, target)
    }

    // MARK: - W39: slices of a larger Data

    func testSlicedContainers() throws {
        let tar = TarContainer.create(from: [TarEntry(info: TarEntryInfo(name: "f", type: .regular),
                                                      data: Data("tar".utf8))])
        let tarSlice = (Data([0xAA, 0xBB, 0xCC]) + tar)[3...]
        XCTAssertEqual(try TarContainer.open(container: tarSlice).first?.data, Data("tar".utf8))
        XCTAssertEqual(try TarContainer.formatOf(container: tarSlice), try TarContainer.formatOf(container: tar))

        let sevenZip = sevenZip(header: Data([0x01]) + sevenZipFilesInfo(["a"], extra: Self.emptyFile) + Data([0x00]))
        let sevenZipSlice = (Data([0xAA, 0xBB, 0xCC]) + sevenZip)[3...]
        XCTAssertEqual(try SevenZipContainer.open(container: sevenZipSlice).map { $0.info.name }, ["a"])
        XCTAssertEqual(try SevenZipContainer.info(container: sevenZipSlice).map { $0.name }, ["a"])
        XCTAssertEqual(try SevenZipContainer.folderUnpackSizes(container: sevenZipSlice), [])

        // With pack streams the parsers seek to absolute offsets: 7-Zip trapped,
        // and a tar entry ending at the end of the input was "truncated".
        let copyFolder = LimitHardeningTests().sevenZipOneFolder(coder: bytes(0x01, 0x00), unpackSize: 3,
                                                                 packed: [Data("ABC".utf8)], fileSizes: [3])
        let copySlice = (Data([0xAA, 0xBB, 0xCC]) + copyFolder)[3...]
        XCTAssertEqual(try SevenZipContainer.open(container: copySlice).map { $0.data }, [Data("ABC".utf8)])
        let block = Data(repeating: 0x42, count: 512)
        let tight = SWCompressionHardeningTests.tarHeader(name: "f", size: 512) + block + Data(count: 1024)
        XCTAssertEqual(try TarContainer.open(container: (Data(count: 2048) + tight)[2048...]).first?.data, block)
    }

    // MARK: - 7-Zip entry attributes (W40, W41)

    /// EmptyStream and EmptyFile for one file.
    static let emptyFile = bytes(0x0E, 0x01, 0x80, 0x0F, 0x01, 0x80)

    func attributes(_ value: UInt32) -> Data {
        cat(Self.emptyFile, bytes(0x15, 0x06, 0x01, 0x00), le(UInt64(value), 4))
    }

    /// W40: the upper 16 bits are a Unix mode only with 0x8000 set.
    func testUnixModeNeedsExtensionBit() throws {
        let without = sevenZip(header: Data([0x01]) + sevenZipFilesInfo(["a"], extra: attributes(0xA1ED_0020))
                               + Data([0x00]))
        let info = try SevenZipContainer.info(container: without)[0]
        XCTAssertNil(info.permissions)
        XCTAssertEqual(info.type, .regular)

        let with = sevenZip(header: Data([0x01]) + sevenZipFilesInfo(["a"], extra: attributes(0x81ED_8020))
                            + Data([0x00]))
        let unix = try SevenZipContainer.info(container: with)[0]
        XCTAssertEqual(unix.permissions?.rawValue, 0o755)
        XCTAssertEqual(unix.type, .regular)
    }

    /// W41: an anti item has no size in `info`, as it has no data in `open`.
    func testAntiItemAgrees() throws {
        let archive = sevenZip(header: Data([0x01])
                               + sevenZipFilesInfo(["gone"], extra: Self.emptyFile + bytes(0x10, 0x01, 0x80))
                               + Data([0x00]))
        let info = try SevenZipContainer.info(container: archive)[0]
        let entry = try SevenZipContainer.open(container: archive)[0]
        XCTAssertTrue(info.isAnti)
        XCTAssertNil(info.size)
        XCTAssertNil(entry.data)
        XCTAssertEqual(entry.info.size, info.size)
    }

    // MARK: - W43: XZ filter chains

    /// `ArchiveHardeningTests.xzHello` with its 20-byte block header replaced:
    /// no sizes, the given filter flags.
    func xzHello(filters: Data, count: Int) -> Data {
        var archive = ArchiveHardeningTests.xzHello
        var body = Data([0x04, UInt8(count - 1)]) + filters
        body.append(Data(count: 16 - body.count))
        let header = body + le(UInt64(crc32(body)), 4)
        archive.replaceSubrange(12..<32, with: header)
        return archive
    }

    func testFilterChainOrder() throws {
        let lzma2 = bytes(0x21, 0x01, 0x1C)
        let delta = bytes(0x03, 0x01, 0x00)
        XCTAssertEqual(try XZArchive.unarchive(archive: xzHello(filters: lzma2, count: 1)), Data("hello, xz\n".utf8))
        assertThrows(try XZArchive.unarchive(archive: xzHello(filters: lzma2 + lzma2, count: 2)))
        assertThrows(try XZArchive.unarchive(archive: xzHello(filters: delta, count: 1)))
        assertThrows(try XZArchive.unarchive(archive: xzHello(filters: lzma2 + delta, count: 2), limit: 100))
    }
}
