//
//  Channel.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

import System

/// A message-oriented communication endpoint for an active mount.
///
/// A channel starts unopened. Mounting a volume or esolves the channel's  transport; closing the
/// channel resolves it to `nil`.
final class Channel: @unchecked Sendable {
    /// Flags that control channel behavior.
    struct Flags: OptionSet {
        /// Enables non-blocking receive mode.
        static let nonBlocking = Flags(rawValue: 1 << 0)

        /// All supported channel flags.
        static let all: Flags = [.nonBlocking]

        /// The raw flag bit mask.
        let rawValue: UInt32
    }

    /// A concrete transport that carries channel messages.
    protocol Transport {
        /// Activates the transport.
        ///
        /// - Throws: An `Errno` value if activation fails.
        func activate() throws(Errno)

        /// Deactivates the transport.
        ///
        /// - Throws: An `Errno` value if deactivation fails.
        func deactivate() throws(Errno)

        /// Returns the current transport flags.
        ///
        /// - Throws: An `Errno` value if the flags cannot be returned.
        func getFlags() throws(Errno) -> Flags

        /// Replaces the current transport flags.
        ///
        /// - Parameter flags: The new channel flags.
        /// - Throws: An `Errno` value if the flags cannot be set.
        func setFlags(_ flags: Flags) throws(Errno)

        /// Interrupts receive-side operations blocked on the transport.
        ///
        /// An interrupted wait or receive operation should fail with `Errno.interrupted`.
        /// If no receive operation is blocked, the interrupt may have no observable effect.
        ///
        /// - Throws: `Errno.notSupported` if the transport cannot be explicitly interrupted, or
        ///   another transport-defined `Errno` value if the interrupt cannot be delivered.
        func interrupt() throws(Errno)

        /// Waits until the next complete message is available or the deadline expires.
        ///
        /// - Parameter deadline: The deadline that bounds how long the call may wait.
        /// - Returns: `true` if a complete message is available, or `false` if the deadline expires.
        /// - Throws: An `Errno` value if the wait fails.
        func waitForNextMessage(until: Deadline) throws(Errno) -> Bool

        /// Receives the next complete message.
        ///
        /// - Returns: The next complete message.
        /// - Throws: An `Errno` value if no message can be received.
        func nextMessage() throws(Errno) -> Message

        /// Sends one complete message.
        ///
        /// - Parameter message: The body buffers whose concatenation forms the message body.
        /// - Returns: The number of bytes sent.
        /// - Throws: An `Errno` value if the message cannot be sent.
        func send(message: any Sequence<UnsafeRawBufferPointer>) throws(Errno) -> Int
    }

    /// A transport backed by a file descriptor.
    protocol FileDescriptorRepresentable {
        /// The borrowed file descriptor associated with the transport.
        var fileDescriptor: FileDescriptor { get }
    }

    /// POSIX signals that should wake blocked receive operations
    private static let interruptSignals = [SIGHUP, SIGINT, SIGPIPE, SIGTERM]

    private let signalSources: [DispatchSourceSignal]

    @BlockingLazy private var transport: (any Transport)?

    /// Creates an unopened channel.
    init() {
        signalSources = Self.interruptSignals.map {
            DispatchSource.makeSignalSource(signal: $0)
        }
    }

    /// Resumes all signal sources used to interrupt blocked receive operations.
    private func resumeSignalSources() {
        for signalSource in signalSources {
            signalSource.setEventHandler { [weak self] in
                try? self?.interrupt()
            }
            signalSource.resume()
        }
    }

    /// Stops all signal sources used to interrupt blocked receive operations.
    private func cancelSignalSources() {
        for signalSource in signalSources {
            signalSource.cancel()
        }
    }

    /// Opens the channel with a transport.
    ///
    /// Only the first call associates a transport with the channel. Later calls leave the existing
    /// transport unchanged.
    ///
    /// - Parameter transport: The transport to associate with the channel.
    /// - Throws: An `Errno` value if activating the transport fails.
    func open(with transport: Transport) throws(Errno) {
        if $transport.resolve(transport) {
            try transport.activate()
            resumeSignalSources()
        }
    }

    /// Closes the channel.
    ///
    /// Closing an unopened channel resolves the channel to a closed state. Closing an active channel
    /// deactivates its transport.
    ///
    /// - Throws: An `Errno` value if deactivating the transport fails.
    func close() throws(Errno) {
        cancelSignalSources()

        $transport.resolve(nil)
        try $transport.value??.deactivate()
    }

    /// The borrowed file descriptor associated with the channel.
    ///
    /// - Throws: `Errno.notSupported` if the channel is not backed by a device file descriptor.
    var fileDescriptor: FileDescriptor {
        get throws(Errno) {
            guard let transport = $transport.wait() else {
                throw .notSupported
            }

            if let transport = transport as? FileDescriptorRepresentable {
                return transport.fileDescriptor
            } else {
                throw .notSupported
            }
        }
    }

    /// Returns the current channel flags.
    ///
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed, or another
    ///   transport-defined `Errno` value if the flags cannot be returned.
    func getFlags() throws(Errno) -> Flags {
        guard let transport = $transport.wait() else {
            throw .operationNotSupportedByDevice
        }
        return try transport.getFlags()
    }

    /// Replaces the current channel flags.
    ///
    /// - Parameter flags: The new channel flags.
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed, or another
    ///   transport-defined `Errno` value if the flags cannot be set.
    func setFlags(_ flags: Flags) throws(Errno) {
        guard let transport = $transport.wait() else {
            throw .operationNotSupportedByDevice
        }
        try transport.setFlags(flags)
    }

    /// Interrupts receive-side operations blocked on the channel.
    ///
    /// Blocked calls to ``waitForNextMessage(until:)`` or ``nextMessage()`` that observe the
    /// interrupt fail with `Errno.interrupted`. If no operation is blocked, the interrupt may have
    /// no observable effect.
    ///
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed,
    ///   `Errno.notSupported` if the active transport cannot be explicitly interrupted, or another
    ///   transport-defined `Errno` value if the interrupt cannot be delivered.
    func interrupt() throws(Errno) {
        $transport.interrupt()

        guard case .some(let transport) = $transport.value else {
            return
        }
        guard let transport else {
            throw .operationNotSupportedByDevice
        }
        try transport.interrupt()
    }

    /// Waits until the next complete message is available or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: `true` if a complete message is available, or `false` if the deadline expires.
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed, or another
    ///   transport-defined `Errno` value if the wait fails.
    func waitForNextMessage(until deadline: Deadline = .immediate) throws(Errno) -> Bool {
        let transport = try $transport.wait(until: deadline, interruptible: true)
        guard case .some(let transport) = transport else {
            return false
        }
        guard let transport else {
            throw .operationNotSupportedByDevice
        }

        return try transport.waitForNextMessage(until: deadline)
    }

    /// Receives the next complete message.
    ///
    /// - Returns: The next complete message.
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed, or another
    ///   transport-defined `Errno` value if the receive operation fails.
    func nextMessage() throws(Errno) -> any Message {
        guard let transport = try $transport.wait(interruptible: true) else {
            throw .operationNotSupportedByDevice
        }
        return try transport.nextMessage()
    }

    /// Sends one complete message.
    ///
    /// - Parameter buffers: The body buffers whose concatenation forms the message body.
    /// - Returns: The number of bytes sent.
    /// - Throws: `Errno.operationNotSupportedByDevice` if the channel is closed, or another
    ///   transport-defined `Errno` value if the send operation fails.
    func send(message buffers: any Sequence<UnsafeRawBufferPointer>) throws(Errno) -> Int {
        guard let transport = $transport.wait() else {
            throw .operationNotSupportedByDevice
        }
        return try transport.send(message: buffers)
    }
}
