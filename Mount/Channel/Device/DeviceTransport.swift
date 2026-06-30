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

    /// I/O control command that wakes all threads currently blocked in `read(2)`
    /// on the device file descriptor.
    ///
    /// Equivalent C definition:
    /// ```c
    /// #define FUSEDEVIOCINTERRUPTREADERS _IO('F', 6)
    /// ```
    private static let interruptReadersCommand = UInt(0x20004606)

    /// Creates a `kqueue(2)` user event for interruptible waits.
    ///
    /// The returned event is used both to register the per-wait `EVFILT_USER` event and to trigger
    /// that event with `NOTE_TRIGGER` when ``interrupt()`` is called.
    ///
    /// - Parameters:
    ///   - flags: The event flags, such as `EV_ADD | EV_ENABLE | EV_CLEAR` for registration.
    ///   - fflags: The filter flags, such as `NOTE_TRIGGER` when interrupting waiters.
    /// - Returns: A configured `kevent64_s` user event.
    private static func makeInterruptEvent(flags: UInt16, fflags: UInt32) -> kevent64_s {
        kevent64_s(
            ident: 1,
            filter: Int16(EVFILT_USER),
            flags: flags,
            fflags: fflags,
            data: 0,
            udata: 0,
            ext: (0, 0)
        )
    }

    /// Protects the set of kqueues currently blocked in `waitForNextMessage(until:)`.
    private let lock: os_unfair_lock_t

    /// The kqueue file descriptors currently blocked in `waitForNextMessage(until:)`.
    private var waiters = Set<Int32>()

    /// The borrowed device file descriptor used by the transport.
    let fileDescriptor: FileDescriptor

    /// Creates a device transport.
    ///
    /// - Parameter fileDescriptor: The device file descriptor to use.
    init(fileDescriptor: FileDescriptor) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())

        self.fileDescriptor = fileDescriptor
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
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

    /// Interrupts blocked receive operations.
    func interrupt() throws(Errno) {
        var error: Errno?
        var event = Self.makeInterruptEvent(flags: 0, fflags: UInt32(NOTE_TRIGGER))

        os_unfair_lock_lock(lock)
        for waiter in waiters {
            if kevent64(waiter, &event, 1, nil, 0, 0, nil) == -1 && error == nil {
                error = Errno(rawValue: errno)
            }
        }
        os_unfair_lock_unlock(lock)

        if ioctl(fileDescriptor.rawValue, Self.interruptReadersCommand) == -1 && error == nil {
            error = Errno(rawValue: errno)
        }

        if let error {
            throw error
        }
    }

    /// Waits until the device file descriptor is readable, interrupted, or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: `true` if a message may be available, or `false` if the deadline expires.
    /// - Throws: `Errno.interrupted` if the wait is interrupted, or another `Errno` value returned
    ///   by `poll(2)`, `kqueue(2)` or `kevent(2)`.
    func waitForNextMessage(until deadline: Deadline) throws(Errno) -> Bool {
        if case .immediate = deadline {
            var pollfd = pollfd(fd: fileDescriptor.rawValue, events: Int16(POLLIN), revents: 0)
            let result = poll(&pollfd, 1, 0)
            guard result != -1 else {
                throw Errno(rawValue: errno)
            }
            return result == 1
        }

        let kqueueFileDescriptor = kqueue()
        guard kqueueFileDescriptor != -1 else {
            throw Errno(rawValue: errno)
        }
        defer {
            Darwin.close(kqueueFileDescriptor)
        }

        var interruptEvent = Self.makeInterruptEvent(
            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR),
            fflags: 0
        )
        guard kevent64(kqueueFileDescriptor, &interruptEvent, 1, nil, 0, 0, nil) != -1 else {
            throw Errno(rawValue: errno)
        }

        os_unfair_lock_lock(lock)
        waiters.insert(kqueueFileDescriptor)
        os_unfair_lock_unlock(lock)

        defer {
            os_unfair_lock_lock(lock)
            waiters.remove(kqueueFileDescriptor)
            os_unfair_lock_unlock(lock)
        }

        var readEvent = kevent64_s(
            ident: UInt64(fileDescriptor.rawValue),
            filter: Int16(EVFILT_READ),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: 0,
            data: 0,
            udata: 0,
            ext: (0, 0)
        )
        guard kevent64(kqueueFileDescriptor, &readEvent, 1, nil, 0, 0, nil) != -1 else {
            throw Errno(rawValue: errno)
        }

        var event = kevent64_s()

        let timeout: timespec?
        if case .deadline(let time) = deadline,
           let milliseconds = DispatchTime.now().distance(to: time).milliseconds {
            let m = max(0, milliseconds)
            timeout = timespec(tv_sec: m / 1_000, tv_nsec: (m % 1_000) * 1_000_000)
        } else {
            timeout = nil
        }

        let result = withOptionalUnsafePointer(to: timeout) {
            kevent64(kqueueFileDescriptor, nil, 0, &event, 1, 0, $0)
        }
        guard result != -1 else {
            throw Errno(rawValue: errno)
        }
        guard result != 0 else {
            return false
        }
        guard event.filter != Int16(EVFILT_USER) else {
            throw .interrupted
        }

        return true
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
