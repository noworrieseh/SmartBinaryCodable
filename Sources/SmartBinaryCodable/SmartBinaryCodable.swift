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
/*protocol BinaryEncodableType {
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
extension Int: BinaryEncodableType {}*/

// MARK: - Public API: SmartBinaryEncoder

/// A binary encoder that works with Swift's `Codable` protocol.
///
/// Encodes Swift types to binary data with automatic support for size-prefixed strings and data fields.
///
/// ## Configuration
/// - **order**: Controls endianness of multi-byte values (default: little-endian)
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
    public let order: ByteOrder

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
    ///   - order: Byte order for multi-byte values (default: `.littleEndian`)
    ///   - sizeSuffix: Suffix for size field names (default: `"Size"`)
    ///   - cstrSuffix: Suffix for C-string field names (default: `"Cstr"`)
    ///   - encoding: String encoding (default: `.utf8`)
    ///   - defaultSizeType: Default size type for encoding multi-byte values (default: `UInt32.self`)
    public init(
        order: ByteOrderOption = .littleEndian,
        sizeSuffix: String = "Size",
        cstrSuffix: String = "Cstr",
        encoding: String.Encoding = .utf8,
        defaultSizeType: any FixedWidthInteger.Type = UInt32.self

    ) {
        self.order = order.toByteOrder()
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
            state: state, order: order, sizeSuffix: sizeSuffix, cstrSuffix: cstrSuffix,
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
            state: encoderState, order: order, sizeSuffix: sizeSuffix,
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
    let order: ByteOrder
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
        state: EncoderState, order: ByteOrder, sizeSuffix: String, cstrSuffix: String,
        encoding: String.Encoding, defaultSizeType: any FixedWidthInteger.Type
    ) {
        self.state = state
        self.order = order
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

    fileprivate func encodeInteger<T: FixedWidthInteger>(_ value: T) {
        SmartBinaryIO.writeInteger(value, &data, order)
    }

    fileprivate func encodeFloat<T: BinaryFloatingPoint>(_ value: T) {
        SmartBinaryIO.writeFloat(value, &data, order)
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
                    value: dataValue, into: &encoder.data, order: encoder.order)
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

    func corrupted(_ text: String) -> DecodingError {
        return DecodingError.dataCorrupted(
            .init(codingPath: codingPath, debugDescription: text))
    }

    mutating func encodeNil() throws {}

    mutating func encode<T: Encodable>(_ value: T) throws {
        let fieldName = codingPath.last?.stringValue ?? ""

        switch value {

        case let v as Bool:
            Bool.write(v, into: &encoder.data)
        //encoder.data.append(v ? 1 : 0)
        case let v as any FixedWidthInteger:
            if fieldName.hasSuffix(encoder.sizeSuffix) {
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
                SmartBinaryIO.writeStringData(
                    v + "\0", into: &encoder.data,
                    order: encoder.order, encoding: encoder.encoding
                )
                //if let encodedData = v.data(using: encoder.encoding) {
                //    encoder.data.append(encodedData)
                //}
                //encoder.data.append(0)
                return
            }
            let sizeType = encoder.sizeFieldType[fieldName] ?? encoder.defaultSizeType
            SmartBinaryIO.writeString(
                sizeType, v, into: &encoder.data,
                order: encoder.order, encoding: encoder.encoding
            )

        case let v as Data:
            if fieldName.hasSuffix(encoder.sizeSuffix) {
                return
            }
            let sizeType = encoder.sizeFieldType[fieldName] ?? encoder.defaultSizeType
            SmartBinaryIO.writeData(sizeType, v, into: &encoder.data, order: encoder.order)

        default:
            try value.encode(to: encoder)
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
/// - **order**: Must match the byte order used during encoding (default: little-endian)
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
    public let order: ByteOrder

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
    ///   - order: Byte order (must match encoder, default: `.littleEndian`)
    ///   - sizeSuffix: Size field suffix (must match encoder, default: `"Size"`)
    ///   - cstrSuffix: C-string field suffix (must match encoder, default: `"Cstr"`)
    ///   - encoding: String encoding (must match encoder, default: `.utf8`)
    ///   - defaultSizeType: Default size type for encoding multi-byte values (default: `UInt32.self`)
    public init(
        data: Data,
        order: ByteOrderOption = .littleEndian,
        sizeSuffix: String = "Size",
        cstrSuffix: String = "Cstr",
        encoding: String.Encoding = .utf8,
        defaultSizeType: any FixedWidthInteger.Type = UInt32.self
    ) {
        self.data = data
        self.order = order.toByteOrder()
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
            data: data, offset: offset, order: order, sizeSuffix: sizeSuffix,
            cstrSuffix: cstrSuffix, encoding: encoding, defaultSizeType: defaultSizeType)
        let decoder = DecoderImpl(state: state)
        let result = try T(from: decoder)
        offset = state.offset
        return result
    }

    var bytesRemaining: Int {
        // data.count represents the total length of the slice/buffer
        // offset represents how many bytes we've consumed
        return Swift.max(0, data.count - offset)
    }
}

// MARK: - Decoder Implementation (Private)

// MARK: Decoder State

private class DecoderState {
    var data: Data
    var offset: Int
    let order: ByteOrder
    let sizeSuffix: String
    let cstrSuffix: String
    let encoding: String.Encoding
    var defaultSizeType: any FixedWidthInteger.Type
    var sizeFieldType: [String: any FixedWidthInteger.Type] = [:]

    init(
        data: Data, offset: Int, order: ByteOrder, sizeSuffix: String, cstrSuffix: String,
        encoding: String.Encoding, defaultSizeType: any FixedWidthInteger.Type
    ) {
        self.data = data
        self.offset = offset
        self.order = order
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
    var order: ByteOrder { state.order }
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

    public func decodeInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        return try SmartBinaryIO.readInteger(type, data, offset: &offset, order: order)

    }
    public func decodeFloat<T: BinaryFloatingPoint>(_ type: T.Type) throws -> T {
        return try SmartBinaryIO.readFloat(type, data, offset: &offset, order: order)
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

    func corrupted(_ text: String) -> DecodingError {
        return DecodingError.dataCorrupted(
            .init(codingPath: codingPath, debugDescription: text))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let fieldName = codingPath.last?.stringValue ?? ""

        guard decoder.offset < decoder.data.count else {
            throw corrupted("Insufficient data")
        }

        if let intType = type as? any FixedWidthInteger.Type {
            let value = try decoder.decodeInteger(intType)
            if fieldName.hasSuffix(decoder.sizeSuffix) {
                decoder.sizeFieldValue[fieldName.removeSuffix(decoder.sizeSuffix)] = value
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
            let value = try Bool.read(decoder.data, offset: &decoder.offset)
            return value as! T
        }

        if type == String.self {
            var count: Int = 0

            // Search for \0
            if fieldName.hasSuffix(decoder.cstrSuffix) {
                let currentPos = decoder.data.startIndex + decoder.offset
                guard let termPos = decoder.data[currentPos...].firstIndex(of: 0) else {
                    throw corrupted("Null terminator not found for C-style string")
                }
                count = termPos - currentPos

            } else {
                count = try getFieldSize(fieldName)
            }

            // Extract string data
            let data = try SmartBinaryIO.readData(
                Int(count), decoder.data, &decoder.offset)
            guard let string = String(data: data, encoding: decoder.encoding) else {
                throw corrupted("Invalid string encoding")
            }

            if fieldName.hasSuffix(decoder.cstrSuffix) {
                decoder.offset += 1
            }

            return string as! T

        }
        if type == Data.self {
            let count = try getFieldSize(fieldName)
            let data = try SmartBinaryIO.readData(
                Int(count), decoder.data, &decoder.offset)
            return data as! T
        }
        return try T(from: decoder)
    }

    private func getFieldSize(_ fieldName: String) throws -> Int {
        if let sizeValue = decoder.sizeFieldValue[fieldName] {
            return Int(sizeValue)
        } else {
            let sizeValue = try decoder.decodeInteger(decoder.defaultSizeType)
            return Int(sizeValue)
        }
    }

}
