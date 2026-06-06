//
//  XPCTransport.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

internal import Collections
internal import DequeModule
import Darwin
import Dispatch
import Foundation
import OSLog
import System
@preconcurrency import XPC

/// A channel transport backed by an XPC listener and peer connection.
final class XPCTransport: Channel.Transport, @unchecked Sendable {
    /// Mutable transport state protected by `condition`.
    private struct State {
        /// A Boolean value that indicates whether the transport can no longer exchange messages.
        var isInvalid: Bool

        /// Incremented whenever a signal should interrupt blocked receive operations.
        var interruptGeneration: UInt64

        /// The current channel flags.
        var flags: Channel.Flags

        /// Messages received from the peer and not yet consumed by the channel.
        var received: Deque<Message>

        init() {
            isInvalid = false
            interruptGeneration = 0
            flags = []
            received = Deque()
        }
    }

    private let listener: xpc_connection_t
    private let condition: NSCondition
    private let signalSource: DispatchSourceSignal
    private var state: State

    @BlockingLazy
    private var connection: xpc_connection_t?

    /// Creates an inactive XPC transport.
    init() {
        listener = xpc_connection_create(nil, nil)
        condition = NSCondition()
        signalSource = DispatchSource.makeSignalSource(signal: SIGPIPE)
        state = State()
    }

    /// The endpoint passed to the mount service so the file system extension can connect.
    var endpoint: xpc_endpoint_t {
        xpc_endpoint_create(listener)
    }

    /// Activates the listener and waits for a file system extension peer connection.
    ///
    /// The listener accepts one endpoint-based peer connection from the file system extension. If the
    /// listener is invalidated before a peer connects, blocked send operations fail with
    /// `Errno.operationNotSupportedByDevice`.
    func activate() throws(Errno) {
        xpc_connection_set_event_handler(listener) { [weak self] event in
            guard let self else {
                return
            }

            guard xpc_get_type(event) == XPC_TYPE_CONNECTION else {
                if event === XPC_ERROR_CONNECTION_INVALID {
                    condition.withLock {
                        self.state.isInvalid = true
                        condition.broadcast()
                    }
                    self.$connection.resolve(nil)
                }
                return
            }

            self.handle(connection: event)
        }

        xpc_connection_activate(listener)

        signalSource.setEventHandler { [weak self] in
            self?.interrupt()
        }
        signalSource.resume()
    }

    /// Cancels the listener and its endpoint-based peer connections.
    ///
    /// Canceling the transport wakes blocked receive operations and prevents future message
    /// exchange.
    func deactivate() throws(Errno) {
        /*
         * Cancelling the listener connection will cancel all endpoint-based peer connections as
         * well. There is no need to cancel the peer connection used to pass messages to the file
         * system extension.
         */

        let cancel = { xpc_connection_cancel(self.listener) }

        if case .some(.some(let connection)) = $connection.value {
            xpc_connection_send_barrier(connection, cancel)
        } else {
            signalSource.cancel()
            cancel()
        }
    }

    /// Configures and activates a file system extension peer connection.
    ///
    /// - Parameter connection: The accepted XPC peer connection.
    private func handle(connection: xpc_connection_t) {
        xpc_connection_set_event_handler(connection) { [weak self] event in
            guard let self else {
                return
            }

            guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
                if event === XPC_ERROR_CONNECTION_INVALID {
                    Logger.mount.info("Connection to file system extension invalidated")

                    signalSource.cancel()

                    self.condition.withLock {
                        self.state.isInvalid = true
                        self.condition.broadcast()
                    }
                }
                return
            }

            do {
                let message = try XPCMessage(event)

                self.condition.withLock {
                    self.state.received.append(message)
                    self.condition.signal()
                }
            } catch {
                Logger.mount.info("Received illegal message from file system extension")
                self.condition.withLock {
                    self.state.isInvalid = true
                    self.condition.broadcast()
                }
            }
        }
        xpc_connection_activate(connection)

        Logger.mount.info("Connection to file system extension established")
        $connection.resolve(connection)
    }

    /// Interrupts blocked receive operations without invalidating the transport.
    private func interrupt() {
        condition.withLock {
            state.interruptGeneration &+= 1
            condition.broadcast()
        }
    }

    /// Returns the current channel flags.
    func getFlags() throws(Errno) -> Channel.Flags {
        condition.withLock { state.flags }
    }

    /// Replaces the current channel flags.
    ///
    /// - Parameter flags: The new channel flags.
    func setFlags(_ flags: Channel.Flags) throws(Errno) {
        condition.withLock { state.flags = flags }
    }

    /// Waits until an XPC message is queued or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: `true` if a message is available, or `false` if the deadline expires.
    /// - Throws: `Errno.interrupted` if the wait is interrupted, or
    ///   `Errno.operationNotSupportedByDevice` if the peer connection is no longer available.
    func waitForNextMessage(until deadline: Deadline) throws(Errno) -> Bool {
        let date: Date? = switch deadline {
        case .immediate:
            nil
        case .deadline(let time):
            Date(dispatchTime: time)
        case .forever:
            .distantFuture
        }

        do {
            return try condition.withLock { () throws(Errno) in
                let interruptGeneration = state.interruptGeneration

                while true {
                    if state.received.first != nil {
                        return true
                    }
                    guard !state.isInvalid else {
                        throw .operationNotSupportedByDevice
                    }
                    guard state.interruptGeneration == interruptGeneration else {
                        throw .interrupted
                    }
                    guard let date, condition.wait(until: date) else {
                        return false
                    }
                }
            }
        } catch let error as Errno {
            throw error
        } catch {
            // We made sure we will never get here
            fatalError()
        }
    }

    /// Removes and returns the next queued XPC message.
    ///
    /// - Returns: The next complete message.
    /// - Throws: `Errno.wouldBlock` if the transport is in non-blocking mode and no complete message
    ///   is available, `Errno.interrupted` if the receive operation is interrupted, or
    ///   `Errno.operationNotSupportedByDevice` if the peer connection is no longer available.
    func nextMessage() throws(Errno) -> Message {
        do {
            return try condition.withLock { () throws(Errno) in
                let isNonBlocking = state.flags.contains(.nonBlocking)
                let interruptGeneration = state.interruptGeneration

                while true {
                    guard let message = state.received.popFirst() else {
                        guard !state.isInvalid else {
                            throw .operationNotSupportedByDevice
                        }
                        guard !isNonBlocking else {
                            throw .wouldBlock
                        }
                        guard state.interruptGeneration == interruptGeneration else {
                            throw .interrupted
                        }

                        condition.wait()
                        continue
                    }

                    return message
                }
            }
        } catch let error as Errno {
            throw error
        } catch {
            // We made sure we will never get here
            fatalError()
        }
    }

    /// Sends one complete message body to the connected file system extension.
    ///
    /// This method waits until the file system extension has established its peer connection.
    ///
    /// - Parameter buffers: The body buffers whose concatenation forms the message body.
    /// - Returns: The number of bytes queued for sending.
    /// - Throws: `Errno.operationNotSupportedByDevice` if the peer connection is no longer
    ///   available.
    func send(message buffers: any Sequence<UnsafeRawBufferPointer>) throws(Errno) -> Int {
        /*
         * Threads may block while waiting for the connection to be established. Once it is
         * established, nothing else in send(message:) can leave threads blocked, so connection
         * invalidation does not require any special wake-up handling.
         */

        guard let connection = $connection.wait() else {
            // The XPC connection was never established.
            throw .operationNotSupportedByDevice
        }

        let body = xpc_array_create_empty()
        var byteCount = 0

        for buffer in buffers {
            xpc_array_set_data(body, XPC_ARRAY_APPEND, buffer.baseAddress, buffer.count)
            byteCount += buffer.count
        }

        let message = xpc_dictionary_create_empty()
        xpc_dictionary_set_value(message, "body", body)
        xpc_connection_send_message(connection, message)

        return byteCount
    }
}
