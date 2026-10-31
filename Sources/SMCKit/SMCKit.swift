import Foundation
import IOKit
import SMC

public final class SMCKit: Sendable {
    public static let shared: SMCKit = try! SMCKit()

    private let connection: io_connect_t

    private init() throws {
        var conn: io_connect_t = 0
        let result = SMCOpen(&conn)

        guard result == kIOReturnSuccess else {
            throw SMCError.connectionFailed(kIOReturn: result)
        }
        self.connection = conn
    }

    deinit {
        SMCClose(connection)
    }

    public func getKeyInformation(_ key: FourCharCode) throws -> DataType {
        var keyInfo = SMCKeyData_keyInfo_t()
        let result = SMCGetKeyInfo(key, &keyInfo, self.connection)
        try check(result, key: key.toString())
        return DataType(type: keyInfo.dataType, size: keyInfo.dataSize)
    }

    public func isKeyFound(_ key: FourCharCode) throws -> Bool {
        do {
            _ = try getKeyInformation(key)
            return true
        } catch SMCError.keyNotFound {
            return false
        }
    }

    public func read<V: SMCCodable>(_ key: FourCharCode) throws -> V {
        try V(readValue(key).bytes)
    }

    public func write<V: SMCCodable>(_ key: FourCharCode, _ value: V) throws {
        try writeValue(key, dataType: V.smcDataType, bytes: value.encode())
    }

    public func readData(_ key: FourCharCode) throws -> Data {
        let smcVal = try readValue(key)
        let validSize = min(Int(smcVal.dataSize), MemoryLayout<SMCBytes_t>.size)
        return withUnsafeBytes(of: smcVal.bytes) { buffer in
            Data(buffer.prefix(validSize))
        }
    }

    public func readString(_ key: FourCharCode) throws -> String {
        let smcVal = try readValue(key)
        let validSize = min(Int(smcVal.dataSize), MemoryLayout<SMCBytes_t>.size)
        let string = withUnsafeBytes(of: smcVal.bytes) { buffer in
            String(bytes: buffer.prefix(validSize).prefix { $0 != 0 }, encoding: .ascii)
        }

        guard let string else {
            throw SMCError.invalidStringData(key: key.toString())
        }
        return string
    }

    public func writeData(_ key: FourCharCode, _ value: Data) throws {
        let keyInfo = try getKeyInformation(key)

        guard keyInfo.type == DataTypes.HexData.type else {
            throw SMCError.dataTypeMismatch(key: key.toString())
        }

        guard value.count == keyInfo.size else {
            throw SMCError.invalidDataSize(
                key: key.toString(),
                expected: keyInfo.size,
                actual: UInt32(value.count)
            )
        }

        try writeValue(key, dataType: keyInfo, bytes: smcBytes(value))
    }

    public func writeString(_ key: FourCharCode, _ value: String) throws {
        let keyInfo = try getKeyInformation(key)

        guard keyInfo.type == DataTypes.Ch8String.type else {
            throw SMCError.dataTypeMismatch(key: key.toString())
        }

        let stringBytes = value.utf8
        guard stringBytes.allSatisfy({ $0 < 0x80 }) else {
            throw SMCError.invalidStringData(key: key.toString())
        }

        guard stringBytes.count <= keyInfo.size else {
            throw SMCError.invalidDataSize(
                key: key.toString(),
                expected: keyInfo.size,
                actual: UInt32(stringBytes.count)
            )
        }

        try writeValue(key, dataType: keyInfo, bytes: smcBytes(stringBytes))
    }

    public func numKeys() throws -> UInt32 {
        let result: BigEndian<UInt32> = try self.read(FourCharCode(fromStaticString: "#KEY"))
        return result.value
    }

    public func allKeys() throws -> [FourCharCode] {
        let numKeys = try self.numKeys()
        var keys: [FourCharCode] = []
        keys.reserveCapacity(Int(numKeys))

        for index in 0..<numKeys {
            var keyBuffer = UInt32Char_t()
            let result = SMCGetKeyFromIndex(index, &keyBuffer, self.connection)
            try check(result, key: "Index \(index)")
            keys.append(FourCharCode(fromCharArray: keyBuffer))
        }

        return keys
    }

    private func readValue(_ key: FourCharCode) throws -> SMCVal_t {
        var keyCharArray = key.toCharArray()
        var smcVal = SMCVal_t()

        let result = SMCReadKey(&keyCharArray, &smcVal, self.connection)
        try check(result, key: key.toString())
        return smcVal
    }

    private func writeValue(
        _ key: FourCharCode,
        dataType: DataType,
        bytes: SMCBytes_t
    ) throws {
        var smcVal = SMCVal_t(
            key: key.toCharArray(),
            dataSize: dataType.size,
            dataType: dataType.type.toCharArray(),
            bytes: bytes
        )

        let result = SMCWriteKey(&smcVal, self.connection)
        try check(result, key: key.toString())
    }

    // The key description is only built on failure, so the success path stays
    // free of string formatting.
    private func check(_ result: SMCResult_t, key: @autoclosure () -> String) throws {
        switch (result.kern_res, result.smc_res) {
        case (kIOReturnSuccess, UInt8(kSMCReturnSuccess)):
            return
        case (kIOReturnSuccess, UInt8(kSMCReturnKeyNotFound)):
            throw SMCError.keyNotFound(key: key())
        case (kIOReturnBadArgument, UInt8(kSMCReturnDataTypeMismatch)):
            throw SMCError.dataTypeMismatch(key: key())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(
                key: key(),
                kIOReturn: result.kern_res,
                SMCResult: result.smc_res
            )
        }
    }
}
