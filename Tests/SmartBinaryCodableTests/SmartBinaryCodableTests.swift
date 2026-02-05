import Foundation
import Testing
import XCTest

@testable import SmartBinaryCodable

// MARK: - Test Fixtures

public struct SmartSimpleStruct: Codable, Equatable {
    public var field1: UInt8
    public var field2: UInt16
    public var field3: UInt32
    public var field4: UInt64

    public init(field1: UInt8 = 0, field2: UInt16 = 0, field3: UInt32 = 0, field4: UInt64 = 0) {
        self.field1 = field1
        self.field2 = field2
        self.field3 = field3
        self.field4 = field4
    }
}

public struct SmartSignedStruct: Codable, Equatable {
    public var int8Val: Int8
    public var int16Val: Int16
    public var int32Val: Int32
    public var int64Val: Int64

    public init(int8Val: Int8 = 0, int16Val: Int16 = 0, int32Val: Int32 = 0, int64Val: Int64 = 0) {
        self.int8Val = int8Val
        self.int16Val = int16Val
        self.int32Val = int32Val
        self.int64Val = int64Val
    }
}

public struct SmartFloatingPointStruct: Codable, Equatable {
    public var floatVal: Float
    public var doubleVal: Double

    public init(floatVal: Float = 0.0, doubleVal: Double = 0.0) {
        self.floatVal = floatVal
        self.doubleVal = doubleVal
    }
}

public struct SmartBoolStruct: Codable, Equatable {
    public var flag1: Bool
    public var flag2: Bool
    public var value: UInt8

    public init(flag1: Bool = false, flag2: Bool = false, value: UInt8 = 0) {
        self.flag1 = flag1
        self.flag2 = flag2
        self.value = value
    }
}

public struct SmartNestedStruct: Codable, Equatable {
    public var simple: SmartSimpleStruct
    public var id: UInt32

    public init(simple: SmartSimpleStruct = SmartSimpleStruct(), id: UInt32 = 0) {
        self.simple = simple
        self.id = id
    }
}

public struct SmartStringStruct: Codable, Equatable {
    public var strSize: UInt8
    public var str: String

    //public init(str: String) {
    //    self.strSize = 0
    //    //self.strSize = UInt8(str.utf8.count)
    //    self.str = str
    //}
}

public struct SmartDataStruct: Codable, Equatable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

public struct SmartStringSizedUInt8: Codable, Equatable {
    public var stringSize: UInt8
    public var string: String
}

public struct SmartStringSizedUInt16: Codable, Equatable {
    public var stringSize: UInt16
    public var string: String
}

public struct SmartStringSizedUInt32: Codable, Equatable {
    public var stringSize: UInt32
    public var string: String
}

public struct SmartStringSizedUInt64: Codable, Equatable {
    public var stringSize: UInt64
    public var string: String
}

public struct SmartDataSizedUInt32: Codable, Equatable {
    public var dataSize: UInt32
    public var data: Data
}

public struct SmartStringNoSize: Codable, Equatable {
    public var string: String
}

public struct SmartCString: Codable, Equatable {
    public var nameCstr: String
}

public struct Version: Codable, Equatable {
    public var major: UInt16
    public var minor: UInt8
    public var patch: UInt8
}

public struct Server: Codable, Equatable {
    public var id: UInt32
    public var name: String
    public var version: Version
}

public struct Cluster: Codable, Equatable {
    public var id: UInt32
    public var name: String
    public var servers: [Server]
}

class SmartBinaryCoderTests: XCTestCase {

    func testRoundTripSimpleStruct() throws {
        let original = SmartSimpleStruct(
            field1: 0x42, field2: 0x1234, field3: 0x5678_90AB, field4: 0x1234_5678_90AB_CDEF)

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartSimpleStruct.self)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripSignedStruct() throws {
        let original = SmartSignedStruct(
            int8Val: -42, int16Val: -1000, int32Val: -100000, int64Val: -10_000_000_000)

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartSignedStruct.self)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripFloatingPointStruct() throws {
        let original = SmartFloatingPointStruct(floatVal: 3.14, doubleVal: 3.141592653589793)
        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartFloatingPointStruct.self)

        XCTAssertEqual(original.floatVal, decoded.floatVal, accuracy: 0.001)
        XCTAssertEqual(original.doubleVal, decoded.doubleVal, accuracy: 0.0001)
    }

    func testRoundTripNestedStruct() throws {
        let simple = SmartSimpleStruct(field1: 0x11, field2: 0x2222, field3: 0x3333_3333)
        let original = SmartNestedStruct(simple: simple, id: 0x4444_4444)

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartNestedStruct.self)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripStringStruct() throws {
        let original = SmartStringStruct(strSize: 0, str: "Hello, World!")
        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringStruct.self)

        //XCTAssertEqual(original.str, original.str)

        //XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.str, decoded.str)
        XCTAssertEqual(decoded.strSize, UInt8(original.str.utf8.count))

    }

    func testRoundTripDataStruct() throws {
        let original = SmartDataStruct(data: "Hello, World!".data(using: .utf8)!)

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartDataStruct.self)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Automatic Sizing Tests

    func testRoundTripStringStructSizedUInt8() throws {
        let original = SmartStringSizedUInt8(stringSize: 0, string: "Test String")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringSizedUInt8.self)

        XCTAssertEqual(decoded.string, original.string)
        XCTAssertEqual(decoded.stringSize, UInt8(original.string.utf8.count))
    }

    func testRoundTripStringStructSizedUInt16() throws {
        let original = SmartStringSizedUInt16(stringSize: 0, string: "Another Test String")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringSizedUInt16.self)

        XCTAssertEqual(decoded.string, original.string)
        XCTAssertEqual(decoded.stringSize, UInt16(original.string.utf8.count))
    }

    func testRoundTripStringStructSizedUInt32() throws {
        let original = SmartStringSizedUInt32(
            stringSize: 0, string: "A much longer string to test with a 32-bit size")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringSizedUInt32.self)

        XCTAssertEqual(decoded.string, original.string)
        XCTAssertEqual(decoded.stringSize, UInt32(original.string.utf8.count))
    }

    func testRoundTripStringStructSizedUInt64() throws {
        let original = SmartStringSizedUInt64(
            stringSize: 0, string: "A string with a 64-bit size field, which is quite large")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringSizedUInt64.self)

        XCTAssertEqual(decoded.string, original.string)
        XCTAssertEqual(decoded.stringSize, UInt64(original.string.utf8.count))
    }

    func testRoundTripDataStructSizedUInt32() throws {
        let originalData = "Some raw data".data(using: .utf8)!
        let original = SmartDataSizedUInt32(dataSize: 0, data: originalData)

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartDataSizedUInt32.self)

        XCTAssertEqual(decoded.data, original.data)
        XCTAssertEqual(decoded.dataSize, UInt32(original.data.count))
    }

    func testRoundTripStringStructNoSize() throws {
        let original = SmartStringNoSize(
            string: "A much longer string to test with a 32-bit size")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartStringNoSize.self)

        XCTAssertEqual(decoded.string, original.string)
        //XCTAssertEqual(decoded.stringSize, UInt32(original.string.utf8.count))
    }

    func testRoundTripCString() throws {
        let original = SmartCString(nameCstr: "terminator")

        let encoder = SmartBinaryEncoder(order: .littleEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .littleEndian)
        let decoded = try decoder.decode(SmartCString.self)

        XCTAssertEqual(original, decoded)
        // Check for null terminator
        XCTAssertEqual(data.last, 0)
    }

    func testRoundTripNested() throws {
        let server1 = Server(id: 1, name: "server1", version: Version(major: 1, minor: 0, patch: 0))
        let server2 = Server(id: 2, name: "server2", version: Version(major: 2, minor: 0, patch: 0))
        let original = Cluster(id: 1, name: "cluster", servers: [server1, server2])
        let encoder = SmartBinaryEncoder(order: .bigEndian)
        let data = try encoder.encode(original)

        let decoder = SmartBinaryDecoder(data: data, order: .bigEndian)
        let decoded = try decoder.decode(Cluster.self)

        XCTAssertEqual(original, decoded)
        // Check for null terminator
    }
}
