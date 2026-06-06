//
//  DeviceMessage.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Darwin

/// A message whose serialized body was read into a single buffer from a FUSE device file descriptor.
final class DeviceMessage: Message {
    private let buffer: UnsafeMutableRawBufferPointer
    private let deallocator: () -> Void

    /// Creates a device message backed by a message body buffer.
    ///
    /// - Parameters:
    ///   - buffer: The buffer containing the serialized message body.
    ///   - deallocator: The closure that releases the backing storage.
    init(_ buffer: UnsafeMutableRawBufferPointer, deallocator: @escaping () -> Void) {
        self.buffer = buffer
        self.deallocator = deallocator
    }

    deinit {
        deallocator()
    }

    /// The total size of the serialized message body in bytes.
    var bodyByteCount: Int {
        buffer.count
    }

    /// The single buffer that makes up the serialized message body.
    var bodyBuffers: [UnsafeMutableRawBufferPointer] {
        [buffer]
    }

    /// Device-backed messages do not provide a reply buffer.
    var replyBuffer: UnsafeMutableRawBufferPointer? { nil }
}
