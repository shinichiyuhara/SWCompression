// LOCAL PATCH (fork): helpers for the hardening regression tests.
//
// Each test feeds a hand-built hostile input to a public entry point and asks
// only that it *throws*. Before the matching fix the same input trapped (an
// uncatchable Swift runtime error that takes the whole test process down), so
// a regression shows up as a crashed test run rather than a failed assertion.
// The findings are in docs/security/audit-20261115.md.

import Foundation
import XCTest

/// Bytes from a hex string; whitespace is ignored.
func hex(_ string: String) -> Data {
    let digits = Array(string.filter { !$0.isWhitespace })
    precondition(digits.count % 2 == 0, "odd number of hex digits")
    var data = Data(capacity: digits.count / 2)
    var i = 0
    while i < digits.count {
        data.append(UInt8(String(digits[i...i + 1]), radix: 16)!)
        i += 2
    }
    return data
}

/// Asserts that `body` throws. Reaching the assertion at all is the point: the
/// input used to trap before it could throw.
func assertThrows<T>(_ body: @autoclosure () throws -> T,
                     _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try body(), message, file: file, line: line)
}
