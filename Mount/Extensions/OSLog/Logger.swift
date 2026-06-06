//
//  Logger.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog

extension Logger {
    /// The logger used by the mount framework.
    static let mount = Logger(
        subsystem: Variant.identifier,
        category: "mount"
    )
}
