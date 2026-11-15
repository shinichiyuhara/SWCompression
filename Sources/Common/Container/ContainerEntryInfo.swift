// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

/// A type that provides access to information about an entry from the container.
public protocol ContainerEntryInfo {

    /// Entry's name.
    var name: String { get }

    /// Entry's type.
    var type: ContainerEntryType { get }

    /// Entry's data size (can be `nil` if either data or size aren't available).
    var size: Int? { get }

    /// Entry's last access time (`nil`, if not available).
    var accessTime: Date? { get }

    /// Entry's creation time (`nil`, if not available).
    var creationTime: Date? { get }

    /// Entry's last modification time (`nil`, if not available).
    var modificationTime: Date? { get }

    /// Entry's permissions in POSIX format (`nil`, if not available).
    ///
    /// - Important: LOCAL PATCH (fork). These are the archive's bits as stored, including setuid, setgid and sticky
    /// (`0o7000`). An archive is anyone's to write: mask with `0o777` (or a stricter mask) before applying them to an
    /// extracted file (security audit 2026-11-15, W40).
    var permissions: Permissions? { get }

}
