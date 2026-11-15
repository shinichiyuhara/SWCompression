// LOCAL PATCH (fork): regression tests, security audit 2026-11-15.

import Foundation
import XCTest
import SWCompression

final class BZip2HardeningTests: XCTestCase {

    /// W3: a block declaring zero selectors (two tables, one used symbol).
    /// `tables[selectors[0]]` indexed an empty array.
    static let zeroSelectors = hex("425a683931415926535900000000000000400040002000020200")

    /// W4: the last symbol of the first table is driven to code length 63 by
    /// repeated "+1" deltas after the only range check. `DecodingTree` then
    /// asked for an array of count -1.
    static let lastLengthUnchecked = hex("425a6839314159265359000000000000004000400020002a1555555555555555555555020037")

    func testZeroSelectorsThrows() {
        assertThrows(try BZip2.decompress(data: Self.zeroSelectors))
        assertThrows(try BZip2.decompress(data: Self.zeroSelectors, limit: 1000))
        assertThrows(try BZip2.multiDecompress(data: Self.zeroSelectors))
    }

    func testUncheckedLastCodeLengthThrows() {
        assertThrows(try BZip2.decompress(data: Self.lastLengthUnchecked))
        assertThrows(try BZip2.decompress(data: Self.lastLengthUnchecked, limit: 1000))
    }

    /// Valid streams still decode after the added checks.
    func testRoundTrip() throws {
        var input = Data()
        for i in 0..<200_000 { input.append(UInt8(truncatingIfNeeded: i &* 7 &+ i / 13)) }
        input.append(Data(repeating: 0x41, count: 50_000))
        let compressed = BZip2.compress(data: input)
        XCTAssertEqual(try BZip2.decompress(data: compressed), input)
        XCTAssertEqual(try BZip2.decompress(data: compressed, limit: input.count), input)
    }
}
