// LOCAL PATCH (fork): regression tests, security audit 2026-11-15.
// Decoders that 7-Zip folders reach as coders: Deflate, LZ4, LZMA, LZMA2.

import Foundation
import XCTest
import SWCompression

final class CoderHardeningTests: XCTestCase {

    // MARK: Deflate (W1)

    /// A stream that ends right after a block without BFINAL.
    func testDeflateEndingAfterNonFinalBlockThrows() {
        // Stored block of length 0, BFINAL = 0, then nothing.
        assertThrows(try Deflate.decompress(data: hex("00 0000 FFFF")))
        // Four empty static blocks, none final.
        assertThrows(try Deflate.decompress(data: hex("02 08 20 80 00")))
        // The same through gzip (with `limit:`) and zlib.
        let gzip = hex("1f8b 0800 00000000 0003 000500faff 4141414141")
        assertThrows(try GzipArchive.unarchive(archive: gzip))
        assertThrows(try GzipArchive.unarchive(archive: gzip, limit: 100))
        assertThrows(try GzipArchive.multiUnarchive(archive: gzip))
        assertThrows(try ZlibArchive.unarchive(archive: hex("789c 000000ffff")))
    }

    func testDeflateRoundTrip() throws {
        var input = Data()
        for i in 0..<100_000 { input.append(UInt8(truncatingIfNeeded: i &* 31 &+ i / 7)) }
        XCTAssertEqual(try Deflate.decompress(data: Deflate.compress(data: input)), input)
        let gz = try GzipArchive.archive(data: input)
        XCTAssertEqual(try GzipArchive.unarchive(archive: gz, limit: input.count), input)
    }

    // MARK: LZ4 (W5, Q3)

    /// 5,000 empty skippable frames before a real one. The decoder recursed
    /// once per frame and overflowed a 512 KiB stack.
    func testManySkippableFramesDoNotRecurse() throws {
        var data = Data()
        for _ in 0..<5_000 { data.append(hex("502A4D18 00000000")) }
        let payload = Data("hello, lz4".utf8)
        data.append(LZ4.compress(data: payload))
        let out = try onSmallStack { try LZ4.decompress(data: data) }
        XCTAssertEqual(out, payload)
    }

    /// A frame at an odd offset (after a 9-byte skippable frame) is read
    /// without assuming alignment.
    func testUnalignedFrame() throws {
        let payload = Data(repeating: 0x5A, count: 1000)
        let data = hex("502A4D18 01000000 00") + LZ4.compress(data: payload)
        XCTAssertEqual(try LZ4.decompress(data: data), payload)
        XCTAssertEqual(try LZ4.multiDecompress(data: data), [payload])
    }

    // MARK: LZMA (W6, W7)

    static let quickBrownFox = Data(String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 50)
        .utf8.prefix(593))

    /// A valid .lzma made with pb = 4 (Python's lzma module, FORMAT_ALONE). The
    /// probability table was one slot short and this trapped.
    func testLZMAWithPb4() throws {
        let file = hex("b700100000ffffffffffffffff002a1a08a203090f548dac6cc0f29a933d10954610a86af323ab496d80e2dad74d92e270d1a8d17f3487f9061516eb945f9543cfd4c88bffff21740000")
        XCTAssertEqual(try LZMA.decompress(data: file), Self.quickBrownFox)
        XCTAssertEqual(try LZMA.decompress(data: file, limit: 1000), Self.quickBrownFox)
    }

    /// A valid .xz made with `--lzma2=pb=4` over 350 KB.
    func testXZWithPb4() throws {
        let file = hex("fd377a585a000004e6d6b4460200210116000000742fe5a3e5572f0210b70000020f570258e2743fef8d91ebf2534be149819c483230f31c37e5abd90055d7e793538ed193841e40d0d23cf80c06955fd1569d5beccdfcd4f1b7a0b844158530e46ad0ed3f171308d33d8afaf1407604c19c40e2dfc9cc822e713f1afc35c57b2fdf5a1ecbf8b5260c1ef069572c30135314e95efa4bd5a69681423d3e3d3bf5fd28af60d88d73e3c11c0fa1b7582a7f587eb1e0dc900c5dccb69f961968d1addc66d7f51dfdcaf78af2ca4f4b6428be27341e35a3601f23a8bf367e246b91b059a0c542ed1f05ca4feb4cb237e40d6ecf7f8ae7b16defaacf9bd07b451c2fb45025502c7ff0ec9549f636b26d321a2b3b9213a434e44ed1927c08ff887b2d1319276f75e938b5f40e8f258978ef45dc5c96df07b9500de2f75f49c99112f4e7677fe5dc15922093dc80a82810d5302f7025a891ad0bb598cc2107409115203a7afa67fdf32475c83acc2fbcdd5dbfcbbc5bb7e9ef38228f3f10a343abb3caf70df580af6d59712517fc268bfbc4cb1129c26b767c3ab0b9dfc4d3c52409a6d279e68202ba7d77fd2b77ec993b7ba43a20e584265c85741fdb46d34d250b497ab2fb6fd0daea3831d8e4d0d9c958a6440ea808b493b30b4c9f44a67b520cb6436d97db89a8daa14847ba7561ab1158c902f16724bd328acb1d0b4f7b27df0877dd7b8ae4bedfcfc5edf6661a9491a12f8d99ba25b4ff49d77e96672a3fc5fcc2ea2c4ffc120a1ff9f8e6aedf8400000006084d1f441e8a170001ac04b0ae15006c7b2aa1b1c467fb020000000004595a")
        var expected = Data()
        for i in 0..<300_000 { expected.append(UInt8(truncatingIfNeeded: i * 7 + i / 13)) }
        expected.append(Data(repeating: 0x41, count: 50_000))
        XCTAssertEqual(try XZArchive.unarchive(archive: file), expected)
        XCTAssertEqual(try XZArchive.unarchive(archive: file, limit: expected.count), expected)
    }

    /// The first symbol is a match at distance 1 into an empty dictionary
    /// (`rep0 == dictEnd`), which slipped past the check.
    func testMatchIntoEmptyDictionaryThrows() {
        let file = hex("5d00000100ffffffffffffffff007ffffc000000000000")
        assertThrows(try LZMA.decompress(data: file))
        assertThrows(try LZMA.decompress(data: file, limit: 1000))
    }

    // MARK: LZMA2 (W8)

    /// An .xz whose LZMA2 data starts with control 0x80: an LZMA chunk with no
    /// dictionary reset and no properties.
    func testLZMA2WithoutInitialResetThrows() {
        let file = hex("fd377a585a000000ff12d9410200210100000000372797d680000000040000000000")
        assertThrows(try XZArchive.unarchive(archive: file))
        assertThrows(try XZArchive.unarchive(archive: file, limit: 1000))
        // The same chunk as raw LZMA2 (dictionary byte 0x00, then the chunk).
        assertThrows(try LZMA2.decompress(data: hex("00 80000000 04 0000000000")))
    }

    func testLZMA2UncompressedChunkFirstThenLZMAWithoutPropertiesThrows() {
        // Control 1 (dictionary reset, 1 byte "A"), then 0x80 (no properties).
        assertThrows(try LZMA2.decompress(data: hex("00 01 0000 41 80000000 04 0000000000")))
    }

    func testLZMA2UncompressedOnly() throws {
        XCTAssertEqual(try LZMA2.decompress(data: hex("00 01 0002 414243 02 0000 44 00")), Data("ABCD".utf8))
    }
}
