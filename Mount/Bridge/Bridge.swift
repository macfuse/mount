//
//  Bridge.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog
import System

/// Shared helpers for exported C bridge functions.
enum Bridge {
    /// A return type that can provide the C API's failure sentinel value.
    protocol PerformReturnValue {
        /// The value returned when a bridged operation throws an `Errno`.
        static var defaultErrorValue: Self { get }
    }

    /// Runs a throwing bridge operation and converts `Errno` failures into C API failures.
    ///
    /// If `operation` throws, this method stores the thrown error in `errno` and returns
    /// `errorValue`. If `operation` succeeds, this method clears `errno` and returns the operation
    /// result.
    ///
    /// - Parameters:
    ///   - errorValue: The value to return when the operation fails.
    ///   - operation: The operation to run.
    /// - Returns: The operation result, or `errorValue` after a failure.
    static func perform<T>(
        returningOnError errorValue: T = T.defaultErrorValue,
        _ operation: () throws(Errno) -> T
    ) -> T where T: PerformReturnValue {
        do throws(Errno) {
            let result = try operation()
            errno = 0
            return result
        } catch {
            errno = error.rawValue
            return errorValue
        }
    }

    /// Converts an opaque MFMount reference into a Swift object.
    ///
    /// - Parameters:
    ///   - reference: The opaque reference to unwrap.
    ///   - as: The expected Swift object type.
    /// - Returns: The referenced object, or `nil` if the reference is `nil` or has the wrong type.
    static func unwrap<T>(
        reference: MFTypeRef?,
        as: T.Type = T.self,
    ) -> T? {
        guard let reference,
              let object = Unmanaged<AnyObject>.fromOpaque(reference).takeUnretainedValue() as? T else {
            return nil
        }
        return object
    }

    /// Logs a bridge diagnostic to unified logging and standard error.
    ///
    /// - Parameters:
    ///   - level: The unified logging level.
    ///   - function: The bridge function that produced the diagnostic.
    ///   - message: The diagnostic message.
    static func log(
        level: OSLogType = .default,
        function: StaticString = #function,
        _ message: String
    ) {
        Logger.mount.log(level: level, "\(message)")

        let data = Data("MFMount: \(function): \(message)\n".utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

/// Uses `false` as the C API failure sentinel for Boolean results.
extension Bool: Bridge.PerformReturnValue {
    static var defaultErrorValue: Bool { false }
}

/// Uses `-1` as the C API failure sentinel for 32-bit integer results.
extension Int32: Bridge.PerformReturnValue {
    static var defaultErrorValue: Int32 { -1 }
}

/// Uses `-1` as the C API failure sentinel for integer results.
extension Int: Bridge.PerformReturnValue {
    static var defaultErrorValue: Int { -1 }
}

/// Uses `nil` as the C API failure sentinel for optional results.
extension Optional: Bridge.PerformReturnValue {
    static var defaultErrorValue: Optional<Wrapped> { nil }
}
