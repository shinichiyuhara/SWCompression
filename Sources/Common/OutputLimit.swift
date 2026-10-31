// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

// LOCAL PATCH (fork): output ceilings for decoders whose caller knows how much
// they must produce (7-Zip's per-coder unpack sizes). Without one, Deflate,
// BZip2 and the pure-Swift LZMA2 path decode as far as the stream goes and the
// size is compared only afterwards — so a header that claims a few bytes cannot
// stop a stream that expands to gigabytes.

/// Thrown when a decoder would produce more than its caller allowed.
struct OutputLimitExceeded: Error {}

/// LOCAL PATCH (fork): the public form of `OutputLimitExceeded`, thrown by the
/// entry points where the host chooses the limit, such as
/// `BZip2.decompress(data:limit:)`.
public struct DecompressionLimitExceeded: Error {
    public let limit: Int
}
