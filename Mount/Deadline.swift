//
//  Deadline.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

/// A deadline that bounds how long an operation may wait.
///
/// Use this type for APIs that support polling, bounded waits, and unbounded waits through a
/// single value.
public enum Deadline {
    /// A deadline that expires immediately.
    case immediate

    /// A deadline that expires at a specific dispatch time.
    case deadline(DispatchTime)

    /// A deadline that never expires.
    case forever

    /// Creates a deadline relative to the current time.
    ///
    /// - Parameter interval: The amount of time to wait from now.
    /// - Returns: A ``Deadline/deadline(_:)`` value for the calculated dispatch time.
    static func after(_ interval: DispatchTimeInterval) -> Self {
        .deadline(.now() + interval)
    }
}
