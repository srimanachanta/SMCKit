import Foundation
import IOKit


actor SMCConnection {
    private var connection: io_connect_t = 0
    private var isOpen: Bool = false
    
    func open() throws {
        guard !isOpen else { return }
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCError.driverNotFound
        }
        
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            throw SMCError.failedToOpen
        }
        defer {
            IOObjectRelease(service)
        }
        
        isOpen = true
    }
    
    func close() {
        guard isOpen else { return }

        IOServiceClose(connection)
        isOpen = false
    }
    
    func call(_ input: inout SMCParamStruct, selector: SMCParamStruct.Selector = .kSMCHandleYPCEvent) throws -> SMCParamStruct {
        assert(MemoryLayout<SMCParamStruct>.stride == 80)
        
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let inputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(connection,
                                               UInt32(selector.rawValue),
                                               &input,
                                               inputSize,
                                               &output,
                                               &outputSize)
        
        switch (result, output.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCSuccess.rawValue):
            return output
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCKeyNotFound.rawValue):
            throw SMCError.keyNotFound(code: input.key.toString())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(kIOReturn: result, SMCResult: output.result)
        }
    }
}

public enum SMCKit {
    private static let conn = SMCConnection()
    
    public static func keyInformation(_ key: FourCharCode) async throws -> DataType {
        var inputStruct = SMCParamStruct()
        inputStruct.key = key
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue
    
        let outputStruct = try await conn.call(&inputStruct)
        
        return DataType(type: outputStruct.keyInfo.dataType,
                        size: outputStruct.keyInfo.dataSize)
    }
    
    public static func isKeyFound(_ code: FourCharCode) async throws -> Bool {
        do {
            _ = try await keyInformation(code)
        } catch SMCError.keyNotFound { return false }

        return true
    }
    
    public static func numKeys() async throws -> UInt32 {
        let key = SMCKey<UInt32>("#KEY")
        return try await read(key)
    }
    
    // TODO
    //    /// Get all valid SMC keys for this machine
    //    static func allKeys() throws -> [SMCKey] {
    //        let count = try keyCount()
    //        var keys = [SMCKey]()
    //
    //        for i in 0 ..< count {
    //            let key = try keyInformationAtIndex(i)
    //            let info = try keyInformation(key)
    //            keys.append(SMCKey(code: key, info: info))
    //        }
    //
    //        return keys
    //    }
    
    public static func read<V: SMCDecodable>(_ key: SMCKey<V>) async throws -> V {
        try await conn.open()
        
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(key.info.size)
        input.data8 = SMCParamStruct.Selector.kSMCReadKey.rawValue
        
        let out = try await conn.call(&input)

        // SMC always gives you a 32‑byte array; delegate the interpretation:
        return try V(out.bytes)
    }
    
    public static func write<V: SMCEncodable>( _ key: SMCKey<V>, _ value: V) async throws {
        try await conn.open()

        var input = SMCParamStruct()
        input.key = key.code
        try input.bytes = value.encodeSMC()
        input.keyInfo.dataSize = UInt32(key.info.size)
        input.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue

        _ = try await conn.call(&input)
    }
    
    
    public static func close() async {
        await conn.close()
    }
}
