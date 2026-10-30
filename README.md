# SWCompression (fork)

> **This is a fork of [tsolomko/SWCompression](https://github.com/tsolomko/SWCompression), branched at
> release 4.9.1.** It adds 7-Zip BCJ branch filters and an Apple-platform fast path for LZMA/LZMA2.
> See [Differences from upstream](#differences-from-upstream) below. Everything else — including this
> README from here down — is upstream's.
>
> Upstream is the place to file issues about the library in general; this fork exists only to carry
> the changes listed below until (and if) they land upstream.

---

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-blue.svg)](https://developer.apple.com/swift/)
[![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/tsolomko/SWCompression/master/LICENSE)
[![Build Status](https://dev.azure.com/tsolomko/SWCompression/_apis/build/status/tsolomko.SWCompression?branchName=develop)](https://dev.azure.com/tsolomko/SWCompression/_build/latest?definitionId=3&branchName=develop)

A framework with (de)compression algorithms and functions for working with various archives and containers.

## What is this?

SWCompression is a framework with a collection of functions for:

1. Decompression (and sometimes compression) using different algorithms.
2. Reading (and sometimes writing) archives of different formats.
3. Reading (and sometimes writing) containers such as ZIP, TAR and 7-Zip.

It also works on Apple platforms, Linux, __and Windows__.

All features are listed in the tables below. "TBD" means that feature is planned but not implemented (yet).

|               | Deflate | BZip2 | LZMA/LZMA2 | LZ4 |
| ------------- | ------- | ----- | ---------- | --- |
| Decompression | ✅      | ✅     | ✅         | ✅  |
| Compression   | ✅      | ✅     | TBD        | ✅  |

|       | Zlib | GZip | XZ  | ZIP | TAR | 7-Zip |
| ----- | ---- | ---- | --- | --- | --- | ----- |
| Read  | ✅   | ✅    | ✅  | ✅  | ✅   | ✅    |
| Write | ✅   | ✅    | TBD | TBD | ✅   | TBD   |

Also, SWCompression is _written with Swift only._

## Installation

SWCompression can be integrated into your project using Swift Package Manager.

__Note:__ SWCompression versions 4.8.6 and earlier were also made available via CocoaPods or Carthage.

To install with Swift Package manager, add SWCompression to you package dependencies and specify it as a dependency for
your target, e.g.:

```swift
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(name: "SWCompression", url: "https://github.com/tsolomko/SWCompression.git",
                 from: "4.9.0")
    ],
    targets: [
        .target(
            name: "TargetName",
            dependencies: ["SWCompression"]
        )
    ]
)
```

More details you can find in [Swift Package Manager's Documentation](https://github.com/apple/swift-package-manager/tree/main/Documentation).

## Usage

### Basic Example

For example, if you want to decompress "deflated" data just use:

```swift
// let data = <Your compressed data>
let decompressedData = try? Deflate.decompress(data: data)
```

However, it is unlikely that you will encounter deflated data outside of any archive. So, in the case of GZip archive
you should use:

```swift
let decompressedData = try? GzipArchive.unarchive(archive: data)
```

### Handling Errors

Most SWCompression functions can throw errors and you are responsible for handling them. If you look at the list of
available error types and their cases, you may be frightened by their number. However, most of the cases (such as
`XZError.wrongMagic`) exist for diagnostic purposes.

Thus, you only need to handle the most common type of error for your archive/algorithm. For example:

```swift
do {
    // let data = <Your compressed data>
    let decompressedData = try XZArchive.unarchive(archive: data)
} catch let error as XZError {
    // <handle XZ related error here>
} catch let error {
    // <handle all other errors here>
}
```

### Documentation

Every function or type of SWCompression's public API is documented. This documentation can be found at its own
[website](http://tsolomko.github.io/SWCompression) or via a slightly shorter link:
[swcompression.tsolomko.me](http://swcompression.tsolomko.me)

### Sophisticated example

There is a small command-line program, "swcomp", which is included in this repository in "Sources/swcomp". It can be
built using Swift Package Manager (only available on macOS).

__IMPORTANT:__ The "swcomp" command-line tool is NOT intended for general use.

## Contributing

Whether you find a bug, have a suggestion, idea, feedback or something else, please
[create an issue](https://github.com/tsolomko/SWCompression/issues) on GitHub. If you have any questions, you can ask
them on the [Discussions](https://github.com/tsolomko/SWCompression/discussions) page.

In the case of a bug, it will be especially helpful if you attach a file (archive, etc.) that caused the bug to occur.

If you'd like to contribute, please [create a pull request](https://github.com/tsolomko/SWCompression/pulls) on GitHub.

### Executing tests locally

If you want to run tests on your computer, you need to do a couple of additional steps after cloning the repository:

```bash
git submodule update --init --recursive
cd "Tests/Test Files"
cp gitattributes-copy .gitattributes
git lfs pull
git lfs checkout
```

These commands will download the files used in tests which are stored in a
[separate repository](https://github.com/tsolomko/SWCompression-Test-Files) using Git LFS. There are two reasons for
this complicated setup. Firstly, some of these files can be quite big, and it would be unfortunate if the users of
SWCompression had to download them during the installation. Secondly, Swift Package Manager and contemporary versions of
Xcode don't always work well with git-lfs-enabled repositories. To prevent any potential problems test files were moved
into another repository.

Please note, that if you want to add a new _type_ of test files, in addition to running `git lfs track`, you have to
also copy into the "Tests/Test Files/gitattributes-copy" file a line this command adds to the "Tests/Test Files/.gitattributes"
file. __Do not commit the ".gitattributes" file to the git history. It is git-ignored for a reason!__

Please also be mindful of Git LFS bandwidth quota on GitHub: try to limit downloading lfs'd files using `git lfs pull`.
In CI we use some caching techniques to help with the quota, so if you're going to add new tests that require several
new test files you should try to submit them all together to reduce the amount of times CI needs to recreate the cache
(recreating the cache requires to do `git lfs pull` for all test files).

## Performance

Using whole module optimizations is recommended for the best performance. They are enabled by default in the Release build
configuration.

[Tests Results](Tests/Results.md) document contains results of benchmarking of various functions.

## Why?

First of all, existing solutions for working with compression, archives and containers have certain disadvantages. They
might not support a particular compression algorithm or archive format and they all have different APIs, which sometimes
can be slightly confusing for users, especially when you mix different libraries in one project. This project attempts to
provide missing (and sometimes existing) functionality through the unified API which is easy to use and remember.

Secondly, in some cases it may be important to have a compression framework written entirely in Swift, without relying
on either system libraries or solutions implemented in other languages. Additionaly, since SWCompression is written
completely in Swift without Objective-C, it can also be used on Linux, __and Windows__.

## Future plans

- Performance...
- Better Deflate compression.
- Something else...

## License

[MIT licensed](LICENSE)

## References

- [pyflate](http://www.paul.sladen.org/projects/pyflate/)
- [Deflate specification](https://www.ietf.org/rfc/rfc1951.txt)
- [GZip specification](https://www.ietf.org/rfc/rfc1952.txt)
- [Zlib specification](https://www.ietf.org/rfc/rfc1950.txt)
- [LZMA SDK and specification](http://www.7-zip.org/sdk.html)
- [XZ specification](http://tukaani.org/xz/xz-file-format-1.0.4.txt)
- [Wikipedia article about LZMA](https://en.wikipedia.org/wiki/Lempel–Ziv–Markov_chain_algorithm)
- [.ZIP Application Note](http://www.pkware.com/appnote)
- [ISO/IEC 21320-1](http://www.iso.org/iso/catalogue_detail.htm?csnumber=60101)
- [List of defined ZIP extra fields](https://opensource.apple.com/source/zip/zip-6/unzip/unzip/proginfo/extra.fld)
- [Wikipedia article about TAR](https://en.wikipedia.org/wiki/Tar_(computing))
- [Pax specification](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html)
- [Basic TAR specification](https://www.gnu.org/software/tar/manual/html_node/Standard.html)
- [star man pages](https://www.systutorials.com/docs/linux/man/5-star/)
- [Apache Commons Compress](https://commons.apache.org/proper/commons-compress/)
- [A walk through the SA-IS Suffix Array Construction Algorithm](http://zork.net/~st/jottings/sais.html)
- [Wikipedia article about BZip2](https://en.wikipedia.org/wiki/Bzip2)
- [LZ4 Frame Format Description](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
- [LZ4 Block Format Description](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md)
- [xxHash specification](https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md)

---

## Differences from upstream

Branched at **4.9.1** (`03a68e6`). Two upstream files modified, three added.
Everything else is byte-identical to upstream.

### 1. 7-Zip BCJ branch filters (correctness)

`Sources/7-Zip/BranchFilters.swift` (new), called from `7zFolder.swift`.

7-Zip applies *branch converters* — BCJ, and its per-architecture variants —
automatically when the input looks like machine code. A branch filter is not a
compressor: it rewrites relative call/jump targets into absolute ones so that
repeated calls become identical byte sequences, and the archive is unreadable
without the inverse. Upstream implements none of them and throws
`compressionNotSupported`, so **any `.7z` containing an executable fails to
open**, which is a common archive rather than an exotic one.

The algorithms are ports of XZ Utils' `src/liblzma/simple/*.c` (public domain),
the same filter specification 7-Zip implements. Decode only.

Deliberately not implemented: BCJ2 (a four-input-stream coder, rejected earlier
by the folder decoder anyway), IA64, and RISC-V.

### 2. LZMA/LZMA2 through Apple's `Compression` framework (speed)

`Sources/Common/LZMAFraming.swift` (new), called from `7zFolder.swift`.

7-Zip stores payloads as *raw* codec streams — no container, because the sizes
and codec parameters live in the 7z header. `COMPRESSION_LZMA` refuses those,
but accepts two containers, and in the shapes 7z produces those containers are
a fixed preamble around the very same bytes. So the payload is framed, never
transformed: LZMA2 into `.xz` (48 bytes of framing), LZMA1 into the legacy
`.lzma` "alone" format (13 bytes). Two framings are needed because **xz cannot
carry LZMA1 by specification**.

Measured end-to-end (extraction to disk, two real archives): LZMA1
28.9 → 40.8 MB/s, LZMA2+BCJ 62.1 → 77.6 MB/s. The in-memory decode alone runs
far faster, but real extraction is bounded by disk writes, so **2–3x is the
honest figure**.

The pure-Swift decoder remains and is used whenever framing does not apply.
7z stores a CRC-32 per entry, so a mis-framed decode fails verification rather
than producing plausible garbage — a wrong fast path cannot pass silently.

Guarded by `#if canImport(Compression)`; on Linux, Windows, Android and WASI
this compiles away and upstream's behaviour is unchanged.

### 3. Progress reporting for long decodes (usability)

`Sources/Common/DecodeProgress.swift` (new), one line in `LZMA2Decoder.swift`,
one in `LZMAFraming.swift`.

A solid 7z is usually one folder, decoded in a single call that yields nothing
until it finishes — a progress bar sits at 0% and then jumps to 100%, which
reads as a hang. A thread-local sink, opt-in and a no-op when unset, is ticked
once per output chunk. Thread-local rather than a parameter so that the patch
stays one line inside upstream code instead of a signature change threaded
through four files.

Both decode paths tick. Ticking only the pure-Swift loop would freeze the bar
precisely when decoding is fastest, because the system path never enters that
loop — measured on a real archive, 17.6 seconds of decode with the bar at 0%.

The sink optionally carries an `onFallback` callback so a host can log when the
system path declines a stream. Without one, that notice goes to stderr, which in
a GUI application no one reads.

### 4. Decoder hardening (security)

Later tags harden decoders against hostile input, turning Swift traps and
unbounded output into thrown errors. `4.9.1-sy.9` (from Arkheion's security
audit of 2026-10-30):

- **BZip2**: the block's pre-BWT buffer is held to the size from the stream
  header. A RUNA/RUNB run previously had no ceiling, so a few dozen run symbols
  asked for terabytes of one byte, or overflowed into a negative count that
  trapped.
- **7-Zip**: each coder is held to its declared unpack size *while* decoding
  (`Deflate`, `BZip2` and the pure-Swift `LZMA2` path take an internal `limit`;
  the `Compression` fast path stops as soon as it passes the expected size).
  Exceeding it is `SevenZipError.wrongSize`, as before, but reported before the
  excess has been produced. New public
  `SevenZipContainer.folderUnpackSizes(container:)` returns those sizes, so a
  host can check what `open(container:)` will materialise before calling it.
  LZ4 coders are not limited yet.
- **7-Zip**: `szMbd()` refuses values that do not fit a non-negative `Int`
  (the 9-byte form could come out negative and trap later).

### Verification

The 86 upstream files carried over were checked byte-for-byte against 4.9.1.
The decoder changes were validated by extracting real archives and comparing
every output file against `7zz`: 4,796 files, zero mismatches, and zero silent
fallbacks.

### Upstreaming

These changes are offered upstream; the fork exists to carry them in the
meantime. If they land, this fork should be retired rather than maintained.
