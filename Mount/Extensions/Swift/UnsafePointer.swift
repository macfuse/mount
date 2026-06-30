//
//  UnsafePointer.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

func withOptionalUnsafePointer<T, R>(
    to value: T?,
    _ body: (UnsafePointer<T>?) throws -> R
) rethrows -> R {
    if let value {
        return try withUnsafePointer(to: value) { pointer in
            try body(pointer)
        }
    } else {
        return try body(nil)
    }
}
