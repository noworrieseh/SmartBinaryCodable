import Foundation

// MARK: - Utilities & Helpers

/// Protocol for types that can encode length information for strings and data.
protocol BinaryEncodableType {
    static func encodeStringLength(
        value: String, into data: inout Data, order: ByteOrder,
        encoding: String.Encoding)
    static func encodeDataLength(value: Data, into data: inout Data, order: ByteOrder)
    static func readDataLength(from data: Data, offset: inout Int) throws -> Self

}

extension FixedWidthInteger {
    /// Encode the length of a string as a fixed-width integer.
    /// The count is calculated based on the encoded byte length for the specified encoding.
    static func encodeStringLength(
        value: String, into data: inout Data, order: ByteOrder,
        encoding: String.Encoding
    ) {
        let count = value.data(using: encoding)?.count ?? 0
        guard let length = Self(exactly: count) else {
            fatalError("Buffer length \(count) exceeds capacity of \(Self.self)")
        }
        SmartBinaryIO.writeInteger(length, &data, order)

        //let count = value.data(using: encoding)?.count ?? 0
        //print("encodeStringLength \(count) \(value)")
        //self.write(count: count, into: &data, order: order)
    }

    /// Encode the length of a Data value as a fixed-width integer.
    static func encodeDataLength(value: Data, into data: inout Data, order: ByteOrder) {
        self.write(count: value.count, into: &data, order: order)
    }

    /// Write a count value as a fixed-width integer in the specified byte order.
    private static func write(count: Int, into data: inout Data, order: ByteOrder) {
        guard let length = Self(exactly: count) else {
            fatalError("Buffer length \(count) exceeds capacity of \(Self.self)")
        }
        let out = (order == .bigEndian) ? length.bigEndian : length.littleEndian
        withUnsafeBytes(of: out) { data.append(contentsOf: $0) }
    }

    static func readDataLength(from data: Data, offset: inout Int) throws -> Self {
        return try SmartBinaryIO.readInteger(Self.self, data, offset: &offset)
    }

    static var typeSize: Int {
        return MemoryLayout<Self>.size
    }
}

extension UInt8: BinaryEncodableType {}
extension UInt16: BinaryEncodableType {}
extension UInt32: BinaryEncodableType {}
extension UInt64: BinaryEncodableType {}
extension Int: BinaryEncodableType {}

extension Data {
    func hexDump() -> String {
        var result = ""
        let rows = self.count / 16 + (self.count % 16 == 0 ? 0 : 1)

        for row in 0..<rows {
            let rowStart = row * 16
            // Explicitly use the Swift standard library min
            let rowEnd = Swift.min(rowStart + 16, self.count)

            // Adjust for startIndex in case this is a DataSlice
            let actualStart = self.startIndex + rowStart
            let actualEnd = self.startIndex + rowEnd
            let rowData = self[actualStart..<actualEnd]

            result += String(format: "%08x  ", rowStart)

            let hexStrings = rowData.map { String(format: "%02x", $0) }
            let hexPart = hexStrings.joined(separator: " ")
            result += hexPart.padding(toLength: 47, withPad: " ", startingAt: 0)

            result += "  |"
            let asciiPart = rowData.map { byte in
                (byte >= 32 && byte <= 126) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            result += asciiPart + "|\n"
        }

        return result
    }

}

extension Bool {

    static func write(_ value: Bool, into data: inout Data) {
        data.append(value ? 1 : 0)
    }
    static func read(_ data: Data, offset: inout Int) throws -> Bool {
        let currentPos = data.startIndex + offset
        let result = data[currentPos] != 0
        offset += 1
        return result
    }
}

extension String {
    public func removeSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}

public func corrupted(_ text: String) -> DecodingError {
    return DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: text))
}

public struct SmartBinaryIO {

    public static func writeInteger<T: FixedWidthInteger>(
        _ value: T, _ data: inout Data, _ order: ByteOrder = .bigEndian
    ) {
        var encoded = order == .bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    public static func writeFloat<T: BinaryFloatingPoint>(
        _ value: T, _ data: inout Data, _ order: ByteOrder = .bigEndian
    ) {
        var encoded = value
        let bytes = withUnsafeBytes(of: &encoded) { Data($0) }
        if order == .bigEndian {
            data.append(Data(bytes.reversed()))
        } else {
            data.append(bytes)
        }
    }

    public static func writeString(
        _ sizeType: any FixedWidthInteger.Type, _ value: String, into data: inout Data,
        order: ByteOrder = .bigEndian, encoding: String.Encoding = .utf8
    ) {
        //let encodedData = value.data(using: encoding) ?? Data()
        sizeType.encodeStringLength(value: value, into: &data, order: order, encoding: encoding)
        //data.append(encodedData)
        writeStringData(value, into: &data)
    }

    public static func writeStringData(
        _ value: String, into data: inout Data,
        order: ByteOrder = .bigEndian, encoding: String.Encoding = .utf8
    ) {
        let encodedData = value.data(using: encoding) ?? Data()
        data.append(encodedData)
    }

    public static func writeData(
        _ sizeType: any FixedWidthInteger.Type,
        _ value: Data, into data: inout Data, order: ByteOrder = .bigEndian
    ) {
        sizeType.encodeDataLength(value: value, into: &data, order: order)
        data.append(value)
    }

    public static func readDataWithSize(
        _ sizeType: any FixedWidthInteger.Type, _ data: Data, _ offset: inout Int
    ) throws -> Data {
        let count = try sizeType.readDataLength(from: data, offset: &offset)
        return try readData(Int(count), data, &offset)
    }

    public static func readData(
        _ count: Int, _ data: Data, _ offset: inout Int
    )
        throws -> Data
    {
        let currentPos = data.startIndex + offset
        let endPos = currentPos + count
        guard endPos <= data.endIndex else {
            throw corrupted("Insufficient data")
        }
        let data = data.subdata(in: offset..<endPos)
        offset += count
        return data
    }

    public static func readInteger<T: FixedWidthInteger>(
        _ type: T.Type, _ data: Data, offset: inout Int, order: ByteOrder = .bigEndian
    ) throws
        -> T
    {
        let size = MemoryLayout<T>.size
        let currentPos = data.startIndex + offset
        guard currentPos + size <= data.endIndex else {
            throw corrupted("Insufficient data")
        }

        let value: T
        if size == 1 {
            if type == UInt8.self {
                value = T(data[currentPos])
            } else {
                value = T(truncatingIfNeeded: UInt8(data[currentPos]))
            }
        } else {
            let raw = data[currentPos..<currentPos + size].withUnsafeBytes {
                $0.loadUnaligned(as: T.self)
            }
            value = order == .bigEndian ? raw.bigEndian : raw.littleEndian
        }
        offset += size
        return value

    }

    public static func readFloat<T: BinaryFloatingPoint>(
        _ type: T.Type, _ data: Data, offset: inout Int, order: ByteOrder = .bigEndian
    ) throws -> T {
        let size = MemoryLayout<T>.size
        let currentPos = data.startIndex + offset
        guard currentPos + size <= data.endIndex else {
            throw corrupted("Insufficient data")
        }

        if T.self == Float.self {
            let i = try readInteger(UInt32.self, data, offset: &offset, order: order)
            return Float(bitPattern: i) as! T
        } else if T.self == Double.self {
            let i = try readInteger(UInt64.self, data, offset: &offset, order: order)
            return Double(bitPattern: i) as! T
        } else {
            throw corrupted("Unsupported float size")
        }
    }
}
