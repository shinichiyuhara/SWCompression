// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

struct DecodingTree {

    // LOCAL PATCH (fork): the tree is kept as linked nodes, two child slots per
    // node, instead of a complete binary tree of 2^(maxBits+1) - 1 slots. The
    // complete tree cost 2^21 slots (16 MiB) for a code of length 20, which
    // BZip2 allows; rebuilt for every block, six tables per block, a stream of
    // small blocks spent about 100 MB of fills per 50 input bytes without
    // producing output, so `limit` could not stop it (security audit
    // 2026-11-15, W20; Deflate's per-block rebuild, W31, gets cheaper too).
    // The node count is at most the total of the code lengths.
    //
    // A slot holds -1 (empty), a node index (>= 0), or a leaf as
    // -(symbol + 2). Overlapping (non-prefix) codes, which only invalid input
    // has, resolve as before: the shorter code wins, and of equal codes the
    // last one.

    private let bitReader: BitReader

    private let children: [Int]

    init(_ huffmanCodes: HuffmanCodes, _ bitReader: BitReader) {
        self.bitReader = bitReader

        var children = [-1, -1]
        for code in huffmanCodes.codes where code.bits > 0 {
            // Put code in its place in the tree, least significant bit first.
            var treeCode = code.code
            var node = 0
            var bit = 0
            var reachable = true
            for _ in 1..<code.bits {
                bit = treeCode & 1
                treeCode >>= 1
                let next = children[2 * node + bit]
                if next >= 0 {
                    node = next
                } else if next == -1 {
                    let new = children.count / 2
                    children.append(-1)
                    children.append(-1)
                    children[2 * node + bit] = new
                    node = new
                } else {
                    // A shorter code is a prefix of this one: it wins.
                    reachable = false
                    break
                }
            }
            if reachable {
                children[2 * node + (treeCode & 1)] = -(code.symbol + 2)
            }
        }
        self.children = children
    }

    func findNextSymbol() -> Int {
        var bitsLeft = bitReader.bitsLeft
        var node = 0
        while bitsLeft > 0 {
            let next = self.children[2 * node + Int(bitReader.bit())]
            bitsLeft -= 1
            if next < -1 {
                return -next - 2
            }
            guard next >= 0
                else { return -1 }
            node = next
        }
        return -1
    }

}
