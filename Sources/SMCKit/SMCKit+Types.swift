import Foundation
import SMC

extension FourCharCode: @retroactive ExpressibleByStringLiteral {
    public init(fromStaticString str: StaticString) {
        precondition(str.utf8CodeUnitCount == 4)

        self = str.withUTF8Buffer { buffer in
            buffer.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
    }

    public init(stringLiteral value: String) {
        let bytes = value.utf8
        precondition(
            bytes.count == 4,
            "FourCharCode must be exactly 4 UTF-8 bytes"
        )
        self = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    public init(fromCharArray charArray: UInt32Char_t) {
        self =
            (UInt32(charArray.chars.0) << 24)
            | (UInt32(charArray.chars.1) << 16)
            | (UInt32(charArray.chars.2) << 8)
            | UInt32(charArray.chars.3)
    }

    public func toString() -> String {
        var string = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            string.unicodeScalars.append(
                UnicodeScalar(UInt8(truncatingIfNeeded: self >> shift))
            )
        }
        return string
    }

    internal func toCharArray() -> UInt32Char_t {
        return UInt32Char_t(
            chars: (
                UInt8((self >> 24) & 0xFF),
                UInt8((self >> 16) & 0xFF),
                UInt8((self >> 8) & 0xFF),
                UInt8(self & 0xFF),
                UInt8(0)
            )
        )
    }
}

public struct DataType: Equatable {
    public let type: FourCharCode
    public let size: UInt32
}

// TODO Other DataTypes from other machines?
enum DataTypes {
    static let UInt8 = DataType(
        type: FourCharCode(fromStaticString: "ui8 "),
        size: 1
    )
    static let UInt16 = DataType(
        type: FourCharCode(fromStaticString: "ui16"),
        size: 2
    )
    static let UInt32 = DataType(
        type: FourCharCode(fromStaticString: "ui32"),
        size: 4
    )
    static let UInt64 = DataType(
        type: FourCharCode(fromStaticString: "ui64"),
        size: 8
    )

    static let Int8 = DataType(
        type: FourCharCode(fromStaticString: "si8 "),
        size: 1
    )
    static let Int16 = DataType(
        type: FourCharCode(fromStaticString: "si16"),
        size: 2
    )
    static let Int32 = DataType(
        type: FourCharCode(fromStaticString: "si32"),
        size: 4
    )
    static let Int64 = DataType(
        type: FourCharCode(fromStaticString: "si64"),
        size: 8
    )

    static let Flag = DataType(
        type: FourCharCode(fromStaticString: "flag"),
        size: 1
    )
    static let Float = DataType(
        type: FourCharCode(fromStaticString: "flt "),
        size: 4
    )

    static let HexData = DataType(
        type: FourCharCode(fromStaticString: "hex_"),
        size: 0
    )
    static let Ch8String = DataType(
        type: FourCharCode(fromStaticString: "ch8*"),
        size: 0
    )
}

public protocol SMCCodable {
    static var smcDataType: DataType { get }
    init(_ raw: SMCBytes_t) throws
    func encode() throws -> SMCBytes_t
}

func smcBytes<Bytes: Collection>(_ bytes: Bytes) -> SMCBytes_t
where Bytes.Element == UInt8 {
    var result = SMCVal_t().bytes
    withUnsafeMutableBytes(of: &result) { buffer in
        buffer.copyBytes(from: bytes.prefix(buffer.count))
    }
    return result
}

func smcBytes<T>(of value: T) -> SMCBytes_t {
    withUnsafeBytes(of: value) { smcBytes($0) }
}

func loadValue<T>(_ raw: SMCBytes_t, as type: T.Type = T.self) -> T {
    withUnsafeBytes(of: raw) { $0.loadUnaligned(as: T.self) }
}

extension SMCCodable where Self: FixedWidthInteger {
    public init(_ raw: SMCBytes_t) throws {
        self.init(littleEndian: loadValue(raw))
    }

    public func encode() throws -> SMCBytes_t {
        smcBytes(of: littleEndian)
    }
}

extension UInt8: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt8 }
}

extension UInt16: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt16 }
}

extension UInt32: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt32 }
}

extension UInt64: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt64 }
}

extension Int8: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int8 }
}

extension Int16: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int16 }
}

extension Int32: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int32 }
}

extension Int64: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int64 }
}

extension Float: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Float }

    public init(_ raw: SMCBytes_t) throws {
        self = loadValue(raw)
    }

    public func encode() throws -> SMCBytes_t {
        smcBytes(of: self)
    }
}

extension Bool: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Flag }

    public init(_ raw: SMCBytes_t) throws {
        self = (raw.0 != 0)
    }

    public func encode() throws -> SMCBytes_t {
        smcBytes(of: UInt8(self ? 1 : 0))
    }
}

// MARK: - Big-Endian Wrapper

/// A wrapper for reading/writing SMC keys that store integer values in big-endian byte order.
///
/// Most SMC keys on Apple Silicon use little-endian byte order, which is what the default
/// `SMCCodable` conformances use. However, a small number of keys (e.g. `#KEY`, `RBID`, `RBRV`,
/// `D1BD`, `FOFC`, `MPPR`) store values in big-endian order. Use this wrapper for those keys.
///
/// ```swift
/// let count: BigEndian<UInt32> = try SMCKit.shared.read("#KEY")
/// print(count.value) // 3209
/// ```
public struct BigEndian<Value: FixedWidthInteger & SMCCodable>: SMCCodable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public static var smcDataType: DataType { Value.smcDataType }

    public init(_ raw: SMCBytes_t) throws {
        self.value = Value(bigEndian: loadValue(raw))
    }

    public func encode() throws -> SMCBytes_t {
        smcBytes(of: value.bigEndian)
    }
}
