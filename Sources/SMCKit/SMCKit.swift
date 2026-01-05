import Foundation
import IOKit
import SMC

public class SMCKit {
    public static let shared = SMCKit()

    private var connection: io_connect_t = 0

    private init() {
        var conn: io_connect_t = 0
        let result = SMCOpen(&conn)

        // A fatal error is appropriate here, as the library is unusable
        // without a connection to the SMC driver.
        guard result == kIOReturnSuccess else {
            fatalError(
                "SMCKit: Failed to open connection to AppleSMC. Error: \(result)"
            )
        }
        self.connection = conn
    }

    deinit {
        SMCCleanupCache()
        SMCClose(connection)
    }

    public func getKeyInformation(_ key: FourCharCode) throws -> DataType {
        var keyInfo = SMCKeyData_keyInfo_t()
        let result = SMCGetKeyInfo(key, &keyInfo, self.connection)

        switch (result.kern_res, result.smc_res) {
        case (kIOReturnSuccess, UInt8(kSMCReturnSuccess)):
            return DataType(
                type: keyInfo.dataType,
                size: UInt32(keyInfo.dataSize)
            )
        case (kIOReturnSuccess, UInt8(kSMCReturnKeyNotFound)):
            throw SMCError.keyNotFound(code: key.toString())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(
                kIOReturn: result.kern_res,
                SMCResult: result.smc_res
            )
        }
    }

    public func isKeyFound(_ key: FourCharCode) throws -> Bool {
        do {
            let _ = try getKeyInformation(key)
            return true
        } catch SMCError.keyNotFound {
            return false
        } catch let error {
            throw error
        }
    }

    public func read<V: SMCCodable>(_ key: FourCharCode) throws -> V {
        var keyCharArray = key.toCharArray()
        var smcVal = SMCVal_t()

        let result = SMCReadKey(&keyCharArray, &smcVal, self.connection)

        switch (result.kern_res, result.smc_res) {
        case (kIOReturnSuccess, UInt8(kSMCReturnSuccess)):
            return try V(smcVal.bytes)
        case (kIOReturnSuccess, UInt8(kSMCReturnKeyNotFound)):
            throw SMCError.keyNotFound(code: key.toString())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(
                kIOReturn: result.kern_res,
                SMCResult: result.smc_res
            )
        }
    }

    public func write<V: SMCCodable>(_ key: FourCharCode, _ value: V) throws {
        let buf = SMCVal_t(
            key: key.toCharArray(),
            dataSize: V.smcDataType.size,
            dataType: V.smcDataType.type.toCharArray(),
            bytes: try value.encode()
        )

        let result = SMCWriteKey(buf, self.connection)

        switch (result.kern_res, result.smc_res) {
        case (kIOReturnSuccess, UInt8(kSMCReturnSuccess)):
            break
        case (kIOReturnSuccess, UInt8(kSMCReturnKeyNotFound)):
            throw SMCError.keyNotFound(code: key.toString())
        case (kIOReturnBadArgument, UInt8(kSMCReturnDataTypeMismatch)):
            throw SMCError.dataTypeMismatch
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(
                kIOReturn: result.kern_res,
                SMCResult: result.smc_res
            )
        }
    }

    public func numKeys() throws -> UInt32 {
        return try self.read(FourCharCode(fromStaticString: "#KEY"))
    }

    public func allKeys() throws -> [FourCharCode] {
        let numKeys = try self.numKeys()

        let keys = try (0..<numKeys).compactMap { index in
            var keyBuffer: UInt32Char_t = (0, 0, 0, 0, 0)

            let result = SMCGetKeyFromIndex(index, &keyBuffer, self.connection)

            switch (result.kern_res, result.smc_res) {
            case (kIOReturnSuccess, UInt8(kSMCReturnSuccess)):
                return FourCharCode(fromCharArray: keyBuffer)
            case (kIOReturnSuccess, UInt8(kSMCReturnKeyNotFound)):
                throw SMCError.keyNotFound(code: "Index \(index)")
            case (kIOReturnBadArgument, UInt8(kSMCReturnDataTypeMismatch)):
                throw SMCError.dataTypeMismatch
            case (kIOReturnNotPrivileged, _):
                throw SMCError.notPrivileged
            default:
                throw SMCError.unknown(
                    kIOReturn: result.kern_res,
                    SMCResult: result.smc_res
                )
            }
        }

        return keys
    }
}
