# SmartBinaryCodable

A high-performance binary encoding/decoding library for Swift that integrates with Swift's standard `Codable` protocol.

## Features

- **Codable Integration** - Seamlessly encode/decode Swift types using the familiar `Codable` protocol
- **Configurable Byte Order** - Support for little-endian, big-endian, and native byte orders
- **Size-Prefixed Strings** - Automatic length encoding for `String` and `Data` fields
- **C-String Support** - Null-terminated string encoding for interoperability
- **Full Type Support** - All standard Swift numeric types (integers, floats, doubles, bools)
- **Swift Package Manager** - Easy integration via SPM

## Requirements

- Swift 6.2+
- macOS, iOS, Linux, or any platform supported by Swift

## Installation

### Swift Package Manager

Add SmartBinaryCodable to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/noworrieseh/SmartBinaryCodable", from: "0.1.0")
]
```

## Usage

### Basic Encoding/Decoding

```swift
import SmartBinaryCodable

struct Server: Codable {
    let nameSize: UInt16
    let name: String
    let port: UInt16
}

let server = Server(nameSize: 4, name: "test", port: 8080)

// Encoding
let encoder = SmartBinaryEncoder()
let data = try encoder.encode(server)

// Decoding
let decoder = SmartBinaryDecoder(data: data)
let decodedServer = try decoder.decode(Server.self)
```

### Size Field Convention

String and `Data` fields use a corresponding size field ending with `Size` (configurable). The size field must appear before the data field:

```swift
struct Message: Codable {
    let contentSize: UInt16  // Size field
    let content: String      // Data field
}
```

Supported size types: `UInt8`, `UInt16`, `UInt32`, `UInt64`

### C-String Support

Fields ending with `Cstr` are encoded/decoded as null-terminated strings:

```swift
struct User: Codable {
    let nameCstr: String  // Encoded with null terminator
}
```

### Configuration

```swift
let encoder = SmartBinaryEncoder(
    byteOrder: .littleEndian,    // Byte order (default: .littleEndian)
    sizeSuffix: "Size",          // Size field suffix (default: "Size")
    cstrSuffix: "Cstr",          // C-string suffix (default: "Cstr")
    encoding: .utf8,             // String encoding (default: .utf8)
    defaultSizeType: UInt32.self // Default size type (default: UInt32.self)
)

let decoder = SmartBinaryDecoder(
    data: data,
    byteOrder: .littleEndian,
    sizeSuffix: "Size",
    cstrSuffix: "Cstr",
    encoding: .utf8,
    defaultSizeType: UInt32.self
)
```

### Incremental Encoding

```swift
let encoder = SmartBinaryEncoder()
try encoder.encodeAndAppend(value1)
try encoder.encodeAndAppend(value2)
let data = encoder.getData()
```

## License

MIT
