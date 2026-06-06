//
//  MFMessage.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog
import System

extension iovec {
    init(from buffer : UnsafeMutableRawBufferPointer) {
        self.init(iov_base: buffer.baseAddress, iov_len: buffer.count)
    }
}

/// A retained bridge object that owns a received message and its exported `iovec` array.
final class MFMessage: ManagedBuffer<any Message, iovec> {
    /// Creates a bridge message from a received channel message.
    ///
    /// The returned object keeps the source message alive for as long as callers may inspect the
    /// exported body buffers.
    ///
    /// - Parameter message: The received message to wrap.
    /// - Returns: A retained-message storage object.
    static func make(from message: any Message) -> MFMessage {
        let bodyBuffers = message.bodyBuffers

        let buffer = MFMessage.create(
            minimumCapacity: bodyBuffers.count,
            makingHeaderWith: { _ in message }
        ) as! MFMessage

        buffer.withUnsafeMutablePointerToElements { elements in
            for i in 0..<bodyBuffers.count {
                elements.advanced(by: i).initialize(to: iovec(from: bodyBuffers[i]))
            }
        }

        return buffer
    }

    deinit {
        withUnsafeMutablePointerToElements { elements in
            _ = elements.deinitialize(count: header.bodyBuffers.count)
        }
    }

    /// The message body exposed through the C API.
    public var bodyBuffers: UnsafeBufferPointer<iovec> {
        withUnsafeMutablePointerToElements {
            UnsafeBufferPointer(start: $0, count: header.bodyBuffers.count)
        }
    }
}

/// Returns the size of a message body in bytes.
///
/// Returns the size of the serialized FUSE message body in bytes. Reply buffers are not part of the
/// message body and are not included in this size.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `message` is `nil` or does not identify a valid message object. |
///
/// - Parameter message: The message whose body size should be returned. May not be `nil`.
/// - Returns: The message body size in bytes, or `-1` if an error occurs.
@c(MFMessageGetBodySize)
public func MFMessageGetBodySize(_ message: MFMessageRef!) -> ssize_t {
    Bridge.perform { () throws(Errno) in
        guard let message = Bridge.unwrap(reference: message, as: MFMessage.self) else {
            Bridge.log(level: .error, "Invalid argument message")
            throw .invalidArgument
        }
        return message.header.bodyByteCount
    }
}

/// Returns the buffers that make up a message body.
///
/// Each body buffer describes one contiguous byte range of the message body. The first body buffer
/// always contains the structured message data. For FUSE requests this includes the FUSE input
/// header and any fixed-size operation structure, file name, or other structured request fields.
///
/// A message may include a second body buffer. When present, the second body buffer contains the
/// variable-length operation payload. Payload buffers are intended for raw data that can be passed to
/// the request handler without rewriting or skipping structured request fields. For example, a FUSE
/// write request may use the first body buffer for the FUSE header and write request structure, and
/// the second body buffer for the bytes to write.
///
/// The complete message body is formed by concatenating the body buffers in array order. Reply
/// buffers are separate from body buffers and are never returned by this function.
///
/// Messages are never zero-length. On success, this function returns a positive value and stores a
/// non-`nil` pointer in `buffers`.
///
/// The returned buffer array is borrowed from `message` and remains valid only while `message` is
/// retained. The caller must not modify or release the returned array or the memory buffers it
/// references.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `message` is `nil`, `message` does not identify a valid message object, or `buffers` is `nil`. |
///
/// - Parameters:
///   - message: The message whose body buffers should be returned. May not be `nil`.
///   - buffers: On return, points to the first `iovec` value in the borrowed buffer array. May not be
///     `nil`.
/// - Returns: The number of buffers in the message body, or `-1` if an error occurs.
@c(MFMessageGetBodyBuffers)
public func MFMessageGetBodyBuffers(
    _ message: MFMessageRef!,
    _ buffers: UnsafeMutablePointer<UnsafePointer<iovec>?>?
) -> ssize_t {
    Bridge.perform { () throws(Errno) in
        guard let message = Bridge.unwrap(reference: message, as: MFMessage.self) else {
            Bridge.log(level: .error, "Invalid argument message")
            throw .invalidArgument
        }
        guard let buffers else {
            Bridge.log(level: .error, "Invalid argument buffers")
            throw .invalidArgument
        }

        let bodyBuffers = message.bodyBuffers
        buffers.pointee = bodyBuffers.baseAddress
        return bodyBuffers.count
    }
}

/// Returns the optional reply buffer associated with a message.
///
/// The returned buffer is borrowed from `message` and remains valid only while `message` is retained.
/// The caller must not release the memory it references.
///
/// The reply buffer is transport-provided storage for reply payload bytes. It is not part of the
/// serialized message body and is not included in ``MFMessageGetBodySize(_:)-(MFMessageRef?)``.
///
/// If the message does not have a reply buffer, this function returns `0` and stores `nil` in
/// `buffer`.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `message` is `nil`, `message` does not identify a valid message object, or `buffer` is `nil`. |
///
/// - Parameters:
///   - message: The message whose reply buffer should be returned. May not be `nil`.
///   - buffer: On return, points to the borrowed reply buffer, or `nil` if the message does not have
///     a reply buffer. May not be `nil`.
/// - Returns: The size of the reply buffer in bytes, `0` if the message does not have a reply buffer,
///   or `-1` if an error occurs.
@c(MFMessageGetReplyBuffer)
public func MFMessageGetReplyBuffer(
    _ message: MFMessageRef!,
    _ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> ssize_t {
    Bridge.perform { () throws(Errno) in
        guard let message = Bridge.unwrap(reference: message, as: MFMessage.self) else {
            Bridge.log(level: .error, "Invalid argument message")
            throw .invalidArgument
        }
        guard let buffer else {
            Bridge.log(level: .error, "Invalid argument buffer")
            throw .invalidArgument
        }

        if let replyBuffer = message.header.replyBuffer {
            buffer.pointee = replyBuffer.baseAddress
            return replyBuffer.count
        } else {
            buffer.pointee = nil
            return 0
        }
    }
}
