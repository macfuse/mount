//
//  DispatchTimeInterval.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Dispatch

extension DispatchTimeInterval {
    /// The interval represented as whole milliseconds.
    ///
    /// Values with finer precision are rounded down. Returns `nil` for `.never` and for unknown
    /// future interval cases.
    var milliseconds: Int? {
        switch self {
        case .seconds(let seconds):
            return seconds * 1_000
        case .milliseconds(let milliseconds):
            return milliseconds
        case .microseconds(let microseconds):
            return microseconds / 1_000
        case .nanoseconds(let nanoseconds):
            return nanoseconds / 1_000_000
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }
}
