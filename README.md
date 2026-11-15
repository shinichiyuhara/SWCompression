# SWCompression (fork)

> **This is a fork of [tsolomko/SWCompression](https://github.com/tsolomko/SWCompression), branched at
> release 4.9.1.** It adds 7-Zip BCJ branch filters, an Apple-platform fast path for LZMA/LZMA2,
> decode progress, and hardening of the decoders against hostile input.
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

Branched at **4.9.1** (`03a68e6`). To list exactly what differs:
`git diff --stat 4.9.1 sy`. As of `4.9.1-sy.12`, 28 upstream files are modified
and 8 added, of which 4 are source files and 4 are this fork's records.
Existing public APIs keep their signatures; on hostile input they throw where
they used to trap. Valid input decodes as before, except 7-Zip containers beyond
the limits `sy.11` and `sy.15` add (more than 64 coders or coder streams in a
folder, an encoded header over 128 MiB, more than 2^21 files or 2^20 folders),
which are refused.

| Tag | Change |
|---|---|
| `sy.1` | BCJ branch filters, the `Compression` fast path, decode progress |
| `sy.2` | Progress from the system decode path too; hosts can log fallbacks |
| `sy.3` | Deflate: out-of-range back-reference distance |
| `sy.4` | TAR and 7-Zip: out-of-range declared sizes |
| `sy.5` | BZip2: out-of-range BWT pointer and MTF index |
| `sy.6` | XZ and LZMA: reads bounded on truncated or corrupt streams |
| `sy.7` | 7-Zip: header metadata reads bounded |
| `sy.8` | TAR: PAX extended-header scans bounded |
| `sy.9` | BZip2 runs and 7-Zip coder output limited; negative `szMbd` refused; `folderUnpackSizes` |
| `sy.10` | LZ4: block and 7-Zip coder output limited |
| `sy.11` | 7-Zip: every header read bounded; PAX `size` range; `BZip2.decompress(data:limit:)` |
| `sy.12` | `limit:` for `GzipArchive`, `XZArchive` and `LZMA` |
| `sy.13` | BZip2: zero selectors and an unchecked last code length refused; regression tests in this repo |
| `sy.14` | TAR: PAX size governs the skip; global PAX records not copied per entry; `TarReader` loops |
| `sy.15` | 7-Zip: ceilings on declared counts; per-file properties once each; folder streams 64 in total; pack offsets summed once |
| `sy.16` | Deflate, LZ4, LZMA and LZMA2 traps reachable as 7-Zip coders; LZMA with pb=4 decodes |
| `sy.17` | GZip extra field, XZ block header and padding, and .lzma header size traps |
| `sy.18` | `limit:` on every decoder; limited gzip/bzip2 read every member; Huffman trees sized by their codes; 7z folders unpacked once; BCJ past 4 GiB; truncated .lzma ends |
| `sy.19` | TAR octal fields, PAX names and times; 7z Unix mode bit and anti items; LZ4 blocks in place; XZ filter order; slices accepted |

Sections 1–3 describe `sy.1` and `sy.2`, section 4 the rest.

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
unbounded output into thrown errors. A Swift trap cannot be caught with `try?`,
so before these a corrupt file could crash the host, including a thumbnailer
that opened it with no action from the user.

`4.9.1-sy.3` to `sy.8` (2026-08-12) close the traps that malformed-input fuzzing
reached. All of them throw on corrupt input where the code used to index out of
range:

- **Deflate** (`sy.3`): a back-reference distance of zero or beyond the data
  decoded so far (RFC 1951 §3.2.5 forbids both).
- **TAR** (`sy.4`): a declared entry size that is negative or past the buffer.
- **7-Zip** (`sy.4`): a header region past the end of the file.
- **BZip2** (`sy.5`): a BWT pointer outside the block, an MTF index outside the
  live symbol list, and a run on an empty symbol list.
- **XZ, LZMA, LZMA2** (`sy.6`): reads past the end of a truncated stream. The
  range decoder pads with zeros past the end instead of reading, so a corrupt
  stream fails its size or CRC check; a valid stream is consumed exactly and
  never reaches the padding.
- **7-Zip** (`sy.7`): reads past the end while parsing the nested header
  metadata, including count-driven loops.
- **TAR** (`sy.8`): PAX record scans that ran past the end looking for a
  delimiter.

`4.9.1-sy.9` (from Arkheion's security audit of 2026-10-30):

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
  `4.9.1-sy.10` adds the same limit to LZ4 (internal
  `LZ4.decompress(data:dictionary:dictionaryID:limit:)`), and holds every LZ4
  block to its frame's maximum block size, which the frame format says bounds
  the *decompressed* block (a 4 MiB block of length extensions could otherwise
  ask for about a gigabyte).
- **7-Zip**: `szMbd()` refuses values that do not fit a non-negative `Int`
  (the 9-byte form could come out negative and trap later).


`4.9.1-sy.11` (from Pinakeion's security audit of 2026-10-31):

- **7-Zip**: every read in the header parsers is bounds-checked, along with the
  arithmetic on header fields. The earlier guards covered only what random
  mutation reached, and hand-built containers under 170 bytes still trapped. A
  count no longer allocates ahead of the bytes that back it, the coder chain
  refuses cycles and missing coders, coder and stream counts follow 7-Zip's own
  limit of 64, and an encoded header may decode to at most 128 MiB.
  `folderUnpackSizes(container:)` now reports the largest output of any coder in
  the folder, since an earlier coder can declare more than the last one produces.
- **TAR**: a PAX `size` record is held to the same range check as the header's
  size field. A negative or overflowing one used to trap.
- **BZip2**: new public `BZip2.decompress(data:limit:)`, which throws
  `DecompressionLimitExceeded`.

`4.9.1-sy.12` (from Demion's review of 2026-11-01): new public `GzipArchive.unarchive(archive:limit:)`,
`XZArchive.unarchive(archive:limit:)` and `LZMA.decompress(data:limit:)`, which
throw `DecompressionLimitExceeded`. These formats decode whole into memory, and
their ratio makes a limit on the input meaningless. The decoders already had the
internal limit; this exposes it, and adds it to the LZMA1 decoder.

`4.9.1-sy.13` onward come from this repository's own whole-codebase audit of
2026-11-15 (`docs/security/audit-20261115.md`), and fix first what a host
reaches without the user opening anything (Pinakeion's covers, Skopeion's
preloading, Arkheion's Quick Look):

- **BZip2** (`sy.13`): a block with zero selectors indexed an empty array, and
  the last symbol of each Huffman table escaped the 1–20 code-length check, so
  its length set the decoding tree's size — gigabytes, or a negative count
  that trapped. Both are refused, as bzip2 1.0.8 refuses them.

- **TAR** (`sy.14`): a PAX `size` now governs the skip to the next header as
  well as the entry's data, as POSIX requires. Skipping by the header's size
  let many entries copy the same bytes (1 GB from a 1.5 MB tar) and put entry
  boundaries where GNU tar and bsdtar do not see them. A global header's
  unknown records are shared with entries that add none of their own, and the
  copies a parse makes for entries that do are capped at 2^20 (`info()`
  itself used 1.2 GB on a 1.4 MB tar). `TarReader.read()` is a loop rather than
  a recursive call per special entry, which overflowed a 512 KiB stack on a
  run of 1,000 `L` headers, reads with the PAX size like `TarContainer`, and
  refuses a negative size.

- **7-Zip** (`sy.15`): `info()` and `folderUnpackSizes()` themselves — the
  calls a host makes to vet an archive — could be made to use gigabytes and
  hours. The header's counts now have absolute ceilings (2^21 files and
  substreams, 2^20 folders and pack streams, 4,096 kept unknown properties);
  a 10 MB header used 2.1 GB before. The properties describing every file
  (0x0E–0x15) may appear once each, and EmptyStream is counted once, where a
  two-byte repeat of EmptyFile used to rescan every file. A folder's coder
  streams are limited to 64 in total, as in 7-Zip, not per coder, and pack
  stream offsets are summed once rather than from zero per stream.

- **Decoders that 7-Zip folders use** (`sy.16`), each reachable from a 7z, and
  from gzip, zlib, xz and lzma: Deflate read the next block header past the end
  of a stream that stopped after a non-final block (five bytes trapped). LZ4
  recursed per skippable frame (40 KB of them overflowed a 512 KiB stack) and
  read frame magics with an aligned load at arbitrary offsets. **LZMA's
  probability table was one slot short, so valid files made with `pb=4`
  trapped** (an upstream bug). A match one byte beyond the dictionary's
  contents slipped past its check, which also ignored an LZMA2 dictionary
  reset. LZMA2 accepted an LZMA chunk before any dictionary reset or
  properties and decoded it with an empty table; it now enforces liblzma's
  order.

- **gzip, xz and lzma containers** (`sy.17`): a gzip extra field whose last
  one to three bytes could not hold a subfield header read past the input
  (21 bytes trapped, also through `GzipHeader(archive:)`). An xz block
  header's variable-length fields were bounded by the input only after the
  declared header size had been checked, so they could run past both; each
  field must now end before the header's CRC. The block padding is checked
  against the input. A .lzma header size of 2^63 overflowed on the first byte;
  sizes with the top bit set, other than "unknown", are refused.

- **Output limits and work per input byte** (`sy.18`): every decoder now has
  a `limit:` form (Deflate, Zlib, multi-member gzip, LZ4, multi-stream BZip2,
  split XZ, LZMA2 and raw LZMA); the multi-result ones count all results
  together. The fork's limited `GzipArchive.unarchive(archive:limit:)` and
  `BZip2.decompress(data:limit:)` now read every concatenated member or
  stream, as the command-line tools do, rather than silently returning the
  first. Huffman decoding trees are linked nodes sized by their codes, not
  complete trees of 2^(maxBits+1) slots (16 MiB for a BZip2 code of length
  20, rebuilt per block). A 7-Zip folder is unpacked once and must produce
  the size it declares; `open()` used to unpack it again from the next pack
  stream. BCJ filters wrap positions at 4 GiB as 7-Zip does, the LZMA fast
  path reserves at most 64 MiB up front, and a truncated .lzma of unknown
  size ends with an error instead of zeros without end.

- **Interpretation and smaller bounds** (`sy.19`): TAR reads an octal field
  filled to its last byte (GNU tar's 12-digit sizes lost their last digit),
  refuses a PAX `path`, `linkpath` or `size` that is not UTF-8 or holds a
  NUL instead of falling back to the basic header, ignores PAX times that are
  not finite whole seconds, and the TAR and gzip writers no longer trap on
  such times. A 7-Zip file's upper attribute bits are a Unix mode only with
  the Unix-extension bit (0x8000), and an anti item has no size in `info()`
  as it has no data in `open()`. XZ requires LZMA2 last and only last. LZ4
  decodes blocks into the frame's output rather than copying 64 KiB per
  dependent block, and BZip2 holds its run-length stage to `limit`. 7-Zip,
  TAR and ZIP accept a slice of a larger `Data`. Permissions are returned as
  stored, setuid included: hosts should mask them before applying.

### Verification

From `sy.16` (and again at `sy.17`–`sy.19`), a corpus made with `7zz`, `xz`, `bzip2` and `gzip` (twelve 7z
method chains including BCJ, ARM64, Delta, Deflate, BZip2, LZMA and LZMA2 with
`pb=4`, plus .xz with and without `pb=4`, .lzma, .bz2 and .gz of the same five
files) decodes byte-identically: 85 files, of which two went through the
pure-Swift fallback inside 7z. From `sy.19` it also holds seven LZ4 frames
made with `lz4 -BD` (dependent blocks) and ustar and pax tars from bsdtar:
104 files, all identical.

The changes of sections 1–3 were validated by extracting real archives and
comparing every output file against `7zz`: 4,796 files, zero mismatches, and
zero silent fallbacks. That figure dates from those tags and was not repeated
for each later one.

Up to `sy.12`, the hardening tags added no tests to this repository; their
regression tests live in the applications that use the fork, which run hostile
files through their own extraction routes. From `sy.13`, each fix also adds a
self-contained test to `Tests/Hardening` (inputs are inline bytes, so it needs
neither the Git LFS test files nor the Xcode project): `swift test`. `sy.6` and `sy.7` were also checked against a corpus of 30
valid archives, which still decoded byte-identically.

### Upstreaming

**None of this has been offered upstream yet** (checked 2026-11-01: no pull
request or issue). If the changes are offered and land, this fork should be
retired rather than maintained.
