import Foundation
import SMC

public enum SMCError: Error {
  case keyNotFound(code: String)
  case notPrivileged
  case dataTypeMismatch

  /// https://developer.apple.com/library/mac/qa/qa1075/_index.html
  ///
  /// - parameter kIOReturn: I/O Kit error code
  /// - parameter SMCResult: SMC specific return code
  case unknown(kIOReturn: kern_return_t, SMCResult: smc_return_t)
}
