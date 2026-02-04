import Foundation

// MARK: - SmartBinaryCodable Module

/// A high-performance binary encoding/decoding system that works with Swift's Codable protocol.
///
/// This module provides `SmartBinaryEncoder` and `SmartBinaryDecoder` for serializing and deserializing
/// Swift types to/from binary data with support for size-prefixed strings and data fields.
///
/// ## Features
/// - Works with Swift's standard `Codable` protocol
/// - Configurable byte order (little-endian or big-endian)
/// - Automatic size-prefixed encoding for `String` and `Data` fields
/// - Null-terminated C-string support
/// - Support for all standard Swift numeric types (integers, floats, doubles, bools)
/// - Proper handling of Data slices with correct startIndex accounting
///
/// ## Usage Example
/// ```swift
/// struct Server: Codable {
///     let nameSize: UInt16
///     let name: String
///     let port: UInt16
/// }
///
/// // Encoding
/// let server = Server(nameSize: 4, name: "test", port: 8080)
/// let encoder = SmartBinaryEncoder()
/// let data = try encoder.encode(server)
///
/// // Decoding
/// let decoder = SmartBinaryDecoder(data: data)
/// let decodedServer = try decoder.decode(Server.self)
/// ```
///
/// ## Size Field Convention
/// String and Data fields check a corresponding size field that ends with the `sizeSuffix` (default: "Size").
/// The size field must appear **before** the data field in the struct definition.  If the size field is not
//  present, a default type is used.  There is a defaultSizeType option which is `UInt32`.
///
/// For example, for a field named `name`, there can a field named `nameSize` of type `UInt8`, `UInt16`, or `UInt32`.
///
/// ## C-String Support
/// Fields ending with the `cstrSuffix` (default: "Cstr") are encoded/decoded as null-terminated strings.
/// Example: `nameCstr: String` will be encoded with a null terminator and no size prefix.

// MARK: - Utilities & Helpers

/// Protocol for types that can encode length information for strings and data.
protocol BinaryEncodableType {
    static func encodeStringLength(
        value: String, into data: inout Data, order: ByteOrder,
        encoding: String.Encoding)
    static func encodeDataLength(value: Data, into data: inout Data, order: ByteOrder)
}

extension FixedWidthInteger {
    /// Encode the length of a string as a fixed-width integer.
    /// The count is calculated based on the encoded byte length for the specified encoding.
    static func encodeStringLength(
        value: String, into data: inout Data, order: ByteOrder,
        encoding: String.Encoding
    ) {
        let count = value.data(using: encoding)?.count ?? 0
        self.write(count: count, into: &data, order: order)
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
    static var sizeType: Int {
        return MemoryLayout<Self>.size
    }
}

extension UInt8: BinaryEncodableType {}
extension UInt16: BinaryEncodableType {}
extension UInt32: BinaryEncodableType {}
extension UInt64: BinaryEncodableType {}
extension Int: BinaryEncodableType {}

// MARK: - Public API: SmartBinaryEncoder

/// A binary encoder that works with Swift's `Codable` protocol.
///
/// Encodes Swift types to binary data with automatic support for size-prefixed strings and data fields.
///
/// ## Configuration
/// - **byteOrder**: Controls endianness of multi-byte values (default: little-endian)
/// - **sizeSuffix**: Suffix for size field names (default: "Size")
/// - **cstrSuffix**: Suffix for C-string field names (default: "Cstr")
/// - **encoding**: String encoding (default: `.utf8`)
///
/// ## Example
/// ```swift
/// struct Message: Codable {
///     let contentSize: UInt16
///     let content: String
///     let priority: UInt8
/// }
///
/// let msg = Message(contentSize: 5, content: "hello", priority: 1)
/// let encoder = SmartBinaryEncoder()
/// let data = try encoder.encode(msg)
/// ```
///
/// - SeeAlso: SmartBinaryDecoder
public class SmartBinaryEncoder {
    private var encoderState: EncoderState

    /// The byte order used for encoding multi-byte values.
    public let byteOrder: ByteOrder

    /// The suffix used to identify size fields (default: "Size").
    public let sizeSuffix: String

    /// The suffix used to identify C-string fields (default: "Cstr").
    public let cstrSuffix: String

    /// The encoding used for string data (default: `.utf8`).
    public let encoding: String.Encoding

    /// The default size type used for encoding multi-byte values (default: `UInt32.self`).
    public let defaultSizeType: any FixedWidthInteger.Type

    /// Initialize an encoder with specified configuration.
    ///
    /// - Parameters:
    ///   - byteOrder: Byte order for multi-byte values (default: `.littleEndian`)
    ///   - sizeSuffix: Suffix for size field names (default: `"Size"`)
    ///   - cstrSuffix: Suffix for C-string field names (default: `"Cstr"`)
    ///   - encoding: String encoding (default: `.utf8`)
    ///   - defaultSizeType: Default size type for encoding multi-byte values (default: `UInt32.self`)
    public init(
        byteOrder: ByteOrderOption = .littleEndian,
        sizeSuffix: String = "Size",
        cstrSuffix: String = "Cstr",
        encoding: String.Encoding = .utf8,
        defaultSizeType: any FixedWidthInteger.Type = UInt32.self

    ) {
        self.byteOrder = byteOrder.toByteOrder()
        self.sizeSuffix = sizeSuffix
        self.cstrSuffix = cstrSuffix
        self.encoding = encoding
        self.defaultSizeType = defaultSizeType
        self.encoderState = EncoderState()
    }

    /// Encode a value to binary data.
    ///
    /// - Parameter value: The value to encode (must conform to `Encodable`)
    /// - Returns: Binary data representation
    /// - Throws: `EncodingError` if encoding fails
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let state = EncoderState()
        let encoder = EncoderImpl(
            state: state, byteOrder: byteOrder, sizeSuffix: sizeSuffix, cstrSuffix: cstrSuffix,
            encoding: encoding, defaultSizeType: defaultSizeType)
        try value.encode(to: encoder)
        return state.data
    }

    /// Encode and append a value to the accumulated data.
    ///
    /// Use this method to incrementally build encoded data from multiple values.
    ///
    /// - Parameter value: The value to encode
    /// - Throws: `EncodingError` if encoding fails
    public func encodeAndAppend<T: Encodable>(_ value: T) throws {
        let encoder = EncoderImpl(
            state: encoderState, byteOrder: byteOrder, sizeSuffix: sizeSuffix,
            cstrSuffix: cstrSuffix, encoding: encoding, defaultSizeType: defaultSizeType)
        try value.encode(to: encoder)
    }

    /// Get the accumulated encoded data from `encodeAndAppend()` calls.
    ///
    /// - Returns: The binary data that has been accumulated
    public func getData() -> Data {
        return encoderState.data
    }

    /// Reset the accumulated data.
    ///
    /// Use this to clear previously accumulated data before starting a new encoding session.
    public func reset() {
        encoderState = EncoderState()
    }
}

// MARK: - Encoder Implementation (Private)

// MARK: Encoder State

private class EncoderState {
    var data: Data
    var codingPath: [CodingKey] = []
    var sizeFieldType: [String: any FixedWidthInteger.Type] = [:]

    init(data: Data = Data()) {
        self.data = data
    }
}

// MARK: Main Encoder Implementation

private class EncoderImpl: Encoder {
    let state: EncoderState
    var userInfo: [CodingUserInfoKey: Any] = [:]
    let byteOrder: ByteOrder
    let sizeSuffix: String
    let cstrSuffix: String
    let encoding: String.Encoding
    let defaultSizeType: any FixedWidthInteger.Type

    var codingPath: [CodingKey] {
        get { state.codingPath }
        set { state.codingPath = newValue }
    }

    var data: Data {
        get { state.data }
        set { state.data = newValue }
    }

    var sizeFieldType: [String: any FixedWidthInteger.Type] {
        get { state.sizeFieldType }
        set { state.sizeFieldType = newValue }
    }

    init(
        state: EncoderState, byteOrder: ByteOrder, sizeSuffix: String, cstrSuffix: String,
        encoding: String.Encoding, defaultSizeType: any FixedWidthInteger.Type
    ) {
        self.state = state
        self.byteOrder = byteOrder
        self.sizeSuffix = sizeSuffix
        self.cstrSuffix = cstrSuffix
        self.encoding = encoding
        self.defaultSizeType = defaultSizeType
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key>
    where Key: CodingKey {
        return KeyedEncodingContainer(KeyedEncodingContainerImpl<Key>(encoder: self))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return UnkeyedEncodingContainerImpl(encoder: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        return SingleValueEncodingContainerImpl(encoder: self)
    }
}

// MARK: Keyed Container

private struct KeyedEncodingContainerImpl<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: EncoderImpl
    var codingPath: [CodingKey] { encoder.codingPath }

    mutating func encodeNil(forKey key: Key) throws {}

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let fieldName = key.stringValue

        // Manually intercept Data types to handle size encoding
        if let dataValue = value as? Data {
            if let sizeType = encoder.sizeFieldType[fieldName] as? any BinaryEncodableType.Type {
                sizeType.encodeDataLength(
                    value: dataValue, into: &encoder.data, order: encoder.byteOrder)
            }
            encoder.data.append(dataValue)
            return
        }

        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        try value.encode(to: encoder)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
        -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        return KeyedEncodingContainer(KeyedEncodingContainerImpl<NestedKey>(encoder: encoder))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        return UnkeyedEncodingContainerImpl(encoder: encoder)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        return encoder
    }

    mutating func superEncoder() -> Encoder {
        return encoder
    }
}

// MARK: Unkeyed Container

private struct UnkeyedEncodingContainerImpl: UnkeyedEncodingContainer {
    let encoder: EncoderImpl
    var codingPath: [CodingKey] { encoder.codingPath }
    var count: Int = 0

    mutating func encodeNil() throws {}

    mutating func encode<T: Encodable>(_ value: T) throws {
        try value.encode(to: encoder)
        count += 1
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        return KeyedEncodingContainer(KeyedEncodingContainerImpl<NestedKey>(encoder: encoder))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        return self
    }

    mutating func superEncoder() -> Encoder {
        return encoder
    }
}

// MARK: Single Value Container

private struct SingleValueEncodingContainerImpl: SingleValueEncodingContainer {
    let encoder: EncoderImpl
    var codingPath: [CodingKey] { encoder.codingPath }

    mutating func encodeNil() throws {}

    mutating func encode<T: Encodable>(_ value: T) throws {
        let fieldName = codingPath.last?.stringValue ?? ""
        switch value {

        case let v as Bool:
            encoder.data.append(v ? 1 : 0)
        case let v as any FixedWidthInteger:
            if keyEndsWithSizeSuffix(fieldName) {
                let baseName = String(fieldName.dropLast(encoder.sizeSuffix.count))
                encoder.sizeFieldType[baseName] = type(of: v)
            } else {
                encoder.encodeInteger(v)
            }
        case let v as any BinaryFloatingPoint:
            encoder.encodeFloat(v)
        case let v as String:
            if fieldName.hasSuffix(encoder.sizeSuffix) {
                return
            }
            if fieldName.hasSuffix(encoder.cstrSuffix) {
                if let encodedData = v.data(using: encoder.encoding) {
                    encoder.data.append(encodedData)
                }
                encoder.data.append(0)
                return
            }
            let sizeType = encoder.sizeFieldType[fieldName] ?? encoder.defaultSizeType
            let encodedData = v.data(using: encoder.encoding) ?? Data()
            sizeType.encodeStringLength(
                value: v, into: &encoder.data, order: encoder.byteOrder,
                encoding: encoder.encoding)
            encoder.data.append(encodedData)

        case let v as Data:
            if fieldName.hasSuffix(encoder.sizeSuffix) {
                return
            }
            let sizeType = encoder.sizeFieldType[fieldName] ?? encoder.defaultSizeType
            sizeType.encodeDataLength(value: v, into: &encoder.data, order: encoder.byteOrder)
            encoder.data.append(v)

        default:
            try value.encode(to: encoder)
        }
    }

    private func keyEndsWithSizeSuffix(_ key: String) -> Bool {
        return key.hasSuffix(encoder.sizeSuffix)
    }
}

// MARK: Encoder Helpers

extension EncoderImpl {
    fileprivate func encodeInteger<T: FixedWidthInteger>(_ value: T) {
        var encoded = byteOrder == .bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    fileprivate func encodeFloat<T: BinaryFloatingPoint>(_ value: T) {
        var encoded = value
        let bytes = withUnsafeBytes(of: &encoded) { Data($0) }
        if byteOrder == .bigEndian {
            data.append(Data(bytes.reversed()))
        } else {
            data.append(bytes)
        }
    }
}

// MARK: - Public API: SmartBinaryDecoder

/// A binary decoder that works with Swift's `Codable` protocol.
///
/// Decodes binary data to Swift types with automatic support for size-prefixed strings and data fields.
///
/// ## Configuration
/// - **data**: The binary data to decode
/// - **byteOrder**: Must match the byte order used during encoding (default: little-endian)
/// - **sizeSuffix**: Must match the encoder's sizeSuffix (default: "Size")
/// - **cstrSuffix**: Must match the encoder's cstrSuffix (default: "Cstr")
/// - **encoding**: Must match the encoder's encoding (default: `.utf8`)
/// - **defaultSizeType**: Default size type for encoding multi-byte values (default: `UInt32.self`)
///
/// ## Example
/// ```swift
/// let decoder = SmartBinaryDecoder(data: binaryData)
/// let message = try decoder.decode(Message.self)
/// ```
///
/// - SeeAlso: SmartBinaryEncoder
public class SmartBinaryDecoder {
    private let data: Data

    /// The current offset in the data stream.
    /// This is updated as values are decoded.
    private(set) var offset: Int = 0

    /// The byte order used during decoding.
    public let byteOrder: ByteOrder

    /// The suffix used to identify size fields.
    public let sizeSuffix: String

    /// The suffix used to identify C-string fields.
    public let cstrSuffix: String

    /// The encoding used for string data.
    public let encoding: String.Encoding

    /// Default size type for encoding multi-byte values.
    public let defaultSizeType: any FixedWidthInteger.Type

    /// Initialize a decoder with binary data.
    ///
    /// - Parameters:
    ///   - data: The binary data to decode
    ///   - byteOrder: Byte order (must match encoder, default: `.littleEndian`)
    ///   - sizeSuffix: Size field suffix (must match encoder, default: `"Size"`)
    ///   - cstrSuffix: C-string field suffix (must match encoder, default: `"Cstr"`)
    ///   - encoding: String encoding (must match encoder, default: `.utf8`)
    ///   - defaultSizeType: Default size type for encoding multi-byte values (default: `UInt32.self`)
    public init(
        data: Data,
        byteOrder: ByteOrderOption = .littleEndian,
        sizeSuffix: String = "Size",
        cstrSuffix: String = "Cstr",
        encoding: String.Encoding = .utf8,
        defaultSizeType: any FixedWidthInteger.Type = UInt32.self
    ) {
        self.data = data
        self.byteOrder = byteOrder.toByteOrder()
        self.sizeSuffix = sizeSuffix
        self.cstrSuffix = cstrSuffix
        self.encoding = encoding
        self.defaultSizeType = defaultSizeType
    }

    /// Decode binary data to a value.
    ///
    /// - Parameter type: The type to decode to (must conform to `Decodable`)
    /// - Returns: The decoded value
    /// - Throws: `DecodingError` if the data is malformed or incomplete
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let state = DecoderState(
            data: data, offset: offset, byteOrder: byteOrder, sizeSuffix: sizeSuffix,
            cstrSuffix: cstrSuffix, encoding: encoding, defaultSizeType: defaultSizeType)
        let decoder = DecoderImpl(state: state)
        let result = try T(from: decoder)
        offset = state.offset
        return result
    }
}

// MARK: - Decoder Implementation (Private)

// MARK: Decoder State

private class DecoderState {
    var data: Data
    var offset: Int
    let byteOrder: ByteOrder
    let sizeSuffix: String
    let cstrSuffix: String
    let encoding: String.Encoding
    var defaultSizeType: any FixedWidthInteger.Type
    var sizeFieldType: [String: any FixedWidthInteger.Type] = [:]

    init(
        data: Data, offset: Int, byteOrder: ByteOrder, sizeSuffix: String, cstrSuffix: String,
        encoding: String.Encoding, defaultSizeType: any FixedWidthInteger.Type
    ) {
        self.data = data
        self.offset = offset
        self.byteOrder = byteOrder
        self.sizeSuffix = sizeSuffix
        self.cstrSuffix = cstrSuffix
        self.encoding = encoding
        self.defaultSizeType = defaultSizeType
    }
}

// MARK: Main Decoder Implementation

private class DecoderImpl: Decoder {
    let state: DecoderState
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var codingPath: [CodingKey] = []

    var data: Data { state.data }
    var offset: Int {
        get { state.offset }
        set { state.offset = newValue }
    }
    var byteOrder: ByteOrder { state.byteOrder }
    var sizeSuffix: String { state.sizeSuffix }
    var cstrSuffix: String { state.cstrSuffix }
    var encoding: String.Encoding { state.encoding }
    var defaultSizeType: any FixedWidthInteger.Type { state.defaultSizeType }
    var sizeFieldValue: [String: any FixedWidthInteger] = [:]

    init(state: DecoderState) {
        self.state = state
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedDecodingContainer<Key>
    where Key: CodingKey {
        return KeyedDecodingContainer(KeyedDecodingContainerImpl<Key>(decoder: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UnkeyedDecodingContainerImpl(decoder: self)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueDecodingContainerImpl(decoder: self)
    }
}

// MARK: Keyed Container

private struct KeyedDecodingContainerImpl<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: DecoderImpl
    var codingPath: [CodingKey] { decoder.codingPath }
    var allKeys: [Key] = []

    func contains(_ key: Key) -> Bool { true }
    func decodeNil(forKey key: Key) throws -> Bool { false }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }
        return try T(from: decoder)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
    {
        return KeyedDecodingContainer(KeyedDecodingContainerImpl<NestedKey>(decoder: decoder))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return UnkeyedDecodingContainerImpl(decoder: decoder)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        return decoder
    }

    func superDecoder() throws -> Decoder {
        return decoder
    }
}

// MARK: Unkeyed Container

private struct UnkeyedDecodingContainerImpl: UnkeyedDecodingContainer {
    let decoder: DecoderImpl
    var currentIndex: Int = 0

    var count: Int? { nil }
    var isAtEnd: Bool { decoder.offset >= decoder.data.count }
    var codingPath: [CodingKey] { decoder.codingPath }

    mutating func decodeNil() throws -> Bool { false }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let result = try T(from: decoder)
        currentIndex += 1
        return result
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
    {
        return KeyedDecodingContainer(KeyedDecodingContainerImpl<NestedKey>(decoder: decoder))
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        return self
    }

    mutating func superDecoder() throws -> Decoder {
        return decoder
    }
}

// MARK: Single Value Container

private struct SingleValueDecodingContainerImpl: SingleValueDecodingContainer {
    let decoder: DecoderImpl
    var codingPath: [CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool { false }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let fieldName = codingPath.last?.stringValue ?? ""

        if let intType = type as? any FixedWidthInteger.Type {
            let value = try decoder.decodeInteger(intType)
            if keyEndsWithSizeSuffix(fieldName) {
                let baseName = String(fieldName.dropLast(decoder.sizeSuffix.count))
                decoder.sizeFieldValue[baseName] = value
            }
            return value as! T
        }

        if type == Float.self {
            return try decoder.decodeFloat(Float.self) as! T
        }
        if type == Double.self {
            return try decoder.decodeFloat(Double.self) as! T
        }
        if type == Bool.self {
            guard decoder.offset < decoder.data.count else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath, debugDescription: "Insufficient data"))
            }
            let currentPos = decoder.data.startIndex + decoder.offset
            let value = decoder.data[currentPos] != 0
            decoder.offset += 1
            return value as! T
        }
        if type == String.self {
            var currentPos = decoder.data.startIndex + decoder.offset
            var endPos: Int

            // Check endPos
            if fieldName.hasSuffix(decoder.cstrSuffix) {
                guard let termPos = decoder.data[currentPos...].firstIndex(of: 0) else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: codingPath,
                            debugDescription: "Null terminator not found for C-style string"))
                }
                endPos = termPos
            } else {
                if let sizeValue = decoder.sizeFieldValue[fieldName] {
                    endPos = currentPos + Int(sizeValue)
                } else {
                    let value = try decoder.decodeInteger(decoder.defaultSizeType)
                    currentPos += decoder.defaultSizeType.sizeType
                    endPos = currentPos + Int(value)
                }
                guard endPos <= decoder.data.endIndex else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: codingPath,
                            debugDescription:
                                "Insufficient data \(fieldName) \(decoder.offset) \(decoder.sizeFieldValue) \(decoder.data.count)"
                        ))
                }
            }

            // Extract string data
            let stringData = decoder.data.subdata(in: currentPos..<endPos)
            guard let string = String(data: stringData, encoding: decoder.encoding) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath, debugDescription: "Invalid string encoding"))
            }

            // Update offset
            decoder.offset += decoder.data.distance(from: currentPos, to: endPos)
            if fieldName.hasSuffix(decoder.cstrSuffix) {
                decoder.offset += 1
            }

            return string as! T

        }
        if type == Data.self {
            var currentPos = decoder.data.startIndex + decoder.offset
            var endPos: Int
            if let sizeValue = decoder.sizeFieldValue[fieldName] {
                endPos = currentPos + Int(sizeValue)
            } else {
                let sizeValue = try decoder.decodeInteger(decoder.defaultSizeType)
                currentPos += decoder.defaultSizeType.sizeType
                endPos = currentPos + Int(sizeValue)
            }
            guard endPos <= decoder.data.endIndex else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath, debugDescription: "Insufficient data"))
            }
            let data = decoder.data.subdata(in: currentPos..<endPos)
            decoder.offset += decoder.data.distance(from: currentPos, to: endPos)
            return data as! T
        }
        return try T(from: decoder)
    }

    private func keyEndsWithSizeSuffix(_ key: String) -> Bool {
        return key.hasSuffix(decoder.sizeSuffix)
    }
}

// MARK: Decoder Helpers

extension DecoderImpl {
    fileprivate func decodeInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        let currentPos = data.startIndex + offset
        guard currentPos + size <= data.endIndex else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Insufficient data"))
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
            value = byteOrder == .bigEndian ? raw.bigEndian : raw.littleEndian
        }
        offset += size
        return value
    }
    fileprivate func decodeFloat<T: BinaryFloatingPoint>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        let currentPos = data.startIndex + offset
        guard currentPos + size <= data.endIndex else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Insufficient data"))
        }

        if T.self == Float.self {
            let i = try decodeInteger(UInt32.self)
            return Float(bitPattern: i) as! T
        } else if T.self == Double.self {
            let i = try decodeInteger(UInt64.self)
            return Double(bitPattern: i) as! T
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported float size"))
        }
    }

}
