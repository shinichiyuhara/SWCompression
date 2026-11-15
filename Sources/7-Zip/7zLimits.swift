// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

// LOCAL PATCH (fork): absolute ceilings on the counts a 7-Zip header declares.
//
// The header parsers allocate per declared item (a `File`, a folder with its
// coder arrays, a pack size, a property). Requiring a byte of header per item
// is not enough: an item costs tens to hundreds of bytes in memory, and an
// encoded header may expand to 128 MiB from a few kilobytes of LZMA. A 10 MB
// plain header of ten million files took 1.6 GB in `folderUnpackSizes()` and
// 2.1 GB in `info()` — the very calls a host makes to vet an archive before
// opening it (security audit 2026-11-15, W12). These ceilings sit far above
// real archives and keep the parse to a few hundred megabytes at worst.
enum SevenZipLimits {

    /// Files (entries) in the archive, and substreams across all folders.
    static let maxFiles = 1 << 21

    /// Folders, and pack streams.
    static let maxFolders = 1 << 20

    /// Properties the parser keeps without understanding them (archive
    /// properties and unknown file properties).
    static let maxUnknownProperties = 1 << 12

    /// Coders in a folder, and coder streams in a folder *in total*. 7-Zip's
    /// reader stops at 64 (`k_Scan_NumCoders_MAX`,
    /// `k_Scan_NumCodersStreams_in_Folder_MAX`); a per-coder 64 still allowed
    /// 4,096 streams and quadratic bind-pair searches (audit W25).
    static let maxFolderStreams = 64

}
