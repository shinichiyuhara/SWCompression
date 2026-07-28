// LOCAL ADDITION — not part of upstream SWCompression.
// See README.md ("Differences from upstream").
//
// Copyright (c) 2026 Shinichi Yuhara.
// Contributed under the same MIT License as the surrounding project.
//
// ---------------------------------------------------------------------------
// A progress sink for long decodes.
//
// Why this exists: SWCompression decodes a 7z folder in ONE call
// (`SevenZipContainer.open` -> `folder.unpack` -> `LZMA2.decompress`), and a
// solid archive is usually a single folder. Nothing is yielded until the whole
// thing is done, so a host app's progress bar sits at 0% for the entire decode
// and then jumps to 100% — a user reasonably reads that as "nothing is
// happening" and cancels. (One did.)
//
// Why a thread-local sink rather than an extra parameter: the alternative is
// threading a closure through SevenZipContainer.open -> SevenZipFolder.unpack
// -> LZMA2.decompress -> LZMA2Decoder.decode, i.e. editing four upstream files.
// This fork's whole maintenance argument is that the patch stays small enough
// to re-apply by hand at every version bump, so the cost is paid here instead:
// one line in LZMA2Decoder's chunk loop, one in LZMAFraming's output loop, and
// everything else lives in this file, which upstream does not have and
// therefore cannot conflict with.
//
// BOTH tick sites are required. The system fast path decodes a whole folder in
// one framework call and never enters LZMA2Decoder's loop, so ticking only
// there means the bar freezes precisely when decoding is fastest.
//
// Thread-local, not global, because a host app may decode several archives
// concurrently and a shared sink would interleave them. SWCompression decodes
// synchronously on the calling thread and spawns none of its own, so the sink
// set by `withSink` is the one the decoder sees.

import Foundation

/// Reports bytes produced so far during a long decode.
public enum DecodeProgress {

    // Namespaced to the library, not to any host app — matching the sibling key
    // in `noteFallback` below. Thread-dictionary keys only need to be unique
    // within the process, so the short form suffices.
    fileprivate static let key = "swcompression.decode.progress"

    /// Box so the closures survive in the (Objective-C) thread dictionary.
    private final class Sink {
        let report: (Int) -> Void
        let fallback: ((String) -> Void)?
        init(_ report: @escaping (Int) -> Void, _ fallback: ((String) -> Void)?) {
            self.report = report
            self.fallback = fallback
        }
    }

    /// Run `body` with `report` receiving the running count of decoded bytes.
    ///
    /// `onFallback`, if given, is called with the coder name when the system
    /// decoder declines a stream and the pure-Swift path runs instead. Pass it
    /// to route that into a real log: the default writes to stderr, which in a
    /// GUI app nobody ever reads.
    ///
    /// Nested calls are supported: the previous sink is restored on exit, so an
    /// inner decode cannot leave a stale sink installed for the outer one.
    public static func withSink<T>(_ report: @escaping (Int) -> Void,
                                   onFallback: ((String) -> Void)? = nil,
                                   _ body: () throws -> T) rethrows -> T {
        let dict = Thread.current.threadDictionary
        let previous = dict[key]
        dict[key] = Sink(report, onFallback)
        defer { dict[key] = previous }
        return try body()
    }

    /// Called from the decoder's chunk loop. A no-op when no sink is installed,
    /// which is the case for every caller that has not opted in (tests,
    /// `swift build` consumers, and every format that decodes fast enough not
    /// to need it).
    @inline(__always)
    static func tick(_ bytesProduced: Int) {
        guard let sink = Thread.current.threadDictionary[key] as? Sink else { return }
        sink.report(bytesProduced)
    }
}

extension DecodeProgress {
    /// Record that the fast (system) LZMA path declined a stream and the
    /// pure-Swift decoder ran instead.
    ///
    /// Visibility is deliberate: falling back silently means
    /// "why is 7z still slow?" has no answer in the log, and a framing bug that
    /// disables the fast path everywhere would look exactly like success.
    /// Thread-local like the progress sink, so concurrent jobs do not mix.
    ///
    /// Goes to the host's `onFallback` when one was installed, and to stderr
    /// otherwise. stderr alone is not enough for a GUI app — the message lands
    /// where no user or bug report will ever include it.
    static func noteFallback(_ coder: String) {
        let key = "swcompression.lzma.fallback"
        let d = Thread.current.threadDictionary
        let count = (d[key] as? Int ?? 0) + 1
        d[key] = count
        guard count <= 3 else { return }   // once per coder is the signal; a flood is noise
        if let sink = d[Self.key] as? Sink, let report = sink.fallback {
            report(coder)
        } else {
            FileHandle.standardError.write(
                Data("LZMAFraming: fell back to pure-Swift \(coder) decoder\n".utf8))
        }
    }
}
