// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

extension LittleEndianByteReader {

    func multiByteDecode() throws -> Int {
        // Reading past the end of the buffer is a Swift trap, not a throwable
        // error, so a truncated varint would crash the process. Refuse when no
        // byte remains — every caller already handles multiByteIntegerError.
        guard !self.isFinished
            else { throw XZError.multiByteIntegerError }
        var i = 1
        var result = self.byte().toInt()
        if result <= 127 {
            return result
        }
        result &= 0x7F
        while true {
            guard !self.isFinished
                else { throw XZError.multiByteIntegerError }
            let byte = self.byte()
            if i >= 9 || byte == 0x00 {
                throw XZError.multiByteIntegerError
            }
            result += (byte.toInt() & 0x7F) << (7 * i)
            i += 1

            if byte & 0x80 == 0 {
                break
            }
        }
        return result
    }

}
