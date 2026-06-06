//
//  MFType.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog

/// Retains an MFMount object.
///
/// The returned reference must be balanced with a corresponding call to
/// ``MFRelease(_:)-(MFTypeRef?)``.
///
/// Passing `nil` is a programming error and causes a runtime trap, matching the non-null contract
/// in `MFMount.h`.
///
/// - Parameter reference: The object to retain.
/// - Returns: The retained object reference.
@c(MFRetain)
public func MFRetain(_ reference: MFTypeRef?) -> MFTypeRef? {
    guard let reference else {
        Bridge.log(level: .error, "Invalid argument reference")
        fatalError()
    }

    _ = Unmanaged<AnyObject>.fromOpaque(reference).retain()
    return reference
}

/// Releases an MFMount object.
///
/// Releases a reference previously returned by a Create, Copy, or Retain function. After the final
/// release, the object is destroyed.
///
/// Passing `nil` is a programming error and causes a runtime trap, matching the non-null contract
/// in `MFMount.h`.
///
/// - Parameter reference: The object to release.
@c(MFRelease)
public func MFRelease(_ reference: MFTypeRef?) {
    guard let reference else {
        Bridge.log(level: .error, "Invalid argument reference")
        fatalError()
    }

    Unmanaged<AnyObject>.fromOpaque(reference).release()
}
