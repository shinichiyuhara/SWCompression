// LOCAL PATCH (fork): regression tests, security audit 2026-11-15 — ZIP
// (W16, W17, W22–W24, W36–W39).

import Foundation
import XCTest
import SWCompression

/// One local file header (30 bytes + name + extra).
func zipLocal(_ name: String, method: UInt16 = 0, flags: UInt16 = 0, crc: UInt32, comp: UInt32, uncomp: UInt32,
              extra: Data = Data()) -> Data {
    let nameBytes = Data(name.utf8)
    return cat(le(0x04034b50, 4), le(20, 2), le(UInt64(flags), 2), le(UInt64(method), 2), le(0, 4),
               le(UInt64(crc), 4), le(UInt64(comp), 4), le(UInt64(uncomp), 4),
               le(UInt64(nameBytes.count), 2), le(UInt64(extra.count), 2), nameBytes, extra)
}

/// One central directory entry (46 bytes + name + extra).
func zipCentral(_ name: String, method: UInt16 = 0, flags: UInt16 = 0, crc: UInt32, comp: UInt32, uncomp: UInt32,
                extra: Data = Data(), attributes: UInt32 = 0, localOffset: UInt32) -> Data {
    let nameBytes = Data(name.utf8)
    return cat(le(0x02014b50, 4), le(0x031E, 2), le(20, 2), le(UInt64(flags), 2), le(UInt64(method), 2), le(0, 4),
               le(UInt64(crc), 4), le(UInt64(comp), 4), le(UInt64(uncomp), 4),
               le(UInt64(nameBytes.count), 2), le(UInt64(extra.count), 2), le(0, 2), le(0, 2), le(0, 2),
               le(UInt64(attributes), 4), le(UInt64(localOffset), 4), nameBytes, extra)
}

/// The end of central directory record.
func zipEnd(count: Int, cdSize: Int, cdOffset: Int, comment: Data = Data()) -> Data {
    cat(le(0x06054b50, 4), le(0, 2), le(0, 2), le(UInt64(count), 2), le(UInt64(count), 2),
        le(UInt64(cdSize), 4), le(UInt64(cdOffset), 4), le(UInt64(comment.count), 2), comment)
}

/// A whole archive of stored entries (name, bytes), central directory last.
func zipStored(_ files: [(String, Data)], comment: Data = Data()) -> Data {
    var body = Data()
    var central = Data()
    for (name, bytes) in files {
        let offset = UInt32(body.count)
        let crc = crc32(bytes)
        body += zipLocal(name, crc: crc, comp: UInt32(bytes.count), uncomp: UInt32(bytes.count)) + bytes
        central += zipCentral(name, crc: crc, comp: UInt32(bytes.count), uncomp: UInt32(bytes.count),
                              localOffset: offset)
    }
    return body + central + zipEnd(count: files.count, cdSize: central.count, cdOffset: body.count, comment: comment)
}

final class ZipHardeningTests: XCTestCase {

    // MARK: - W16: bounds

    func testEndRecordOffsetsOutOfRange() {
        // The central directory at 0x100 of a 22-byte input.
        assertThrows(try ZipContainer.info(container: zipEnd(count: 1, cdSize: 46, cdOffset: 0x100)))
        // 0xFFFF entries asks for a ZIP64 locator 20 bytes before the start.
        assertThrows(try ZipContainer.info(container: zipEnd(count: 0xFFFF, cdSize: 0, cdOffset: 0)))
        // A central directory entry cut short by the end record.
        let cut = zipCentral("f", crc: 0, comp: 0, uncomp: 0, localOffset: 0).prefix(30)
        assertThrows(try ZipContainer.info(container: cut + zipEnd(count: 1, cdSize: 30, cdOffset: 0)))
    }

    /// A stored entry declaring 2 GiB in both headers: `info()` passed and
    /// `open()` copied past the end.
    func testStoredSizeBeyondInput() {
        let local = zipLocal("f", crc: 0, comp: 0x7FFF_FFFF, uncomp: 0x7FFF_FFFF) + Data("abc".utf8)
        let central = zipCentral("f", crc: 0, comp: 0x7FFF_FFFF, uncomp: 0x7FFF_FFFF, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
        assertThrows(try ZipContainer.open(container: archive))
    }

    // MARK: - W17: declared sizes bound the output; entries do not overlap

    func testDeflateBombStopsAtDeclaredSize() {
        let deflated = ZlibArchive.archive(data: Data(count: 2 << 20)).dropFirst(2).dropLast(4)
        let crc = crc32(Data([0]))
        let local = zipLocal("bomb", method: 8, crc: crc, comp: UInt32(deflated.count), uncomp: 1) + deflated
        let central = zipCentral("bomb", method: 8, crc: crc, comp: UInt32(deflated.count), uncomp: 1, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        XCTAssertEqual(try ZipContainer.info(container: archive).first?.size, 1)
        assertThrows(try ZipContainer.open(container: archive))
    }

    func testOverlappingEntriesRefused() {
        let bytes = Data("shared".utf8)
        let crc = crc32(bytes)
        let local = zipLocal("a", crc: crc, comp: 6, uncomp: 6) + bytes
        let one = zipCentral("a", crc: crc, comp: 6, uncomp: 6, localOffset: 0)
        let central = one + one
        let archive = local + central + zipEnd(count: 2, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    func testOpenLimit() throws {
        let archive = zipStored([("a", Data(count: 600)), ("b", Data(count: 600))])
        XCTAssertThrowsError(try ZipContainer.open(container: archive, limit: 1000)) { error in
            XCTAssertEqual((error as? DecompressionLimitExceeded)?.limit, 1000)
        }
        XCTAssertEqual(try ZipContainer.open(container: archive, limit: 1200).count, 2)
    }

    // MARK: - W22: data descriptors agree with the central directory

    /// Deflated `text` with a data descriptor; the central directory says
    /// `cdText`'s CRC and size.
    func describedEntry(_ text: String, central cdText: String, descriptorText: String? = nil) -> Data {
        let bytes = Data(text.utf8)
        let deflated = ZlibArchive.archive(data: bytes).dropFirst(2).dropLast(4)
        let described = Data((descriptorText ?? text).utf8)
        let cdBytes = Data(cdText.utf8)
        let local = zipLocal("f", method: 8, flags: 0x08, crc: 0, comp: 0, uncomp: 0) + deflated
            + cat(le(0x08074b50, 4), le(UInt64(crc32(described)), 4), le(UInt64(deflated.count), 4),
                  le(UInt64(described.count), 4))
        let central = zipCentral("f", method: 8, flags: 0x08, crc: crc32(cdBytes),
                                 comp: UInt32(deflated.count),
                                 uncomp: UInt32(cdBytes.count), localOffset: 0)
        return local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
    }

    func testDataDescriptorCannotOverride() throws {
        XCTAssertEqual(try ZipContainer.open(container: describedEntry("hello", central: "hello")).first?.data,
                       Data("hello".utf8))
        // The directory's CRC is for "hallo"; the data and its descriptor are
        // "hello". The descriptor's CRC was used and the data passed.
        assertThrows(try ZipContainer.open(container: describedEntry("hello", central: "hallo")))
    }

    /// The central directory says 3 bytes while the data and its descriptor
    /// say 11: `info()` showed 3 and `open()` returned 11.
    func testDescriptorSizeBeyondDirectory() {
        let archive = describedEntry("hello world", central: "hel")
        XCTAssertEqual(try ZipContainer.info(container: archive).first?.size, 3)
        assertThrows(try ZipContainer.open(container: archive))
    }

    // MARK: - W23, W24: ZIP64 and extra fields

    func zip64(_ values: UInt64...) -> Data {
        var body = Data()
        for v in values { body += le(v, 8) }
        return cat(le(0x0001, 2), le(UInt64(body.count), 2), body)
    }

    func testZip64SizeAboveIntMax() {
        let huge: UInt64 = 1 << 63
        let local = zipLocal("f", crc: 0, comp: 0xFFFF_FFFF, uncomp: 0xFFFF_FFFF, extra: zip64(huge, 0))
        let central = zipCentral("f", crc: 0, comp: 0, uncomp: 0xFFFF_FFFF, extra: zip64(huge), localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    func testZip64FieldTooShort() {
        let local = zipLocal("f", crc: 0, comp: 0, uncomp: 0)
        let central = zipCentral("f", crc: 0, comp: 0, uncomp: 0xFFFF_FFFF, extra: cat(le(0x0001, 2), le(0, 2)),
                                 localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    /// An NTFS field of 8 bytes at the very end of the central directory: 32
    /// bytes were read regardless, past the end of the input.
    func testShortNtfsFieldIgnored() throws {
        let bytes = Data("x".utf8)
        let crc = crc32(bytes)
        let local = zipLocal("f", crc: crc, comp: 1, uncomp: 1) + bytes
        // Reserved, then attribute tag 1 of 24 bytes — which the field does
        // not hold; the end record follows.
        let ntfs = cat(le(0x000A, 2), le(8, 2), le(0, 4), le(1, 2), le(24, 2))
        let central = zipCentral("f", crc: crc, comp: 1, uncomp: 1, extra: ntfs, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        XCTAssertEqual(try ZipContainer.open(container: archive).first?.data, bytes)
    }

    /// An extra field whose length runs past the extra area is refused.
    func testExtraFieldPastItsArea() {
        let local = zipLocal("f", crc: 0, comp: 0, uncomp: 0)
        let central = zipCentral("f", crc: 0, comp: 0, uncomp: 0, extra: cat(le(0x5455, 2), le(200, 2), bytes(0x01)),
                                 localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    // MARK: - W36: one interpretation

    func testLocalNameMustMatch() {
        let bytes = Data("x".utf8)
        let crc = crc32(bytes)
        let local = zipLocal("evil.sh", crc: crc, comp: 1, uncomp: 1) + bytes
        let central = zipCentral("readme", crc: crc, comp: 1, uncomp: 1, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    func testLocalSizesMustMatch() {
        let bytes = Data("xy".utf8)
        let crc = crc32(bytes)
        let local = zipLocal("f", crc: crc, comp: 2, uncomp: 2) + bytes
        let central = zipCentral("f", crc: crc, comp: 1, uncomp: 1, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        assertThrows(try ZipContainer.info(container: archive))
    }

    func testUnicodePathField() throws {
        let plain = "caf?"
        let unicode = "café"
        let field = cat(bytes(0x01), le(UInt64(crc32(Data(plain.utf8))), 4), Data(unicode.utf8))
        let local = zipLocal(plain, crc: 0, comp: 0, uncomp: 0)
        let central = zipCentral(plain, crc: 0, comp: 0, uncomp: 0,
                                 extra: cat(le(0x7075, 2), le(UInt64(field.count), 2), field), localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        XCTAssertEqual(try ZipContainer.info(container: archive).first?.name, unicode)
    }

    /// A comment that holds an end-record signature: the record whose comment
    /// ends the input is the real one.
    func testEndRecordInsideComment() throws {
        let fake = zipEnd(count: 1, cdSize: 46, cdOffset: 0x7000_0000)
        let real = zipStored([("f", Data("data".utf8))], comment: fake)
        XCTAssertEqual(try ZipContainer.open(container: real).first?.data, Data("data".utf8))
    }

    // MARK: - W37, W38, W39

    func testNoEndRecordIsQuick() {
        let start = Date()
        assertThrows(try ZipContainer.info(container: Data(count: 32 << 20)))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testTrailingSlashIsDirectory() throws {
        let local = zipLocal("dir/", crc: 0, comp: 0, uncomp: 0)
        let central = zipCentral("dir/", crc: 0, comp: 0, uncomp: 0, attributes: 0, localOffset: 0)
        let archive = local + central + zipEnd(count: 1, cdSize: central.count, cdOffset: local.count)
        XCTAssertEqual(try ZipContainer.info(container: archive).first?.type, .directory)
    }

    func testSlicedZip() throws {
        let archive = zipStored([("f", Data("data".utf8))])
        let slice = (Data(count: 100) + archive)[100...]
        XCTAssertEqual(try ZipContainer.open(container: slice).first?.data, Data("data".utf8))
    }
}
