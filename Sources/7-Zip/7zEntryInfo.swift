// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

/// Provides access to information about an entry from the 7-Zip container.
public struct SevenZipEntryInfo: ContainerEntryInfo {

    // MARK: ContainerEntryInfo

    public let name: String

    public let size: Int?

    public let type: ContainerEntryType

    public let accessTime: Date?

    public let creationTime: Date?

    public let modificationTime: Date?

    public let permissions: Permissions?

    // MARK: 7-Zip specific

    /**
     Entry's "win attributes". 7-Zip internal property.
     May be useful when origin file system's attributes weren't POSIX compatible.
     */
    public let winAttributes: UInt32?

    /// Entry's attributes in DOS format.
    public let dosAttributes: DosAttributes?

    /// True, if entry has a stream (data) inside the container. 7-Zip internal propety.
    public let hasStream: Bool

    /// True, if entry is an empty file. 7-Zip internal property.
    public let isEmpty: Bool

    /**
     True, if entry is an anti-file. Used in differential backups to indicate that file should be deleted.
     7-Zip internal property.
     */
    public let isAnti: Bool

    /// CRC32 of entry's data.
    public let crc: UInt32?

    init(_ file: SevenZipFileInfo.File, _ size: Int? = nil, _ crc: UInt32? = nil) {
        self.hasStream = !file.isEmptyStream
        self.isEmpty = file.isEmptyFile
        self.isAnti = file.isAntiFile

        self.name = file.name

        self.accessTime = file.aTime
        self.creationTime = file.cTime
        self.modificationTime = file.mTime

        self.winAttributes = file.winAttributes

        // LOCAL PATCH (fork): the upper 16 bits hold a Unix mode only when
        // 7-Zip's FILE_ATTRIBUTE_UNIX_EXTENSION (0x8000) says so; otherwise
        // they are whatever the writer left there and were read as a file type
        // and permissions anyway (security audit 2026-11-15, W40).
        let unixMode = self.winAttributes.flatMap { $0 & 0x8000 != 0 ? $0 >> 16 : nil }
        if let attributes = self.winAttributes {
            self.permissions = unixMode.map { Permissions(rawValue: 0x0FFF & $0) }
            self.dosAttributes = DosAttributes(rawValue: 0xFF & attributes)
        } else {
            self.permissions = nil
            self.dosAttributes = nil
        }

        // Set entry type.
        if let unixMode = unixMode,
            let unixType = ContainerEntryType(0xF000 & unixMode) {
            self.type = unixType
        } else if let dosAttributes = self.dosAttributes {
            if dosAttributes.contains(.directory) {
                self.type = .directory
            } else {
                self.type = .regular
            }
        } else if file.isEmptyStream && !file.isEmptyFile {
            self.type = .directory
        } else {
            self.type = .regular
        }

        self.crc = crc
        self.size = size
    }

}
