// LOCAL PATCH (fork): regression tests, security audit 2026-11-15 — output
// limits and the work a small input can cause (W18–W20, W26, W29, W30).

import Foundation
import XCTest
import SWCompression

final class LimitHardeningTests: XCTestCase {

    static let mebibyteOfZeros = Data(count: 1 << 20)

    /// Asserts that `body` throws `DecompressionLimitExceeded` for `limit`.
    func assertLimit<T>(_ limit: Int, _ body: () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual((error as? DecompressionLimitExceeded)?.limit, limit, "\(error)", file: file, line: line)
        }
    }

    // MARK: - W18: every decoder has a `limit:` form

    func testDeflateAndZlibLimits() throws {
        let zlib = ZlibArchive.archive(data: Self.mebibyteOfZeros)
        // A zlib stream is a two-byte header, raw Deflate and an Adler-32.
        let deflate = zlib.dropFirst(2).dropLast(4)
        assertLimit(100_000) { try Deflate.decompress(data: Data(deflate), limit: 100_000) }
        assertLimit(100_000) { try ZlibArchive.unarchive(archive: zlib, limit: 100_000) }
        XCTAssertEqual(try Deflate.decompress(data: Data(deflate), limit: 1 << 20), Self.mebibyteOfZeros)
        XCTAssertEqual(try ZlibArchive.unarchive(archive: zlib, limit: 1 << 20), Self.mebibyteOfZeros)
    }

    func testGzipMultiUnarchiveLimit() throws {
        let member = try GzipArchive.archive(data: Self.mebibyteOfZeros)
        let two = member + member
        assertLimit(1_500_000) { try GzipArchive.multiUnarchive(archive: two, limit: 1_500_000) }
        XCTAssertEqual(try GzipArchive.multiUnarchive(archive: two, limit: 2 << 20).map { $0.data },
                       [Self.mebibyteOfZeros, Self.mebibyteOfZeros])
    }

    func testLZ4Limits() throws {
        let frame = LZ4.compress(data: Self.mebibyteOfZeros)
        assertLimit(100_000) { try LZ4.decompress(data: frame, limit: 100_000) }
        assertLimit(1_500_000) { try LZ4.multiDecompress(data: frame + frame, limit: 1_500_000) }
        XCTAssertEqual(try LZ4.decompress(data: frame, limit: 1 << 20), Self.mebibyteOfZeros)
        XCTAssertEqual(try LZ4.multiDecompress(data: frame + frame, limit: 2 << 20),
                       [Self.mebibyteOfZeros, Self.mebibyteOfZeros])
    }

    func testBZip2MultiDecompressLimit() throws {
        let stream = BZip2.compress(data: Self.mebibyteOfZeros)
        assertLimit(1_500_000) { try BZip2.multiDecompress(data: stream + stream, limit: 1_500_000) }
        XCTAssertEqual(try BZip2.multiDecompress(data: stream + stream, limit: 2 << 20),
                       [Self.mebibyteOfZeros, Self.mebibyteOfZeros])
    }

    /// Python's `lzma`: 1 MiB of zeros as .xz (CRC-32), as raw LZMA2 behind its
    /// dictionary byte (1 MiB = 16), and as raw LZMA1 (lc 3, lp 0, pb 2, end marker).
    static let xzZeros = hex("""
        fd377a585a0000016922de360200210116000000742fe5a3efffff00d95d00006ffdffffa3b7ff473e481572396151b89228e6a3\
        8607f9eee41e82d32fc53a3c014bb17ec98a8a4d2fa30dd97fa6e38c231153e05918c5758ae277f8b6947f0c6ac0de744964e2e9\
        5c53b204d8f7440cab5f0d6d46e9e5c37688b79657acb64de1691d6ffb4b88106c42cb883f5c008fd04eaf262894711f3d8f24e1\
        709ea7235fec28cb85d195988a7e2a91f22775f719c006984d98fdd8afd5900fc42553f8f591363105a5b0ee6fc1704d470cd191\
        11aaad601dbaceb127185c5986e9665258bee976ac59e4e55b0508f9c7daadfcfb522af7e4952500000000001cea38a70001f101\
        808040006fd5eedc3e300d8b020000000001595a
        """)
    static let lzma2Zeros = hex("""
        10efffff00d95d00006ffdffffa3b7ff473e481572396151b89228e6a38607f9eee41e82d32fc53a3c014bb17ec98a8a4d2fa30d\
        d97fa6e38c231153e05918c5758ae277f8b6947f0c6ac0de744964e2e95c53b204d8f7440cab5f0d6d46e9e5c37688b79657acb6\
        4de1691d6ffb4b88106c42cb883f5c008fd04eaf262894711f3d8f24e1709ea7235fec28cb85d195988a7e2a91f22775f719c006\
        984d98fdd8afd5900fc42553f8f591363105a5b0ee6fc1704d470cd19111aaad601dbaceb127185c5986e9665258bee976ac59e4\
        e55b0508f9c7daadfcfb522af7e495250000
        """)
    static let lzma1Zeros = hex("""
        00006ffdffffa3b7ff473e481572396151b89228e6a38607f9eee41e82d32fc53a3c014bb17ec98a8a4d2fa30dd97fa6e38c2311\
        53e05918c5758ae277f8b6947f0c6ac0de744964e2e95c53b204d8f7440cab5f0d6d46e9e5c37688b79657acb64de1691d6ffb4b\
        88106c42cb883f5c008fd04eaf262894711f3d8f24e1709ea7235fec28cb85d195988a7e2a91f22775f719c006984d98fdd8afd5\
        900fc42553f8f591363105a5b0ee6fc1704d470cd19111aaad601dbaceb127185c5986e9665258bee976ac59e4e55b0508f9c7da\
        adfcfb522af7e51cdccfffff82160000
        """)

    func testXZSplitUnarchiveLimit() throws {
        let two = Self.xzZeros + Self.xzZeros
        assertLimit(1_500_000) { try XZArchive.splitUnarchive(archive: two, limit: 1_500_000) }
        XCTAssertEqual(try XZArchive.splitUnarchive(archive: two, limit: 2 << 20),
                       [Self.mebibyteOfZeros, Self.mebibyteOfZeros])
    }

    func testLZMA2AndRawLZMALimits() throws {
        assertLimit(100_000) { try LZMA2.decompress(data: Self.lzma2Zeros, limit: 100_000) }
        XCTAssertEqual(try LZMA2.decompress(data: Self.lzma2Zeros, limit: 1 << 20), Self.mebibyteOfZeros)
        let properties = LZMAProperties(lc: 3, lp: 0, pb: 2, dictionarySize: 1 << 20)
        assertLimit(100_000) { try LZMA.decompress(data: Self.lzma1Zeros, properties: properties, limit: 100_000) }
        XCTAssertEqual(try LZMA.decompress(data: Self.lzma1Zeros, properties: properties, limit: 1 << 20),
                       Self.mebibyteOfZeros)
    }

    // MARK: - W19: the limited single-result forms read every member

    func testGzipLimitedReadsEveryMember() throws {
        let a = try GzipArchive.archive(data: Data("first\n".utf8))
        let b = try GzipArchive.archive(data: Data("second\n".utf8))
        XCTAssertEqual(try GzipArchive.unarchive(archive: a + b, limit: 100), Data("first\nsecond\n".utf8))
        XCTAssertEqual(try GzipArchive.unarchive(archive: a + Data(count: 512), limit: 100), Data("first\n".utf8))
        assertThrows(try GzipArchive.unarchive(archive: a + Data("junk".utf8), limit: 100))
        assertLimit(10) { try GzipArchive.unarchive(archive: a + b, limit: 10) }
    }

    func testBZip2LimitedReadsEveryStream() throws {
        let a = BZip2.compress(data: Data("first\n".utf8))
        let b = BZip2.compress(data: Data("second\n".utf8))
        XCTAssertEqual(try BZip2.decompress(data: a + b, limit: 100), Data("first\nsecond\n".utf8))
        XCTAssertEqual(try BZip2.decompress(data: a + Data(count: 512), limit: 100), Data("first\n".utf8))
        assertThrows(try BZip2.decompress(data: a + Data("junk".utf8), limit: 100))
        assertLimit(10) { try BZip2.decompress(data: a + b, limit: 10) }
    }

    // MARK: - W20 / W31: Huffman tables as linked nodes

    /// Deflate and BZip2 with many distinct symbols still round-trip through
    /// the rebuilt decoding tree.
    func testHuffmanRoundTrips() throws {
        var input = Data()
        var x: UInt32 = 2_463_534_242
        for _ in 0..<60_000 {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5
            input.append(UInt8(truncatingIfNeeded: x % 97 + (x >> 8) % 61))
        }
        XCTAssertEqual(try BZip2.decompress(data: BZip2.compress(data: input)), input)
        XCTAssertEqual(try ZlibArchive.unarchive(archive: ZlibArchive.archive(data: input)), input)
        XCTAssertEqual(try GzipArchive.unarchive(archive: GzipArchive.archive(data: input)), input)
    }

    // MARK: - W30: truncated .lzma of unknown size

    /// 18 bytes: properties, size "unknown", then a range-coder start and nothing
    /// more. Without a limit this produced zeros forever.
    static let truncatedUnknownSize = hex("5d00100000ffffffffffffffff0000000000")

    func testTruncatedUnknownSizeLzmaEnds() {
        assertThrows(try LZMA.decompress(data: Self.truncatedUnknownSize))
        assertThrows(try LZMA.decompress(data: Self.truncatedUnknownSize, limit: 1 << 30))
        // A valid stream of unknown size still ends at its end marker.
        let alone = hex("5d00001000ffffffffffffffff") + Self.lzma1Zeros
        XCTAssertEqual(try LZMA.decompress(data: alone), Self.mebibyteOfZeros)
    }

    // MARK: - 7-Zip folders: W26, W29

    /// One folder (`coders`, declared `unpackSize`) over `packed` pack streams,
    /// holding files of `fileSizes` (the last implied).
    func sevenZipOneFolder(coder: Data, unpackSize: Int, packed: [Data], fileSizes: [Int]) -> Data {
        var packSizes = Data()
        for p in packed { packSizes += szNumber(p.count) }
        let packInfo = cat(bytes(0x06), szNumber(0), szNumber(packed.count), bytes(0x09), packSizes, bytes(0x00))
        let unpackInfo = cat(bytes(0x07, 0x0B), szNumber(1), bytes(0x00), szNumber(1), coder,
                             bytes(0x0C), szNumber(unpackSize), bytes(0x00))
        var sizes = Data()
        for s in fileSizes.dropLast() { sizes += szNumber(s) }
        let substreams = cat(bytes(0x08, 0x0D), szNumber(fileSizes.count),
                             fileSizes.count > 1 ? bytes(0x09) + sizes : Data(), bytes(0x00))
        let streams = cat(bytes(0x04), packInfo, unpackInfo, substreams, bytes(0x00))
        let names = (0..<fileSizes.count).map { "f\($0)" }
        return sevenZip(header: Data([0x01]) + streams + sevenZipFilesInfo(names) + Data([0x00]),
                        packed: packed.reduce(Data(), +))
    }

    /// W26: a Copy folder of declared size 2 whose one byte of output ran out
    /// after the first file; the same folder was then unpacked again from the
    /// next pack stream for the second.
    func testFolderIsUnpackedOnce() {
        let archive = sevenZipOneFolder(coder: bytes(0x01, 0x00), unpackSize: 2,
                                        packed: [Data("A".utf8), Data("B".utf8)], fileSizes: [1, 1])
        assertThrows(try SevenZipContainer.open(container: archive))
    }

    /// W26: a Copy folder whose output is longer than declared is refused, not
    /// cut silently.
    func testCopyFolderSizeChecked() throws {
        let short = sevenZipOneFolder(coder: bytes(0x01, 0x00), unpackSize: 1,
                                      packed: [Data("ABC".utf8)], fileSizes: [1])
        assertThrows(try SevenZipContainer.open(container: short))
        let exact = sevenZipOneFolder(coder: bytes(0x01, 0x00), unpackSize: 3,
                                      packed: [Data("ABC".utf8)], fileSizes: [1, 2])
        XCTAssertEqual(try SevenZipContainer.open(container: exact).map { $0.data }, [Data("A".utf8), Data("BC".utf8)])
    }

    /// W29: an LZMA2 folder declaring 2^47 bytes. The fast path reserved that
    /// much up front and trapped.
    func testHugeDeclaredLZMA2FolderThrows() {
        let lzma2Coder = bytes(0x21, 0x21, 0x01, 0x10) // id size 1 + properties; id 0x21; one property byte
        let archive = sevenZipOneFolder(coder: lzma2Coder, unpackSize: 1 << 47,
                                        packed: [Self.lzma2Zeros.dropFirst()], fileSizes: [1 << 47])
        assertThrows(try SevenZipContainer.open(container: archive))
    }
}
