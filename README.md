# SMCKit

A modern Swift wrapper around the Apple System Management Controller (SMC) with full async/await support, string literal syntax, and efficient caching.

Updated Swift implementation of the original [SMCKit Project](https://github.com/beltex/SMCKit). Features generic types for reading and writing SMC values, hash map-based caching for improved performance, and a standalone C library for cross-language compatibility.

## Features

- **Concurrency**: Actor-based design with full async/await support
- **Performance**: Hash map-based caching significantly reduces SMC calls
- **Battery Efficient**: Caching minimizes power consumption
- **Thread-Safe**: Actor isolation ensures safe concurrent access
- **Type-Safe**: Generic codable types for all SMC data types

## Requirements

- macOS 10.15+ (for async/await support)
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add SMCKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SMCKit.git", from: "1.0.0")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SMCKit"]
)
```

For C/C++ projects, link against the standalone C library:

```swift
.target(
    name: "YourCTarget",
    dependencies: ["SMC"]
)
```

## Quick Start

### Swift Usage

```swift
import SMCKit

// Read temperature sensor using async/await
Task {
    let temp: Float = try await SMCKit.shared.read("TC0P")
    print("CPU Temperature: \(temp)°C")
}
```

### C Library Usage

```c
#include <smc.h>

io_connect_t conn;
if (SMCOpen(&conn) != kIOReturnSuccess) {
    // Handle error
}

UInt32Char_t key = {{'T', 'C', '0', 'P', '\0'}};
SMCVal_t val;

SMCResult_t result = SMCReadKey(&key, &val, conn);
if (result.kern_res == kIOReturnSuccess && result.smc_res == kSMCReturnSuccess) {
    // Use val.bytes
}

SMCCleanupCache();
SMCClose(conn);
```

## Usage Guide

### String Literal Support

The new `ExpressibleByStringLiteral` conformance allows clean syntax:

```swift
// Before (verbose)
let key = FourCharCode(fromStaticString: "TC0P")
let temp: Float = try await SMCKit.shared.read(key)

// After (clean)
let temp: Float = try await SMCKit.shared.read("TC0P")
```

### Async/Await Support

SMCKit is an `actor`, providing automatic thread-safe concurrent access:

```swift
// Multiple concurrent reads - automatically serialized by the actor
async let cpuTemp: Float = SMCKit.shared.read("TC0P")
async let gpuTemp: Float = SMCKit.shared.read("TG0P")
async let fanSpeed: UInt16 = SMCKit.shared.read("F0Ac")

let (cpu, gpu, fan) = try await (cpuTemp, gpuTemp, fanSpeed)
print("CPU: \(cpu)°C, GPU: \(gpu)°C, Fan: \(fan) RPM")
```

### Reading Values

```swift
// Read different data types
let temp: Float = try await SMCKit.shared.read("TC0P")
let fanSpeed: UInt16 = try await SMCKit.shared.read("F0Ac")
let flag: Bool = try await SMCKit.shared.read("SOME")
```

### Writing Values

```swift
// Write a value to SMC
try await SMCKit.shared.write("SOME", UInt32(42))
```

### Byte Ordering

SMCKit uses **little-endian** byte order for all integer types (`UInt8`, `UInt16`, `UInt32`, `UInt64`, `Int8`, `Int16`, `Int32`, `Int64`). This matches the native byte order used by the vast majority of SMC keys on Apple Silicon Macs.

A small number of keys (e.g. `#KEY`, `RBID`, `RBRV`, `D1BD`, `FOFC`, `MPPR`) store values in big-endian byte order. For these keys, use the `BigEndian` wrapper type:

```swift
// Reading a big-endian key
let count: BigEndian<UInt32> = try await SMCKit.shared.read("#KEY")
print(count.value) // 3209

// Writing a big-endian key
try await SMCKit.shared.write("RBID", BigEndian<UInt32>(4))
```

Alternatively, you can use `readData`/`writeData` for full control over the raw bytes.

### Variable-Length Types (hex_, ch8*)

Some SMC keys use variable-length data types that don't have a fixed size at compile time. SMCKit provides dedicated methods for these:

```swift
// Read raw binary data (hex_ type)
let data: Data = try await SMCKit.shared.readData("SOME")

// Read an ASCII string (ch8* type) - null padding is automatically trimmed
let name: String = try await SMCKit.shared.readString("RPlt")

// Write raw binary data (size must match the key's expected dataSize)
try await SMCKit.shared.writeData("SOME", Data([0x01, 0x02, 0x03, 0x04]))

// Write an ASCII string (automatically null-padded to the key's expected dataSize)
try await SMCKit.shared.writeString("RPlt", "j614s")
```

### Cache Management

```swift
// Clear the internal key info cache to free memory
await SMCKit.shared.clearCache()

// The cache is automatically populated again on next access
let temp: Float = try await SMCKit.shared.read("TC0P")
```

### Querying Keys

```swift
// Check if a key exists
let exists = try await SMCKit.shared.isKeyFound("TC0P")

// Get key information
let info = try await SMCKit.shared.getKeyInformation("TC0P")
print("Type: \(info.type), Size: \(info.size)")

// Get total number of keys
let count = try await SMCKit.shared.numKeys()
print("Total SMC keys: \(count)")

// Get all available keys (can take a few seconds)
let allKeys = try await SMCKit.shared.allKeys()
for key in allKeys {
    print(key.toString())
}
```

## Supported Types

SMCKit supports automatic encoding/decoding for these fixed-size types via the `SMCCodable` protocol (all integer types use little-endian byte order):

- `UInt8`, `UInt16`, `UInt32`, `UInt64`
- `Int8`, `Int16`, `Int32`, `Int64`
- `Float`
- `Bool`
- `BigEndian<T>` — wrapper for the rare SMC keys that use big-endian byte order

Variable-length types are supported through dedicated methods:

- `Data` — raw binary data (`hex_` SMC type) via `readData`/`writeData`
- `String` — ASCII strings (`ch8*` SMC type) via `readString`/`writeString`

## Error Handling

```swift
do {
    let temp: Float = try await SMCKit.shared.read("TC0P")
    print("Temperature: \(temp)")
} catch SMCError.keyNotFound(let key) {
    print("Key not found: \(key)")
} catch SMCError.notPrivileged {
    print("Need elevated privileges")
} catch SMCError.dataTypeMismatch(let key) {
    print("Wrong data type for key: \(key)")
} catch SMCError.connectionFailed(let kIOReturn) {
    print("Failed to connect to SMC: \(kIOReturn)")
} catch SMCError.invalidDataSize(let key, let expected, let actual) {
    print("Size mismatch for \(key): expected \(expected), got \(actual)")
} catch SMCError.invalidStringData(let key) {
    print("Invalid ASCII string data for key: \(key)")
} catch {
    print("Unknown error: \(error)")
}
```

## Architecture

### Swift Layer (SMCKit)
- **Actor-based**: Thread-safe concurrent access via Swift's actor model
- **Type-safe**: Generic `SMCCodable` protocol for compile-time type safety
- **Modern**: Async/await support for clean asynchronous code
- **Ergonomic**: String literal keys for readable code

### C Library (libsmc)
- **Standalone**: Can be used independently in C/C++ projects
- **Cached**: Global hash map cache for key information
- **Thread-safe**: pthread mutex protection for cache operations
- **Efficient**: Minimizes expensive SMC calls through caching

## Performance Notes

- **Caching**: Key information is cached globally, significantly reducing SMC calls
- **Actor Isolation**: Thread-safe access without manual locking overhead
- **Battery Efficient**: Caching mechanism greatly reduces battery usage

## License

MIT License - See LICENSE file for details

## Credits

Based on the original [SMCKit](https://github.com/beltex/SMCKit) by beltex.

Modernized with Swift concurrency, improved caching, and standalone C library support.
