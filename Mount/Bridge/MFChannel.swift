//
//  MFChannel.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import OSLog
import System

extension Channel {
    /// Sends a message described by C `iovec` values.
    ///
    /// - Parameter iovecs: The body buffers to send.
    /// - Returns: The number of bytes sent.
    func send(message iovecs: any Sequence<iovec>) throws(Errno) -> Int {
        let buffers = iovecs.map { UnsafeRawBufferPointer(start: $0.iov_base, count: $0.iov_len) }
        return try send(message: buffers)
    }
}

/// Creates a new channel.
///
/// A channel created by this function is not associated with a transport until `MFMount()`
/// succeeds. Channel operations that require a transport may block until the association is complete
/// or the channel is closed.
///
/// The caller owns the returned channel and must release it with ``MFRelease(_:)-(MFTypeRef?)``.
/// Use ``MFChannelClose(_:)-(MFChannelRef?)`` to close the channel when unmounting the volume.
///
/// This function has no defined `errno` failure values.
///
/// - Returns: A newly created channel, or `nil` if the channel could not be created.
@c(MFChannelCreate)
public func MFChannelCreate() -> MFChannelRef? {
    let channel = Channel()
    return Unmanaged.passRetained(channel).toOpaque()
}

/// Creates a channel using an existing device file descriptor.
///
/// Ownership of `fileDescriptor` is transferred to the channel. The descriptor is closed when the
/// channel is closed. Destroying the channel without closing it can result in undefined behavior.
///
/// On failure, this function returns `nil` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `fileDescriptor` is invalid. |
///
/// If this function fails, ownership of `fileDescriptor` remains with the caller.
///
/// - Parameter fileDescriptor: The device file descriptor to use.
/// - Returns: A newly created channel, or `nil` if the channel could not be created.
@c(MFChannelCreateWithDeviceFileDescriptor)
public func MFChannelCreateWithDeviceFileDescriptor(_ fileDescriptor: CInt) -> MFChannelRef? {
    Bridge.perform { () throws(Errno) in
        let fileDescriptor = FileDescriptor(rawValue: fileDescriptor)
        guard fileDescriptor.rawValue >= 0 else {
            Bridge.log(level: .error, "Invalid argument fileDescriptor")
            throw .invalidArgument
        }

        let transport = DeviceTransport(fileDescriptor: fileDescriptor)

        let channel = Channel()
        try channel.open(with: transport)
        return Unmanaged.passRetained(channel).toOpaque()
    }
}

/// Returns the file descriptor associated with a channel.
///
/// The returned file descriptor is borrowed. The caller must not close it.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil` or does not identify a valid channel object. |
/// | `ENOTSUP` | `channel` is not backed by a device file descriptor. |
///
/// - Parameter channel: The channel whose file descriptor should be returned. May not be `nil`.
/// - Returns: The channel's file descriptor, or `-1` if the channel has no associated file
///   descriptor or an error occurs.
@c(MFChannelGetFileDescriptor)
public func MFChannelGetFileDescriptor(_ channel: MFChannelRef?) -> CInt {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        return try channel.fileDescriptor.rawValue
    }
}

extension MFChannelFlags {
    /// Creates C channel flags from Swift channel flags.
    init(from flags: Channel.Flags) {
        self.init(rawValue: flags.rawValue)
    }
}

extension Channel.Flags {
    /// Creates Swift channel flags from C channel flags.
    init(from flags: MFChannelFlags) throws(Errno) {
        let unsupported = flags.rawValue & ~Channel.Flags.all.rawValue
        guard unsupported == 0 else {
            throw .invalidArgument
        }

        self.init(rawValue: flags.rawValue)
    }
}

/// Returns the current channel flags.
///
/// On failure, this function returns `false` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil`, `channel` does not identify a valid channel object, or `flags` is `nil`. |
/// | `ENODEV` | `channel` is closed. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `fcntl(2)` using `F_GETFL`.
///
/// The value stored in `flags` is undefined on failure.
///
/// - Parameters:
///   - channel: The channel whose flags should be returned. May not be `nil`.
///   - flags: On return, contains the current channel flags. May not be `nil`.
/// - Returns: `true` if the flags were returned successfully; otherwise `false`.
@c(MFChannelGetFlags)
public func MFChannelGetFlags(
    _ channel: MFChannelRef?,
    _ flags: UnsafeMutablePointer<MFChannelFlags>?
) -> Bool {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }
        guard let flags else {
            Bridge.log(level: .error, "Invalid argument flags")
            throw .invalidArgument
        }

        flags.pointee = MFChannelFlags(from: try channel.getFlags())
        return true
    }
}

/// Sets the channel flags.
///
/// This function replaces the channel's current flags with `flags`.
///
/// To enable non-blocking receive mode, include `MFChannelFlagNonBlocking`.
///
/// On failure, this function returns `false` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil`, `channel` does not identify a valid channel object, or `flags` contains unsupported flag bits. |
/// | `ENODEV` | `channel` is closed. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `fcntl(2)` using `F_GETFL` or `F_SETFL`.
///
/// - Parameters:
///   - channel: The channel whose flags should be changed. May not be `nil`.
///   - flags: A bit mask composed of `MFChannelFlag` values.
/// - Returns: `true` if the flags were set successfully; otherwise `false`.
@c(MFChannelSetFlags)
public func MFChannelSetFlags(_ channel: MFChannelRef?, _ flags: MFChannelFlags) -> Bool {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        try channel.setFlags(try Channel.Flags(from: flags))
        return true
    }
}

/// Waits until the next complete message is available.
///
/// After this function reports success, the caller can call
/// ``MFChannelCopyNextMessage(_:)-(MFChannelRef?)`` to retrieve the next complete message. Message
/// availability may change before that call, especially when the same channel is used from multiple
/// threads.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil` or does not identify a valid channel object. |
/// | `EINTR` | The wait was interrupted. |
/// | `ENODEV` | `channel` is closed. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `poll(2)`.
///
/// - Parameters:
///   - channel: The channel to wait on. May not be `nil`.
///   - timeout: The timeout value, in milliseconds. Pass `0` to poll without blocking. Pass a
///     negative value to wait indefinitely.
/// - Returns: A positive value if a complete message is available, `0` if the operation timed out,
///   or `-1` if an error occurs.
@c(MFChannelWaitForNextMessage)
public func MFChannelWaitForNextMessage(_ channel: MFChannelRef?, _ timeout: Int32) -> Int32 {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        let deadline: Deadline = if timeout == 0 {
            .immediate
        } else if timeout < 0 {
            .forever
        } else {
            .after(.milliseconds(Int(timeout)))
        }

        do throws(Errno) {
            return try channel.waitForNextMessage(until: deadline) ? 1 : 0
        } catch {
            Bridge.log(level: .error, "Failed to wait on channel: \(error)")
            throw error
        }
    }
}

/// Copies the next complete message from a channel.
///
/// On success, this function returns a retained message reference. The caller owns the returned
/// message and must release it with ``MFRelease(_:)-(MFTypeRef?)``.
///
/// If no complete message is available, the behavior depends on the channel's blocking mode.
/// In blocking mode, this function waits until a message is available or the channel is interrupted
/// or closed. In non-blocking mode, this function returns `nil` and sets `errno` to `EAGAIN`.
///
/// On failure, this function returns `nil` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EAGAIN` | The channel is in non-blocking mode and no complete message is available. |
/// | `EINVAL` | `channel` is `nil` or does not identify a valid channel object. |
/// | `EINTR` | The receive operation was interrupted. |
/// | `ENODEV` | `channel` is closed. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `read(2)`.
///
/// - Parameter channel: The channel from which to receive the next FUSE message. May not be `nil`.
/// - Returns: A retained message reference, or `nil` if an error occurs.
@c(MFChannelCopyNextMessage)
public func MFChannelCopyNextMessage(_ channel: MFChannelRef?) -> MFMessageRef? {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        do throws(Errno) {
            let message = try channel.nextMessage()

            let box = MFMessage.make(from: message)
            return Unmanaged.passRetained(box).toOpaque()
        } catch {
            if error != .operationNotSupportedByDevice {
                Bridge.log(level: .error, "Failed to receive message: \(error)")
            }
            throw error
        }
    }
}

/// Sends a FUSE message body on a channel.
///
/// The array referenced by `buffers` describes the body buffers that make up the serialized message
/// body. The channel preserves the message boundary when sending. The array and the memory it
/// references are not retained by this function and need only remain valid for the duration of the
/// call.
///
/// On failure, this function returns `-1` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil`, `channel` does not identify a valid channel object, `buffers` is `nil`, or `count` is `0`. |
/// | `ENODEV` | `channel` is closed. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `writev(2)`.
///
/// - Parameters:
///   - channel: The channel on which to send the message. May not be `nil`.
///   - buffers: An array of `iovec` values describing the body buffers. May not be `nil`.
///   - count: The number of buffers. Must be greater than `0`.
/// - Returns: The number of bytes sent, or `-1` if an error occurs.
@c(MFChannelSendMessage)
public func MFChannelSendMessage(
    _ channel: MFChannelRef?,
    _ buffers: UnsafePointer<iovec>?,
    _ count: size_t
) -> ssize_t {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }
        guard let buffers else {
            Bridge.log(level: .error, "Invalid argument buffers")
            throw .invalidArgument
        }
        guard count > 0 else {
            Bridge.log(level: .error, "Invalid argument count")
            throw .invalidArgument
        }

        do throws(Errno) {
            let parts = UnsafeBufferPointer<iovec>(start: buffers, count: Int(count))
            return try channel.send(message: parts)
        } catch {
            Bridge.log(level: .error, "Failed to send message: \(error)")
            throw error
        }
    }
}

/// Closes a channel.
///
/// Closing a channel prevents further message transmission. Calling this function on an already
/// closed channel should be treated as a programming error.
///
/// On failure, this function returns `false` and sets `errno` as follows:
///
/// | Value | Description |
/// | --- | --- |
/// | `EINVAL` | `channel` is `nil` or does not identify a valid channel object. |
///
/// For a device-backed channel, this function may also fail with an `errno` value returned by
/// `close(2)`.
///
/// - Parameter channel: The channel to close. May not be `nil`.
/// - Returns: `true` if the channel was closed successfully; otherwise `false`.
@c(MFChannelClose)
public func MFChannelClose(_ channel: MFChannelRef?) -> Bool {
    Bridge.perform { () throws(Errno) in
        guard let channel = Bridge.unwrap(reference: channel, as: Channel.self) else {
            Bridge.log(level: .error, "Invalid argument channel")
            throw .invalidArgument
        }

        do throws(Errno) {
            try channel.close()
            return true
        } catch {
            Bridge.log(level: .error, "Failed to close channel: \(error)")
            throw error
        }
    }
}
