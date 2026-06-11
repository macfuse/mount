//
//  DeviceTransport.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import Darwin
import OSLog
import System

import MFMount_Private

extension Channel.Flags {
    /// Creates channel flags from file status flags.
    ///
    /// - Parameter fileStatusFlags: The file status flags returned by `fcntl(2)`.
    fileprivate init(fileStatusFlags: Int32) {
        self = []

        if (fileStatusFlags & O_NONBLOCK) == O_NONBLOCK {
            insert(.nonBlocking)
        }
    }

    /// The file status flags represented by this channel flag set.
    fileprivate var fileStatusFlags: Int32 {
        var flags: Int32 = 0

        if contains(.nonBlocking) {
            flags |= O_NONBLOCK
        }

        return flags
    }
}

/// A channel transport backed by a FUSE device file descriptor.
class DeviceTransport: Channel.Transport, Channel.FileDescriptorRepresentable {
    /// The alignment for incoming message body buffer, matching the system page size.
    ///
    /// Page alignment keeps buffers suitable for device I/O and avoids unnecessary misalignment when
    /// the kernel copies complete FUSE messages into user-space memory.
    private static let messageBufferAlignment = Int(getpagesize())

    /// The borrowed device file descriptor used by the transport.
    let fileDescriptor: FileDescriptor

    /// Creates a device transport.
    ///
    /// - Parameter fileDescriptor: The device file descriptor to use.
    init(fileDescriptor: FileDescriptor) {
        self.fileDescriptor = fileDescriptor
    }

    /// Activates the transport.
    func activate() throws(Errno) {
        // Nothing to do here
    }

    /// Deactivates the transport and closes the device file descriptor.
    ///
    /// - Throws: An `Errno` value if the device file descriptor cannot be closed.
    func deactivate() throws(Errno) {
        /*
         * libfuse used to call ioctl(2) on the file descriptor to inform the kernel extension that
         * the file system server is no longer available. Closing the file descriptor should have
         * the same effect.
         */

        do {
            try fileDescriptor.close()
        } catch {
            Logger.mount.error("Failed to close device file descriptor: \(error)")
            throw .badFileDescriptor
        }
    }

    /// Returns the current channel flags from the device file descriptor.
    ///
    /// - Throws: An `Errno` value returned by `fcntl(2)` using `F_GETFL`.
    func getFlags() throws(Errno) -> Channel.Flags {
        let fileStatusFlags = fcntl(fileDescriptor.rawValue, F_GETFL)
        guard fileStatusFlags != -1 else {
            throw Errno(rawValue: errno)
        }

        return .init(fileStatusFlags: fileStatusFlags)
    }

    /// Replaces the current channel flags on the device file descriptor.
    ///
    /// - Parameter flags: The new channel flags.
    /// - Throws: An `Errno` value returned by `fcntl(2)` using `F_GETFL` or `F_SETFL`.
    func setFlags(_ flags: Channel.Flags) throws(Errno) {
        var fileStatusFlags = fcntl(fileDescriptor.rawValue, F_GETFL)
        guard fileStatusFlags != -1 else {
            throw Errno(rawValue: errno)
        }

        fileStatusFlags &= ~Channel.Flags.all.fileStatusFlags
        fileStatusFlags |= flags.fileStatusFlags

        guard fcntl(fileDescriptor.rawValue, F_SETFL, fileStatusFlags) != -1 else {
            throw Errno(rawValue: errno)
        }
    }

    /// Waits until the device file descriptor is readable or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: `true` if a message may be available, or `false` if the deadline expires.
    /// - Throws: An `Errno` value returned by `poll(2)`.
    func waitForNextMessage(until deadline: Deadline) throws(Errno) -> Bool {
        var pollfd = pollfd(fd: fileDescriptor.rawValue, events: Int16(POLLIN), revents: 0)

        let timeout: Int32 = switch deadline {
        case .immediate:
            0
        case .deadline(let time):
            max(0, Int32(DispatchTime.now().distance(to: time).milliseconds ?? 0))
        case .forever:
            -1
        }

        let result = Darwin.poll(&pollfd, 1, timeout)
        guard result != -1 else {
            throw Errno(rawValue: errno)
        }

        return result == 1
    }

    /// Reads the next complete message from the device file descriptor.
    ///
    /// - Returns: The next complete message.
    /// - Throws: An `Errno` value returned by `read(2)`, or
    ///   `Errno.operationNotSupportedByDevice` if the device reaches end-of-file.
    func nextMessage() throws(Errno) -> Message {
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: Parameters.deviceMessageBufferByteCount,
            alignment: Self.messageBufferAlignment
        )

        switch Darwin.read(fileDescriptor.rawValue, buffer.baseAddress, buffer.count) {
        case -1:
            buffer.deallocate()
            throw Errno(rawValue: errno)

        case 0:
            buffer.deallocate()
            throw .operationNotSupportedByDevice

        case let byteCount:
            let messageBuffer = UnsafeMutableRawBufferPointer(rebasing: buffer[0..<byteCount])
            return DeviceMessage(messageBuffer) {
                buffer.deallocate()
            }
        }
    }

    /// Writes one complete message to the device file descriptor.
    ///
    /// - Parameter buffers: The body buffers whose concatenation forms the message body.
    /// - Returns: The number of bytes written.
    /// - Throws: An `Errno` value returned by `writev(2)`.
    func send(message buffers: any Sequence<UnsafeRawBufferPointer>) throws(Errno) -> Int {
        var iovecs = buffers.map {
            iovec(
                iov_base: UnsafeMutableRawPointer(mutating: $0.baseAddress),
                iov_len: $0.count
            )
        }

        let byteCount = writev(fileDescriptor.rawValue, &iovecs, Int32(iovecs.count))
        if byteCount == -1 {
            throw Errno(rawValue: errno)
        }
        return byteCount
    }
}
