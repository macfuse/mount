//
//  Message.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import System
import XPC

import MFMount_Private

/// A complete FUSE message received from a channel.
public protocol Message: AnyObject {
    /// The total size of the serialized message body in bytes.
    var bodyByteCount: Int { get }

    /// Buffers whose concatenation forms the serialized message body.
    ///
    /// The first buffer contains the structured message data. Additional buffers, if present,
    /// contain variable-length operation payload data.
    var bodyBuffers: [UnsafeMutableRawBufferPointer] { get }

    /// Optional transport-provided buffer for writing reply payload bytes.
    ///
    /// This buffer is not part of the serialized message body and is not included in
    /// ``bodyByteCount``.
    var replyBuffer: UnsafeMutableRawBufferPointer? { get }
}

extension Message {
    /// The FUSE input header at the beginning of the message.
    ///
    /// - Throws: `Errno.ioError` if the message body is too short to contain a FUSE input header.
    public var header: UnsafePointer<fuse_in_header> {
        get throws(Errno) {
            guard let buffer = bodyBuffers.first,
                  buffer.count >= MemoryLayout<fuse_in_header>.size else {
                throw .ioError
            }

            return UnsafePointer(buffer.baseAddress!.assumingMemoryBound(to: fuse_in_header.self))
        }
    }
}
