// LOCAL PATCH (fork): regression tests, security audit 2026-11-15.

import Foundation
import XCTest
import SWCompression

final class SevenZipHardeningTests: XCTestCase {

    /// W12: more files than the ceiling. A Dummy (0x19) property pads the
    /// header so that the older one-byte-per-file check passes.
    func testFileCountCeiling() {
        let n = (1 << 21) + 1
        let header = Data([0x01, 0x05]) + szNumber(n) + Data([0x19]) + szNumber(n) + Data(count: n)
            + Data([0x00, 0x00])
        let archive = sevenZip(header: header)
        assertThrows(try SevenZipContainer.info(container: archive))
        assertThrows(try SevenZipContainer.folderUnpackSizes(container: archive))
    }

    /// W13: EmptyFile (0x0F) repeated. Each repeat rescanned every file.
    func testRepeatedEmptyFilePropertyThrows() {
        let n = 16
        var props = Data([0x0E]) + szNumber(2) + Data([0xFF, 0xFF]) // EmptyStream: all 16 empty
        for _ in 0..<3 { props += Data([0x0F]) + szNumber(2) + Data([0x00, 0x00]) }
        let names = (0..<n).map { "f\($0)" }
        let archive = sevenZip(header: Data([0x01]) + sevenZipFilesInfo(names, extra: props) + Data([0x00]))
        assertThrows(try SevenZipContainer.info(container: archive))
        assertThrows(try SevenZipContainer.open(container: archive))
    }

    /// W13: a single EmptyFile property still works.
    func testSingleEmptyFileProperty() throws {
        let props = Data([0x0E]) + szNumber(1) + Data([0xC0]) // f0, f1 empty
            + Data([0x0F]) + szNumber(1) + Data([0x80])        // f0 is an empty file, f1 a directory
        let archive = sevenZip(header: Data([0x01]) + sevenZipFilesInfo(["f0", "f1"], extra: props) + Data([0x00]))
        let infos = try SevenZipContainer.info(container: archive)
        XCTAssertEqual(infos.map(\.name), ["f0", "f1"])
        XCTAssertEqual(infos.map(\.type), [.regular, .directory])
    }

    /// W25: two coders of 40 input streams each — 80 streams in the folder,
    /// within the old per-coder limit of 64 but over 7-Zip's folder total.
    func testFolderStreamTotalCeiling() {
        var folder = szNumber(2)
        for _ in 0..<2 { folder += Data([0x11, 0x00]) + szNumber(40) + szNumber(1) } // complex Copy, 40 in, 1 out
        folder += szNumber(0) + szNumber(1)                                       // bind pair: in 0 <- out 1
        for i in 1...79 { folder += szNumber(i) }                                 // packed streams
        let packInfo = cat(bytes(0x06), szNumber(0), szNumber(1), bytes(0x09), szNumber(0), bytes(0x00))
        let unpackInfo = cat(bytes(0x07, 0x0B), szNumber(1), bytes(0x00), folder,
                             bytes(0x0C), szNumber(0), szNumber(0), bytes(0x00))
        let streams = cat(bytes(0x04), packInfo, unpackInfo, bytes(0x00))
        let archive = sevenZip(header: Data([0x01]) + streams + Data([0x00]))
        assertThrows(try SevenZipContainer.folderUnpackSizes(container: archive))
        assertThrows(try SevenZipContainer.info(container: archive))
    }

    /// W28 and the ceilings: a valid archive of Copy folders, one pack stream
    /// each, still opens with every entry's bytes in place.
    func testCopyFoldersOpen() throws {
        let payloads = (0..<50).map { Data("payload-\($0)-".utf8) + Data(repeating: UInt8($0), count: $0) }
        var packSizes = Data()
        var folders = Data()
        var unpackSizes = Data()
        for p in payloads {
            packSizes += szNumber(p.count)
            folders += szNumber(1) + Data([0x01, 0x00]) // one simple Copy coder
            unpackSizes += szNumber(p.count)
        }
        let packInfo = cat(bytes(0x06), szNumber(0), szNumber(payloads.count), bytes(0x09), packSizes, bytes(0x00))
        let unpackInfo = cat(bytes(0x07, 0x0B), szNumber(payloads.count), bytes(0x00), folders,
                             bytes(0x0C), unpackSizes, bytes(0x00))
        let streams = cat(bytes(0x04), packInfo, unpackInfo, bytes(0x08, 0x00), bytes(0x00))
        let names = (0..<payloads.count).map { "file\($0)" }
        let archive = sevenZip(header: Data([0x01]) + streams + sevenZipFilesInfo(names) + Data([0x00]),
                               packed: payloads.reduce(Data(), +))
        let entries = try SevenZipContainer.open(container: archive)
        XCTAssertEqual(entries.map { $0.info.name }, names)
        XCTAssertEqual(entries.map { $0.data }, payloads)
        XCTAssertEqual(try SevenZipContainer.folderUnpackSizes(container: archive), payloads.map { $0.count })
    }
}
