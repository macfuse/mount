//
//  Date.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Foundation

extension Date {
    /// Creates a date that corresponds to a dispatch time.
    ///
    /// - Parameter dispatchTime: The dispatch time to convert.
    init(dispatchTime: DispatchTime) {
        if dispatchTime == DispatchTime.distantFuture {
            self = Date.distantFuture
            return
        }

        let now = DispatchTime.now()

        let deltaNanoseconds =
            Int64(clamping: dispatchTime.uptimeNanoseconds) -
            Int64(clamping: now.uptimeNanoseconds)

        let deltaSeconds = TimeInterval(deltaNanoseconds) / 1_000_000_000
        self = Date(timeIntervalSinceNow: deltaSeconds)
    }
}
