//
//  XPCMessage.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog
import System
import XPC

import MFMount_Private

/// Tracks shared-memory mappings created while decoding an XPC message.
///
/// `MemoryMappings` owns the address ranges returned by `xpc_shmem_map` and releases them with
/// `munmap` when ``unmap()`` is called. The value is noncopyable so ownership of mapped memory
/// cannot be duplicated accidentally.
struct MemoryMappings: ~Copyable {
    /// The mapped address ranges to release.
    ///
    /// Each buffer records the full byte count returned by `xpc_shmem_map`, which may be larger
    /// than the byte count advertised by the XPC message.
    private var buffers: [UnsafeMutableRawBufferPointer]

    /// Creates an empty mapping store.
    ///
    /// - Parameter capacity: The number of mappings to reserve storage for.
    init(capacity: Int) {
        buffers = [UnsafeMutableRawBufferPointer]()
        buffers.reserveCapacity(capacity)
    }

    /// Maps a shared-memory buffer described by an XPC array.
    ///
    /// The array must contain an `XPC_TYPE_SHMEM` object at index `0` and an `XPC_TYPE_INT64` byte
    /// count at index `1`. On success, this method records the full mapped range and returns a
    /// buffer limited to the advertised byte count.
    ///
    /// The returned buffer is borrowed from this mapping store. The caller must not deallocate it.
    ///
    /// - Parameter array: The XPC array that describes the shared-memory buffer.
    /// - Returns: A buffer covering the advertised bytes, or `nil` if the descriptor is malformed or
    ///   the shared memory cannot be mapped.
    @inline(always)
    mutating func map(_ array: xpc_object_t) -> UnsafeMutableRawBufferPointer? {
        let sharedMemoryValue = xpc_array_get_value(array, 0)
        let byteCountValue = xpc_array_get_value(array, 1)

        guard xpc_get_type(sharedMemoryValue) == XPC_TYPE_SHMEM,
              xpc_get_type(byteCountValue) == XPC_TYPE_INT64 else {
            return nil
        }

        let rawByteCount = xpc_int64_get_value(byteCountValue)
        guard rawByteCount > 0, rawByteCount <= Int64(Int.max) else {
            return nil
        }

        let byteCount = Int(rawByteCount)
        var pointer: UnsafeMutableRawPointer? = nil
        let mappedByteCount = xpc_shmem_map(sharedMemoryValue, &pointer)

        guard mappedByteCount > 0, let pointer else {
            return nil
        }
        guard mappedByteCount >= byteCount else {
            munmap(pointer, mappedByteCount)
            return nil
        }

        buffers.append(UnsafeMutableRawBufferPointer(
            start: pointer,
            count: mappedByteCount
        ))
        return UnsafeMutableRawBufferPointer(start: pointer, count: byteCount)
    }

    /// Unmaps all recorded shared-memory ranges.
    ///
    /// After this method returns, previously returned buffers are no longer valid. Calling this
    /// method more than once is safe.
    mutating func unmap() {
        for buffer in buffers {
            munmap(buffer.baseAddress, buffer.count)
        }

        buffers.removeAll(keepingCapacity: false)
    }
}

/// A message decoded from an XPC dictionary received from the file system extension.
final class XPCMessage: Message {
    private let object: xpc_object_t
    private var mappings: MemoryMappings

    /// The total size of the serialized message body in bytes.
    let bodyByteCount: Int

    /// Buffers whose concatenation forms the serialized message body.
    let bodyBuffers: [UnsafeMutableRawBufferPointer]

    /// Optional transport-provided shared-memory buffer for writing reply payload bytes.
    let replyBuffer: UnsafeMutableRawBufferPointer?

    /// Creates a message from an XPC dictionary.
    ///
    /// The dictionary's `body` entry contains the serialized message body as inline data objects or
    /// shared-memory objects. If present, the `reply` entry contains the transport-provided reply
    /// buffer. Shared memory is mapped for the lifetime of the message.
    ///
    /// - Parameter object: The XPC dictionary containing the message body and optional reply buffer.
    /// - Throws: `Errno.ioError` if the dictionary does not contain a valid message.
    init(_ object: xpc_object_t) throws(Errno) {
        guard let body = xpc_dictionary_get_value(object, "body"),
              xpc_get_type(body) == XPC_TYPE_ARRAY else {
            Logger.mount.error("Message body is missing")
            throw .ioError
        }

        let bodyCount = xpc_array_get_count(body)
        guard bodyCount > 0 else {
            Logger.mount.error("Message body is empty")
            throw .ioError
        }

        var mappings = MemoryMappings(capacity: 2)
        var bodyByteCount = 0

        var bodyBuffers = [UnsafeMutableRawBufferPointer]()
        bodyBuffers.reserveCapacity(bodyCount)

        var replyBuffer: UnsafeMutableRawBufferPointer? = nil

        do throws(Errno) {
            for i in 0..<bodyCount {
                let value = xpc_array_get_value(body, i)

                switch xpc_get_type(value) {
                case XPC_TYPE_DATA:
                    let pointer = xpc_data_get_bytes_ptr(value)
                    let byteCount = xpc_data_get_length(value)

                    guard let pointer, byteCount > 0 else {
                        Logger.mount.error("Message body buffer is empty")
                        throw .ioError
                    }

                    bodyBuffers.append(UnsafeMutableRawBufferPointer(
                        start: UnsafeMutableRawPointer(mutating: pointer),
                        count: byteCount
                    ))
                    bodyByteCount += byteCount

                case XPC_TYPE_ARRAY:
                    guard let buffer = mappings.map(value) else {
                        Logger.mount.error("Failed to map message body buffer")
                        throw .ioError
                    }
                    bodyBuffers.append(buffer)
                    bodyByteCount += buffer.count

                default:
                    Logger.mount.error("Unexpected message body buffer type")
                    throw .ioError
                }
            }

            guard bodyBuffers[0].count >= MemoryLayout<fuse_in_header>.size else {
                Logger.mount.error("First message body buffer is too small for header")
                throw .ioError
            }

            if let reply = xpc_dictionary_get_value(object, "reply") {
                guard xpc_get_type(reply) == XPC_TYPE_ARRAY,
                      let buffer = mappings.map(reply) else {
                    Logger.mount.error("Failed to map message reply buffer")
                    throw .ioError
                }
                replyBuffer = buffer
            }
        } catch {
            mappings.unmap()
            throw error
        }

        self.object = object
        self.mappings = mappings

        self.bodyByteCount = bodyByteCount
        self.bodyBuffers = bodyBuffers
        self.replyBuffer = replyBuffer
    }

    deinit {
        mappings.unmap()
    }
}
