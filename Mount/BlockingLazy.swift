//
//  BlockingLazy.swift
//  Mount
//
//  Copyright (c) 2026 Benjamin Fleischer
//  All rights reserved.
//
//  This framework can be distributed under the terms of the GNU LGPL. See the file LICENSE.txt.
//

internal import Atomics
import Foundation
import System

/// An interface for resolving and waiting on a ``BlockingLazy`` value.
///
/// A resolver exposes the resolved value, if one is available, and provides blocking wait
/// operations for callers that need the value before continuing.
public protocol BlockingLazyResolver<T> {
    associatedtype T

    /// The resolved value, if the value has already been resolved.
    var value: T? { get }

    /// Waits until the value is resolved.
    ///
    /// - Returns: The resolved value.
    func wait() -> T

    /// Waits until the value is resolved or, if requested, the wait is interrupted.
    ///
    /// - Parameter interruptible: A Boolean value that indicates whether ``interrupt()`` may abort
    ///   this wait.
    /// - Returns: The resolved value.
    /// - Throws: `Errno.interrupted` if `interruptible` is `true` and the wait is interrupted
    ///   before the value is resolved.
    func wait(interruptible: Bool) throws(Errno) -> T

    /// Waits until the value is resolved or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    func wait(until deadline: Deadline) -> T?

    /// Waits until the value is resolved, the deadline expires, or, if requested, the wait is
    /// interrupted.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Parameter interruptible: A Boolean value that indicates whether ``interrupt()`` may abort
    ///   this wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    /// - Throws: `Errno.interrupted` if `interruptible` is `true` and the wait is interrupted
    ///   before the value is resolved.
    func wait(until deadline: Deadline, interruptible: Bool) throws(Errno) -> T?

    /// Interrupts currently blocked interruptible waits.
    func interrupt()

    /// A Boolean value that indicates whether the value has been resolved.
    var isResolved: Bool { get }

    /// Resolves the value.
    ///
    /// Only the first call to this method stores a value. Later calls leave the original value
    /// unchanged.
    ///
    /// - Parameter value: The value to store.
    /// - Returns: `true` if this call resolved the value, or `false` if the value was already
    ///   resolved.
    @discardableResult func resolve(_ value: T) -> Bool
}

/// A property wrapper for a value that is resolved once and can be waited on by other threads.
///
/// `BlockingLazy` starts unresolved. Readers of ``wrappedValue`` block until a resolver provides
/// the value by calling ``resolve(_:)``. Use ``projectedValue`` to pass a resolver to code that
/// should be able to resolve or wait on the value without direct access to the wrapped property.
@propertyWrapper
public struct BlockingLazy<T>: BlockingLazyResolver<T> {
    private class Box {
        var value: T

        init(_ value: T) {
            self.value = value
        }
    }

    private class State {
        let atomicBox: ManagedAtomicLazyReference<Box>
        let condition: NSCondition
        var interruptGeneration: UInt64

        init() {
            atomicBox = ManagedAtomicLazyReference()
            condition = NSCondition()
            interruptGeneration = 0
        }
    }

    /// The resolver interface exposed by the property wrapper projection.
    public typealias Resolver = BlockingLazyResolver

    /// Shared storage for the resolved value, wait condition, and interrupt generation.
    private let state: State

    /// Creates an unresolved blocking lazy value.
    public init() {
        state = State()
    }

    /// The resolved value, if the value has already been resolved.
    public var value: T? {
        return state.atomicBox.load()?.value
    }

    /// Waits until the value is resolved.
    ///
    /// - Returns: The resolved value.
    public func wait() -> T {
        try! wait(interruptible: false)
    }

    /// Waits until the value is resolved or, if requested, the wait is interrupted.
    ///
    /// - Parameter interruptible: A Boolean value that indicates whether ``interrupt()`` may abort
    ///   this wait.
    /// - Returns: The resolved value.
    /// - Throws: `Errno.interrupted` if `interruptible` is `true` and the wait is interrupted before
    ///   the value is resolved.
    public func wait(interruptible: Bool) throws(Errno) -> T {
        if let box = state.atomicBox.load() {
            return box.value
        }

        state.condition.lock()
        defer {
            state.condition.unlock()
        }

        let generation = state.interruptGeneration

        while true {
            if let box = state.atomicBox.load() {
                return box.value
            }
            guard !interruptible || state.interruptGeneration == generation else {
                throw .interrupted
            }

            state.condition.wait()
        }
    }

    /// Waits until the value is resolved or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    public func wait(until deadline: Deadline) -> T? {
        try! wait(until: deadline, interruptible: false)
    }

    /// Waits until the value is resolved, the deadline expires, or, if requested, the wait is
    /// interrupted.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Parameter interruptible: A Boolean value that indicates whether ``interrupt()`` may abort
    ///   this wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    /// - Throws: `Errno.interrupted` if `interruptible` is `true` and the wait is interrupted before
    ///   the value is resolved.
    public func wait(until deadline: Deadline, interruptible: Bool) throws(Errno) -> T? {
        if let box = state.atomicBox.load() {
            return box.value
        }
        if case .forever = deadline {
            return try wait(interruptible: interruptible)
        }

        let date: Date? = if case .deadline(let time) = deadline {
            Date(dispatchTime: time)
        } else {
            nil
        }

        state.condition.lock()
        defer {
            state.condition.unlock()
        }

        let generation = state.interruptGeneration

        while true {
            if let box = state.atomicBox.load() {
                return box.value
            }
            guard !interruptible || state.interruptGeneration == generation else {
                throw Errno.interrupted
            }
            guard let date else {
                return nil
            }
            guard state.condition.wait(until: date) else {
                guard !interruptible || state.interruptGeneration == generation else {
                    throw Errno.interrupted
                }
                return nil
            }
        }
    }

    /// Interrupts currently blocked interruptible waits.
    public func interrupt() {
        state.condition.withLock {
            state.interruptGeneration &+= 1
            state.condition.broadcast()
        }
    }

    /// A Boolean value that indicates whether the value has been resolved.
    public var isResolved: Bool {
        state.atomicBox.load() != nil
    }

    /// Resolves the value.
    ///
    /// Only the first call to this method stores a value. Later calls leave the original value
    /// unchanged.
    ///
    /// - Parameter value: The value to store.
    /// - Returns: `true` if this call resolved the value, or `false` if the value was already
    ///   resolved.
    @discardableResult
    public func resolve(_ value: T) -> Bool {
        let box = Box(value)
        guard state.atomicBox.storeIfNilThenLoad(box) === box else {
            return false
        }

        state.condition.withLock {
            state.condition.broadcast()
        }
        return true
    }

    /// The wrapped value.
    ///
    /// Accessing this property blocks until the value is resolved.
    public var wrappedValue: T {
        wait()
    }

    /// A resolver for the wrapped value.
    public var projectedValue: any Resolver<T> {
        self
    }
}
