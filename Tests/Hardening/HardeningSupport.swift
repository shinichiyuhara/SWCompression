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

// MARK: - TAR builder

/// One 512-byte ustar header block with a valid checksum.
func tarHeader(name: String, size: Int, type: Character = "0") -> Data {
    var h = [UInt8](repeating: 0, count: 512)
    func put(_ string: String, at offset: Int) {
        for (i, b) in string.utf8.enumerated() { h[offset + i] = b }
    }
    put(name, at: 0)
    put("0000644", at: 100)
    put("0000000", at: 108)
    put("0000000", at: 116)
    put(String(format: "%011o", size), at: 124)
    put("00000000000", at: 136)
    put(String(type), at: 156)
    put("ustar", at: 257)
    put("00", at: 263)
    put("        ", at: 148)
    let sum = h.reduce(0) { $0 + Int($1) }
    put(String(format: "%06o", sum), at: 148)
    h[154] = 0
    h[155] = 0x20
    return Data(h)
}

/// `data` padded with zeros to a whole number of 512-byte blocks.
func tarPadded(_ data: Data) -> Data {
    var d = data
    let rem = d.count % 512
    if rem != 0 { d.append(Data(count: 512 - rem)) }
    return d
}

/// One PAX record, `"<len> <key>=<value>\n"`, with the length counting itself.
func paxRecord(_ key: String, _ value: String) -> Data {
    let body = " \(key)=\(value)\n"
    var length = body.utf8.count + 1
    while String(length).utf8.count + body.utf8.count != length {
        length = String(length).utf8.count + body.utf8.count
    }
    return Data((String(length) + body).utf8)
}

/// A PAX extended header entry (`x` local, `g` global) carrying `records`.
func paxEntry(_ records: Data, global: Bool = false) -> Data {
    tarHeader(name: global ? "pax_global" : "pax_local", size: records.count, type: global ? "g" : "x")
        + tarPadded(records)
}

/// Runs `body` on a thread with a 512 KiB stack (GCD's secondary-thread size),
/// where unbounded recursion overflows first.
func onSmallStack<T>(_ body: @escaping () throws -> T) throws -> T {
    var result: Result<T, Error>?
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        result = Result { try body() }
        done.signal()
    }
    thread.stackSize = 512 * 1024
    thread.start()
    done.wait()
    return try result!.get()
}
