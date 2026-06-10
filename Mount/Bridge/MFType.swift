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
/// - Parameter reference: The object to retain.
/// - Returns: The retained object reference.
@c @implementation
public func MFRetain(_ reference: MFTypeRef) -> MFTypeRef {
    _ = Unmanaged<AnyObject>.fromOpaque(reference).retain()
    return reference
}

/// Releases an MFMount object.
///
/// Releases a reference previously returned by a Create, Copy, or Retain function. After the final
/// release, the object is destroyed.
///
/// - Parameter reference: The object to release.
@c @implementation
public func MFRelease(_ reference: MFTypeRef) {
    Unmanaged<AnyObject>.fromOpaque(reference).release()
}
