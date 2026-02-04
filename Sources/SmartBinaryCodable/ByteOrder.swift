import Foundation

public enum ByteOrderOption {
    case native
    case littleEndian
    case bigEndian
    public func toByteOrder() -> ByteOrder {
        switch self {
        case .native:
            if isLittleEndian() {
                return .littleEndian
            } else {
                return .bigEndian
            }
        case .littleEndian:
            return .littleEndian
        case .bigEndian:
            return .bigEndian
        }
    }
}

public enum ByteOrder {
    case littleEndian
    case bigEndian
}

public func isLittleEndian() -> Bool {
    var number: UInt16 = 0x1
    return withUnsafeBytes(of: &number) { buffer in
        buffer.load(as: UInt8.self) == 1
    }
}
