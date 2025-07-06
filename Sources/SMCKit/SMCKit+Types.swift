import Foundation


public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8)

public protocol SMCDecodable {
    static var smcDataType: DataType { get }
    init(_ raw: SMCBytes) throws
}

public protocol SMCEncodable {
    static var smcDataType: DataType { get }
    func encodeSMC() throws -> SMCBytes
}

public typealias SMCCodable = SMCDecodable & SMCEncodable

@inlinable
func smcBytes(_ slice: [UInt8]) -> SMCBytes {
    var tmp = [UInt8](repeating: 0, count: 32)
    tmp.replaceSubrange(0..<min(slice.count, 32), with: slice)
    return unsafeBitCast(tmp, to: SMCBytes.self)
}

@inlinable func toBytes<T>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v) { Array($0) } }
@inlinable func fromBytes<T>(_ b: [UInt8]) -> T { b.withUnsafeBytes { $0.load(as: T.self) } }

extension UInt8: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt8 }
    
    public init(_ raw: SMCBytes) throws {
        self = raw.0
    }
    
    public func encodeSMC() throws -> SMCBytes {
        smcBytes([self])
    }
}

extension UInt16: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt16 }

    public init(_ raw: SMCBytes) throws {
        self = (UInt16(raw.0) << 8) | UInt16(raw.1)
    }

    public func encodeSMC() throws -> SMCBytes {
        smcBytes([UInt8(self >> 8), UInt8(self & 0xFF)])
    }
}

extension UInt32: SMCCodable {
    public static var smcDataType: DataType { DataTypes.UInt32 }

    public init(_ raw: SMCBytes) throws {
        self = (UInt32(raw.0) << 24) |
               (UInt32(raw.1) << 16) |
               (UInt32(raw.2) << 8)  |
               UInt32(raw.3)
    }

    public func encodeSMC() throws -> SMCBytes {
        smcBytes([
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ])
    }
}

extension Int8: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int8 }

    public init(_ raw: SMCBytes) throws {
        self = Int8(bitPattern: raw.0)
    }

    public func encodeSMC() throws -> SMCBytes {
        smcBytes([UInt8(bitPattern: self)])
    }
}

extension Int16: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int16 }

    public init(_ raw: SMCBytes) throws {
        let unsigned = UInt16(raw.0) << 8 | UInt16(raw.1)
        self = Int16(bitPattern: unsigned)
    }

    public func encodeSMC() throws -> SMCBytes {
        let u = UInt16(bitPattern: self)
        return smcBytes([UInt8(u >> 8), UInt8(u & 0xFF)])
    }
}

extension Int32: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Int32 }

    public init(_ raw: SMCBytes) throws {
        let u = UInt32(raw.0) << 24 |
                UInt32(raw.1) << 16 |
                UInt32(raw.2) << 8  |
                UInt32(raw.3)
        self = Int32(bitPattern: u)
    }

    public func encodeSMC() throws -> SMCBytes {
        let u = UInt32(bitPattern: self)
        return smcBytes([
            UInt8((u >> 24) & 0xFF),
            UInt8((u >> 16) & 0xFF),
            UInt8((u >> 8) & 0xFF),
            UInt8(u & 0xFF)
        ])
    }
}

extension Float: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Float }

    public init(_ raw: SMCBytes) throws {
        let bytes = [raw.0, raw.1, raw.2, raw.3]
        self = fromBytes(bytes)
    }

    public func encodeSMC() throws -> SMCBytes {
        smcBytes(toBytes(self))
    }
}

extension Bool: SMCCodable {
    public static var smcDataType: DataType { DataTypes.Flag }

    public init(_ raw: SMCBytes) throws {
        self = (raw.0 != 0)
    }

    public func encodeSMC() throws -> SMCBytes {
        smcBytes([self ? 1 : 0])
    }
}

public extension FourCharCode {
    init(fromStaticString str: StaticString) {
        precondition(str.utf8CodeUnitCount == 4)
        
        self = str.withUTF8Buffer { buffer in
            buffer.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
    }
    
    func toString() -> String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
        return String(bytes.map { Character(UnicodeScalar($0)) })
    }
}

struct SMCParamStruct {
    /// I/O Kit function selector
    enum Selector: UInt8 {
        case kSMCHandleYPCEvent = 2
        case kSMCReadKey = 5
        case kSMCWriteKey = 6
        case kSMCGetKeyFromIndex = 8
        case kSMCGetKeyInfo = 9
    }
    
    /// Return codes for SMCParamStruct.result property
    enum Result: UInt8 {
        case kSMCSuccess = 0
        case kSMCError = 1
        case kSMCKeyNotFound = 132
    }
    
    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    
    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct SMCKeyInfoData {
        /// Number of bytes used in `bytes`
        var dataSize: UInt32 = 0

        /// Data type of the bytes, helps interpreting the data
        var dataType: UInt32 = 0

        var dataAttributes: UInt8 = 0
    }
    
    var key: FourCharCode = 0              // FourCharCode representing SMC key
    var vers: SMCVersion = .init()
    var pLimitData: SMCPLimitData = .init()
    var keyInfo: SMCKeyInfoData = .init()

    var padding: UInt16 = 0               // For struct alignment

    var result: UInt8 = 0                 // Result code of the operation
    var status: UInt8 = 0                 // Additional status info
    var data8: UInt8 = 0                  // Method selector or data
    var data32: UInt32 = 0                // Additional 32-bit data

    // 32-byte data block returned from SMC
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
    
}

public struct DataType: Equatable {
    let type: FourCharCode
    let size: UInt32
}

public enum DataTypes {
    static let UInt8 = DataType(type: FourCharCode(fromStaticString: "ui8 "), size: 1)
    static let UInt16 = DataType(type: FourCharCode(fromStaticString: "ui16"), size: 2)
    static let UInt32 = DataType(type: FourCharCode(fromStaticString: "ui32"), size: 4)
    static let UInt64 = DataType(type: FourCharCode(fromStaticString: "ui64"), size: 8)
    
    static let Int8 = DataType(type: FourCharCode(fromStaticString: "si8 "), size: 1)
    static let Int16 = DataType(type: FourCharCode(fromStaticString: "si16"), size: 2)
    static let Int32 = DataType(type: FourCharCode(fromStaticString: "si32"), size: 4)
    static let Int64 = DataType(type: FourCharCode(fromStaticString: "si64"), size: 8)

    static let Flag = DataType(type: FourCharCode(fromStaticString: "flag"), size: 1)
    static let Float = DataType(type: FourCharCode(fromStaticString: "flt "), size: 4)
}

public struct SMCKey<Value: SMCCodable> {
    public let code: FourCharCode
    public var info: DataType { Value.smcDataType }
    
    public init(_ str: StaticString) {
        self.code = FourCharCode(fromStaticString: str)
    }
}
