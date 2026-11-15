// LOCAL PATCH (fork): regression tests, security audit 2026-11-15.

import Foundation
import XCTest
import SWCompression

final class TarHardeningTests: XCTestCase {

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swc-hardening-\(UUID().uuidString).tar")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func readAll(_ url: URL) throws -> [TarEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var reader = TarReader(fileHandle: handle)
        var entries = [TarEntry]()
        while let entry = try reader.read() { entries.append(entry) }
        return entries
    }

    /// W14: a global header of K unknown records, then N entries that each have
    /// a local unknown record. Each entry used to receive its own merged copy of
    /// all K (quadratic memory); past the budget this now throws.
    func testGlobalUnknownRecordsAreBudgeted() throws {
        var global = Data()
        for i in 0..<3_000 { global.append(paxRecord(String(format: "k%07d", i), "")) }
        var tar = paxEntry(global, global: true)
        for i in 0..<400 {
            tar.append(paxEntry(paxRecord("zz", "yy")))
            tar.append(tarHeader(name: "f\(i)", size: 0))
        }
        tar.append(Data(count: 1024))
        assertThrows(try TarContainer.info(container: tar))
        assertThrows(try TarContainer.open(container: tar))
        assertThrows(try readAll(temporaryFile(tar)))
    }

    /// W14: a local header without unknown records shares the global ones
    /// instead of copying them, and is not charged to the budget.
    func testGlobalUnknownRecordsSharedWithoutLocalOnes() throws {
        var global = Data()
        for i in 0..<3_000 { global.append(paxRecord(String(format: "k%07d", i), "")) }
        var tar = paxEntry(global, global: true)
        for i in 0..<400 {
            tar.append(paxEntry(paxRecord("path", "dir/f\(i)")))
            tar.append(tarHeader(name: "f\(i)", size: 0))
        }
        tar.append(Data(count: 1024))
        let infos = try TarContainer.info(container: tar)
        XCTAssertEqual(infos.count, 400)
        XCTAssertEqual(infos[399].name, "dir/f399")
        XCTAssertEqual(infos[399].unknownExtendedHeaderRecords?.count, 3_000)
    }

    /// W21: the PAX size (512) is smaller than the header's (1024). POSIX readers
    /// take the PAX size, so the second block is the next header. Skipping by the
    /// header size hid that entry from SWCompression.
    func testPaxSizeGovernsTheSkip() throws {
        var tar = paxEntry(paxRecord("size", "512"))
        tar.append(tarHeader(name: "a", size: 1024))
        tar.append(Data(repeating: 0x41, count: 512))
        tar.append(tarHeader(name: "hidden", size: 3))
        tar.append(tarPadded(Data("xyz".utf8)))
        tar.append(Data(count: 1024))

        let infos = try TarContainer.info(container: tar)
        XCTAssertEqual(infos.map(\.name), ["a", "hidden"])
        XCTAssertEqual(infos.map(\.size), [512, 3])
        let entries = try TarContainer.open(container: tar)
        XCTAssertEqual(entries.map(\.info.name), ["a", "hidden"])
        XCTAssertEqual(entries[0].data, Data(repeating: 0x41, count: 512))
        XCTAssertEqual(entries[1].data, Data("xyz".utf8))
        let read = try readAll(temporaryFile(tar))
        XCTAssertEqual(read.map(\.info.name), ["a", "hidden"])
        XCTAssertEqual(read.map(\.data), entries.map(\.data))
    }

    /// W21: a global `size` record made every following size-0 entry slice the
    /// same trailing bytes — each a separate copy in `open` (1 GB from a 1.5 MB
    /// tar). Skipping by that same size, the first entry's data swallows the
    /// headers after it, as GNU tar reads it, and the bytes are copied once.
    func testGlobalPaxSizeDoesNotOverlapEntries() throws {
        var tar = paxEntry(paxRecord("size", "65536"), global: true)
        for i in 0..<64 { tar.append(tarHeader(name: "f\(i)", size: 0)) }
        tar.append(Data(count: 65536 + 1024))
        let infos = try TarContainer.info(container: tar)
        XCTAssertEqual(infos.map(\.name), ["f0"])
        let entries = try TarContainer.open(container: tar)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].data?.count, 65536)
    }

    /// W15: 2,000 size-0 `L` (GNU long name) headers before a file. `read()`
    /// recursed once per special entry and overflowed a 512 KiB stack.
    func testManySpecialEntriesDoNotRecurse() throws {
        var tar = Data()
        for _ in 0..<2_000 { tar.append(tarHeader(name: "././@LongLink", size: 0, type: "L")) }
        tar.append(tarHeader(name: "a", size: 0))
        tar.append(Data(count: 1024))
        let url = try temporaryFile(tar)
        let entries = try onSmallStack { try self.readAll(url) }
        XCTAssertEqual(entries.count, 1)
    }

    /// Q2: a negative base-256 size reached `FileHandle.read(upToCount:)`.
    func testNegativeSizeInReaderThrows() throws {
        var header = [UInt8](tarHeader(name: "neg", size: 0))
        // base-256: high bit set, all ones = -1
        for i in 124..<136 { header[i] = 0xFF }
        for i in 148..<156 { header[i] = 0x20 }
        let sum = header.reduce(0) { $0 + Int($1) }
        let checksum = Array(String(format: "%06o", sum).utf8)
        for (i, b) in checksum.enumerated() { header[148 + i] = b }
        header[154] = 0
        header[155] = 0x20
        var tar = Data(header)
        tar.append(Data(count: 1024))
        let url = try temporaryFile(tar)
        assertThrows(try readAll(url))
    }

    /// Ordinary archives, including PAX ones, still read the same through all
    /// three entry points.
    func testRoundTrip() throws {
        var a = TarEntryInfo(name: "dir/a.txt", type: .regular)
        a.unknownExtendedHeaderRecords = ["SCHILY.xattr.user.k": "v"]
        let entries = [
            TarEntry(info: TarEntryInfo(name: "dir", type: .directory), data: nil),
            TarEntry(info: a, data: Data("hello".utf8)),
            TarEntry(info: TarEntryInfo(name: String(repeating: "n", count: 150), type: .regular),
                     data: Data(repeating: 7, count: 1000)),
        ]
        let tar = TarContainer.create(from: entries)
        let opened = try TarContainer.open(container: tar)
        XCTAssertEqual(opened.map(\.info.name), entries.map(\.info.name))
        XCTAssertEqual(opened.map(\.data), [nil, Data("hello".utf8), Data(repeating: 7, count: 1000)])
        XCTAssertEqual(opened[1].info.unknownExtendedHeaderRecords?["SCHILY.xattr.user.k"], "v")
        let read = try readAll(temporaryFile(tar))
        XCTAssertEqual(read.map(\.info.name), entries.map(\.info.name))
        XCTAssertEqual(read.map(\.data), opened.map(\.data))
    }
}
