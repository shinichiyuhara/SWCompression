// LOCAL ADDITION — not part of upstream SWCompression.
// See README.md ("Differences from upstream").
//
// Copyright (c) 2026 Shinichi Yuhara.
// Contributed under the same MIT License as the surrounding project.
//
// ---------------------------------------------------------------------------
// 7-Zip branch-converter ("BCJ") filters — DECODE ONLY.
//
// A branch filter rewrites the relative call/jump targets in machine code into
// absolute ones before compression, so that repeated calls to the same routine
// become identical byte sequences and the entropy coder can exploit them.
// It is not a compressor: it is a reversible permutation applied either side of
// LZMA/LZMA2, and the archive is unreadable without it.
//
// 7-Zip applies these AUTOMATICALLY when the input looks like an executable, so
// "a .7z containing a program" is the common case, not an exotic one. Upstream
// SWCompression implements none of them (checked through 4.9.1) and throws
// `compressionNotSupported`, which is why such archives could not be opened.
//
// The algorithms are ports of XZ Utils' `src/liblzma/simple/*.c`, which is in
// the public domain and is the same filter specification 7-Zip implements.
// Only the decode direction is implemented — this fork does not create 7z.
//
// NOT implemented, and deliberately so:
//   * BCJ2 (id 0303011B) — a four-input-stream coder; the folder decoder
//     rejects multi-stream coders before reaching a filter at all.
//   * IA64 (Itanium) and RISC-V — the two most intricate of the family, for
//     targets that do not plausibly appear in a macOS user's archives.
// Both still surface as `compressionNotSupported`, which is honest: they are
// unsupported, not silently mis-decoded.

import Foundation

/// The branch filters, keyed by the coder ID they answer to.
enum BranchFilter {

    /// Resolve a 7z coder ID to a filter. Returns nil when the ID is not a
    /// branch converter this file implements.
    ///
    /// 7-Zip has two ID schemes for the same filters: a legacy four-byte form
    /// (`03 03 01 03`) and a modern one-byte form (`04`). Archives in the wild
    /// carry either — the file that prompted this work uses the legacy form —
    /// so both are matched.
    static func decoder(for id: [UInt8]) -> ((inout [UInt8]) -> Void)? {
        switch id {
        case [0x04], [0x03, 0x03, 0x01, 0x03]:
            return x86
        case [0x05], [0x03, 0x03, 0x02, 0x05]:
            return powerPC
        case [0x07], [0x03, 0x03, 0x05, 0x01]:
            return arm
        case [0x08], [0x03, 0x03, 0x07, 0x01]:
            return armThumb
        case [0x09], [0x03, 0x03, 0x08, 0x05]:
            return sparc
        case [0x0A]:
            return arm64
        default:
            return nil
        }
    }

    /// True when `b` is 0x00 or 0xFF — the only two high bytes a *near* x86
    /// call displacement can have, which is what makes the filter reversible.
    @inline(__always)
    private static func isX86MSByte(_ b: UInt8) -> Bool { b == 0x00 || b == 0xFF }

    // MARK: - x86

    /// x86 CALL/JMP (E8/E9) relative→absolute converter.
    ///
    /// Faithful port of XZ Utils `x86.c`. The mask bookkeeping exists because
    /// an E8/E9 byte can occur *inside* a previously converted displacement;
    /// the filter therefore has to remember which of the last few positions
    /// were themselves rewritten, or encode and decode disagree. Do not
    /// "simplify" it — the state machine is the specification.
    static func x86(_ buffer: inout [UInt8]) {
        // MASK_TO_ALLOWED_STATUS / MASK_TO_BIT_NUMBER from x86.c.
        let allowed: [Bool] = [true, true, true, false, true, false, false, false]
        let bitNumber: [UInt32] = [0, 1, 2, 2, 3, 3, 3, 3]

        let size = buffer.count
        guard size >= 5 else { return }

        var prevMask: UInt32 = 0
        // x86_coder_init() seeds this to (uint32_t)-5 so the first instruction
        // is treated as having no converted predecessor.
        var prevPos: UInt32 = 0 &- 5
        let nowPos: UInt32 = 0   // 7z applies the filter to the whole folder at once

        let limit = size - 5
        var pos = 0

        while pos <= limit {
            let b0 = buffer[pos]
            if b0 != 0xE8 && b0 != 0xE9 {
                pos += 1
                continue
            }

            let offset = nowPos &+ UInt32(pos) &- prevPos
            prevPos = nowPos &+ UInt32(pos)

            if offset > 5 {
                prevMask = 0
            } else {
                var i: UInt32 = 0
                while i < offset {
                    prevMask &= 0x77
                    prevMask <<= 1
                    i += 1
                }
            }

            var b = buffer[pos + 4]

            if isX86MSByte(b)
                && allowed[Int((prevMask >> 1) & 0x7)]
                && (prevMask >> 1) < 0x10 {

                var src = (UInt32(b) << 24)
                    | (UInt32(buffer[pos + 3]) << 16)
                    | (UInt32(buffer[pos + 2]) << 8)
                    | UInt32(buffer[pos + 1])

                var dest: UInt32
                while true {
                    // Decode direction: absolute → relative.
                    dest = src &- (nowPos &+ UInt32(pos) &+ 5)

                    if prevMask == 0 { break }

                    let i = bitNumber[Int(prevMask >> 1)]
                    b = UInt8truncating(dest >> (24 - i * 8))
                    if !isX86MSByte(b) { break }
                    src = dest ^ ((1 << (32 - i * 8)) &- 1)
                }

                // The top byte is not stored: it is recomputed as a sign
                // extension of bit 24, which is what makes the 5-byte
                // instruction round-trip.
                buffer[pos + 4] = UInt8truncating(~(((dest >> 24) & 1) &- 1))
                buffer[pos + 3] = UInt8truncating(dest >> 16)
                buffer[pos + 2] = UInt8truncating(dest >> 8)
                buffer[pos + 1] = UInt8truncating(dest)
                pos += 5
                prevMask = 0
            } else {
                prevMask |= 0x01
                if isX86MSByte(b) { prevMask |= 0x10 }
                pos += 1
            }
        }
    }

    // MARK: - Fixed-width RISC filters
    //
    // These have no state: every candidate instruction is independent, so each
    // is a straight scan at the architecture's instruction alignment.

    /// ARM BL (little-endian, 4-byte aligned, 24-bit word displacement).
    static func arm(_ buffer: inout [UInt8]) {
        var i = 0
        while i + 4 <= buffer.count {
            if buffer[i + 3] == 0xEB {
                var src = (UInt32(buffer[i + 2]) << 16)
                    | (UInt32(buffer[i + 1]) << 8)
                    | UInt32(buffer[i])
                src <<= 2
                var dest = src &- (UInt32(i) &+ 8)
                dest >>= 2
                buffer[i + 2] = UInt8truncating(dest >> 16)
                buffer[i + 1] = UInt8truncating(dest >> 8)
                buffer[i]     = UInt8truncating(dest)
            }
            i += 4
        }
    }

    /// ARM-Thumb BL pair (two 16-bit halves, 2-byte aligned, 22-bit halfword
    /// displacement). Only the F0..F7 / F8..FF encoding is a long branch.
    static func armThumb(_ buffer: inout [UInt8]) {
        var i = 0
        while i + 4 <= buffer.count {
            if (buffer[i + 1] & 0xF8) == 0xF0 && (buffer[i + 3] & 0xF8) == 0xF8 {
                var src = ((UInt32(buffer[i + 1]) & 0x7) << 19)
                    | (UInt32(buffer[i]) << 11)
                    | ((UInt32(buffer[i + 3]) & 0x7) << 8)
                    | UInt32(buffer[i + 2])
                src <<= 1
                var dest = src &- (UInt32(i) &+ 4)
                dest >>= 1
                buffer[i + 1] = UInt8truncating(0xF0 | ((dest >> 19) & 0x7))
                buffer[i]     = UInt8truncating(dest >> 11)
                buffer[i + 3] = UInt8truncating(0xF8 | ((dest >> 8) & 0x7))
                buffer[i + 2] = UInt8truncating(dest)
                i += 2   // consumed both halves
            }
            i += 2
        }
    }

    /// PowerPC branch (big-endian, 4-byte aligned; primary opcode 18, AA=0).
    static func powerPC(_ buffer: inout [UInt8]) {
        var i = 0
        while i + 4 <= buffer.count {
            if (buffer[i] & 0xFC) == 0x48 && (buffer[i + 3] & 0x3) == 1 {
                let src = ((UInt32(buffer[i]) & 0x3) << 24)
                    | (UInt32(buffer[i + 1]) << 16)
                    | (UInt32(buffer[i + 2]) << 8)
                    | (UInt32(buffer[i + 3]) & 0xFC)
                let dest = src &- UInt32(i)
                buffer[i]     = UInt8truncating(0x48 | ((dest >> 24) & 0x3))
                buffer[i + 1] = UInt8truncating(dest >> 16)
                buffer[i + 2] = UInt8truncating(dest >> 8)
                buffer[i + 3] = UInt8truncating((UInt32(buffer[i + 3]) & 0x3) | dest)
            }
            i += 4
        }
    }

    /// SPARC CALL (big-endian, 4-byte aligned, 30-bit word displacement).
    static func sparc(_ buffer: inout [UInt8]) {
        var i = 0
        while i + 4 <= buffer.count {
            if (buffer[i] == 0x40 && (buffer[i + 1] & 0xC0) == 0x00)
                || (buffer[i] == 0x7F && (buffer[i + 1] & 0xC0) == 0xC0) {
                var src = (UInt32(buffer[i]) << 24)
                    | (UInt32(buffer[i + 1]) << 16)
                    | (UInt32(buffer[i + 2]) << 8)
                    | UInt32(buffer[i + 3])
                src <<= 2
                var dest = src &- UInt32(i)
                dest >>= 2
                // Re-encode the sign so the 30-bit field sits back inside a
                // valid CALL word.
                dest = ((0x4000_0000 &- (dest & 0x40_0000)) | 0x4000_0000 | (dest & 0x3F_FFFF))
                buffer[i]     = UInt8truncating(dest >> 24)
                buffer[i + 1] = UInt8truncating(dest >> 16)
                buffer[i + 2] = UInt8truncating(dest >> 8)
                buffer[i + 3] = UInt8truncating(dest)
            }
            i += 4
        }
    }

    /// ARM64 BL and ADRP (little-endian, 4-byte aligned).
    ///
    /// Port of XZ Utils `arm64.c`. ADRP is included because a page-relative
    /// address is as compressible as a call target; the `0x001C0000` guard
    /// skips ADRPs whose immediate is too far to benefit, exactly as upstream
    /// does — skipping a different set would desynchronise from the encoder.
    static func arm64(_ buffer: inout [UInt8]) {
        var i = 0
        while i + 4 <= buffer.count {
            var instr = UInt32(buffer[i])
                | (UInt32(buffer[i + 1]) << 8)
                | (UInt32(buffer[i + 2]) << 16)
                | (UInt32(buffer[i + 3]) << 24)

            if (instr >> 26) == 0x25 {
                // BL: 26-bit word displacement.
                let src = instr
                instr = 0x9400_0000
                var pc = UInt32(i)
                pc >>= 2
                pc = 0 &- pc          // decode direction
                instr |= (src &+ pc) & 0x03FF_FFFF
                store32(&buffer, i, instr)
            } else if (instr & 0x9F00_0000) == 0x9000_0000 {
                // ADRP: 21-bit page displacement, split across two fields.
                let src = ((instr >> 29) & 3) | ((instr >> 3) & 0x001F_FFFC)
                if ((src &+ 0x0002_0000) & 0x001C_0000) != 0 {
                    i += 4
                    continue
                }
                instr &= 0x9000_001F
                var pc = UInt32(i)
                pc >>= 12
                pc = 0 &- pc          // decode direction
                let dest = src &+ pc
                instr |= (dest & 3) << 29
                instr |= (dest & 0x0003_FFFC) << 3
                instr |= (0 &- (dest & 0x0002_0000)) & 0x00E0_0000
                store32(&buffer, i, instr)
            }
            i += 4
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func store32(_ buffer: inout [UInt8], _ i: Int, _ v: UInt32) {
        buffer[i]     = UInt8truncating(v)
        buffer[i + 1] = UInt8truncating(v >> 8)
        buffer[i + 2] = UInt8truncating(v >> 16)
        buffer[i + 3] = UInt8truncating(v >> 24)
    }
}

/// `UInt8(truncatingIfNeeded:)` spelled short — these filters truncate on every
/// store, and the long form buries the arithmetic.
@inline(__always)
private func UInt8truncating(_ v: UInt32) -> UInt8 {
    UInt8(truncatingIfNeeded: v)
}
