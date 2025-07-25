import Foundation
import SMC

public extension FourCharCode {
  public init(fromStaticString str: StaticString) {
    precondition(str.utf8CodeUnitCount == 4)

    self = str.withUTF8Buffer { buffer in
      buffer.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
  }

  public init(fromCharArray charArray: UInt32Char_t) {
    self =
      (UInt32(charArray.0) << 24) | (UInt32(charArray.1) << 16) | (UInt32(charArray.2) << 8)
      | UInt32(charArray.3)
  }

  public func toString() -> String {
    let bytes: [UInt8] = [
      UInt8((self >> 24) & 0xFF),
      UInt8((self >> 16) & 0xFF),
      UInt8((self >> 8) & 0xFF),
      UInt8(self & 0xFF),
    ]
    return String(bytes.map { Character(UnicodeScalar($0)) })
  }

  internal func toCharArray() -> UInt32Char_t {
    return (
      UInt8((self >> 24) & 0xFF),
      UInt8((self >> 16) & 0xFF),
      UInt8((self >> 8) & 0xFF),
      UInt8(self & 0xFF),
      UInt8(0)
    )
  }
}

public struct DataType: Equatable {
  public let type: FourCharCode
  public let size: UInt32
}

// TODO Other DataTypes from other machines?
enum DataTypes {
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

public protocol SMCCodable {
  static var smcDataType: DataType { get }
  init(_ raw: SMCBytes_t) throws
  func encode() throws -> SMCBytes_t
}

@inlinable func smcBytes(_ slice: [UInt8]) -> SMCBytes_t {
  var tmp = [UInt8](repeating: 0, count: 32)
  tmp.replaceSubrange(0..<min(slice.count, 32), with: slice)
  return unsafeBitCast(tmp, to: SMCBytes_t.self)
}

@inlinable func toBytes<T>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v) { Array($0) } }
@inlinable func fromBytes<T>(_ b: [UInt8]) -> T { b.withUnsafeBytes { $0.load(as: T.self) } }

extension UInt8: SMCCodable {
  public static var smcDataType: DataType { DataTypes.UInt8 }

  public init(_ raw: SMCBytes_t) throws {
    self = raw.0
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes([self])
  }
}

extension UInt16: SMCCodable {
  public static var smcDataType: DataType { DataTypes.UInt16 }

  public init(_ raw: SMCBytes_t) throws {
    self = (UInt16(raw.0) << 8) | UInt16(raw.1)
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes([UInt8(self >> 8), UInt8(self & 0xFF)])
  }
}

extension UInt32: SMCCodable {
  public static var smcDataType: DataType { DataTypes.UInt32 }

  public init(_ raw: SMCBytes_t) throws {
    self = (UInt32(raw.0) << 24) | (UInt32(raw.1) << 16) | (UInt32(raw.2) << 8) | UInt32(raw.3)
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes([
      UInt8((self >> 24) & 0xFF),
      UInt8((self >> 16) & 0xFF),
      UInt8((self >> 8) & 0xFF),
      UInt8(self & 0xFF),
    ])
  }
}

extension Int8: SMCCodable {
  public static var smcDataType: DataType { DataTypes.Int8 }

  public init(_ raw: SMCBytes_t) throws {
    self = Int8(bitPattern: raw.0)
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes([UInt8(bitPattern: self)])
  }
}

extension Int16: SMCCodable {
  public static var smcDataType: DataType { DataTypes.Int16 }

  public init(_ raw: SMCBytes_t) throws {
    let unsigned = UInt16(raw.0) << 8 | UInt16(raw.1)
    self = Int16(bitPattern: unsigned)
  }

  public func encode() throws -> SMCBytes_t {
    let u = UInt16(bitPattern: self)
    return smcBytes([UInt8(u >> 8), UInt8(u & 0xFF)])
  }
}

extension Int32: SMCCodable {
  public static var smcDataType: DataType { DataTypes.Int32 }

  public init(_ raw: SMCBytes_t) throws {
    let u = UInt32(raw.0) << 24 | UInt32(raw.1) << 16 | UInt32(raw.2) << 8 | UInt32(raw.3)
    self = Int32(bitPattern: u)
  }

  public func encode() throws -> SMCBytes_t {
    let u = UInt32(bitPattern: self)
    return smcBytes([
      UInt8((u >> 24) & 0xFF),
      UInt8((u >> 16) & 0xFF),
      UInt8((u >> 8) & 0xFF),
      UInt8(u & 0xFF),
    ])
  }
}

extension Float: SMCCodable {
  public static var smcDataType: DataType { DataTypes.Float }

  public init(_ raw: SMCBytes_t) throws {
    let bytes = [raw.0, raw.1, raw.2, raw.3]
    self = fromBytes(bytes)
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes(toBytes(self))
  }
}

extension Bool: SMCCodable {
  public static var smcDataType: DataType { DataTypes.Flag }

  public init(_ raw: SMCBytes_t) throws {
    self = (raw.0 != 0)
  }

  public func encode() throws -> SMCBytes_t {
    smcBytes([self ? 1 : 0])
  }
}
