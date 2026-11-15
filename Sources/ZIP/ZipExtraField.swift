// Copyright (c) 2026 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData

/// A type that represents an extra field from a ZIP container.
public protocol ZipExtraField {

    /**
     ID of extra field. Must be equal to the key of extra field in `ZipContainer.customExtraFields` dictionary and
     instance `id` property
     */
    static var id: UInt16 { get }

    /// Location of extra field. Must be equal to the value of `location` argument of `init?(_:_:location:)`.
    var location: ZipExtraFieldLocation { get }

    /// Size of extra field's data. Must be equal to the value of the second argument of `init?(_:_:location:)`.
    var size: Int { get }

    /**
     Creates an extra field instance reading `size` amount of data from `byteReader`.

     It is guaranteed that the offset of `byteReader` is equal to the position right after extra field header ID and
     length of extra field data. It is also guaranteed that header ID matches conforming type's static `id` property.

     Following conditions are checked after execution of this initializer. Failure to satisfy them in conforming type
     will result in runtime error.

     - Postcondition: `location` property of a created instance must be equal to the `location` argument.
     - Postcondition: `size` property of a created instance must be equal to the second argument.
     - Postcondition: exactly `size` amount of bytes must be read by initializer from `byteReader`.
     */
    init?(_ byteReader: LittleEndianByteReader, _ size: Int, location: ZipExtraFieldLocation)

}

extension ZipExtraField {

    /**
     ID of extra field. Must be equal to the key of extra field in `ZipContainer.customExtraFields` dictionary and
     static `id` property
     */
    public var id: UInt16 {
        return Self.id
    }

}

/// Location of ZIP extra field inside a container.
public enum ZipExtraFieldLocation {
    /// ZIP extra field is located in container's Central Directory.
    case centralDirectory
    /// ZIP extra field is located in one of container's Local Headers.
    case localHeader
}

extension ZipContainer {

    /// LOCAL PATCH (fork): reads the `length` bytes of extra fields at the
    /// reader's offset, which the caller has checked are present. Every field
    /// must fit in that area, and each is read from its own start and left at
    /// its own end whatever its parser did — the parsers used to read fixed
    /// amounts across field boundaries and past the input (security audit
    /// 2026-11-15, W16, W24). Fewer than four bytes left over (zipalign's zero
    /// padding) are skipped. `builtin` handles the IDs this library knows and
    /// returns false for the rest, which go to `customExtraFields`.
    static func readExtraFields(_ byteReader: LittleEndianByteReader, length: Int,
                                location: ZipExtraFieldLocation,
                                builtin: (_ headerID: UInt16, _ size: Int) throws -> Bool) throws -> [ZipExtraField] {
        let end = byteReader.offset + length
        var customExtraFields = [ZipExtraField]()
        while byteReader.offset < end {
            guard end - byteReader.offset >= 4 else {
                byteReader.offset = end
                break
            }
            let headerID = byteReader.uint16()
            let size = byteReader.int(fromBytes: 2)
            guard size <= end - byteReader.offset
                else { throw ZipError.wrongSize }
            let fieldStart = byteReader.offset
            if try !builtin(headerID, size) {
                if let customExtraFieldType = ZipContainer.customExtraFields[headerID],
                    customExtraFieldType.id == headerID,
                    let customExtraField = customExtraFieldType.init(byteReader, size, location: location),
                    customExtraField.id == headerID {
                    precondition(customExtraField.location == location,
                                 "Custom field with ID=\(headerID) of type=\(customExtraFieldType) changed location.")
                    precondition(customExtraField.size == size,
                                 "Custom field with ID=\(headerID) of type=\(customExtraFieldType) changed size.")
                    guard byteReader.offset == fieldStart + size
                        else { fatalError("Custom field with ID=\(headerID) of type=\(customExtraFieldType)" +
                                          " failed to read exactly \(size) bytes.") }
                    customExtraFields.append(customExtraField)
                }
            }
            byteReader.offset = fieldStart + size
        }
        return customExtraFields
    }

}
