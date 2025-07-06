import Foundation

public enum SMCError: Error {
    case driverNotFound
    case failedToOpen
    case keyNotFound(code: String)
    case notPrivileged
    
    /// https://developer.apple.com/library/mac/qa/qa1075/_index.html
    ///
    /// - parameter kIOReturn: I/O Kit error code
    /// - parameter SMCResult: SMC specific return code
    case unknown(kIOReturn: kern_return_t, SMCResult: UInt8)
}
