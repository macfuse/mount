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

    /// Waits until the value is resolved or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    func wait(until deadline: Deadline) -> T?

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

    /// The resolver interface exposed by the property wrapper projection.
    public typealias Resolver = BlockingLazyResolver

    private let condition: NSCondition
    private let atomicBox: ManagedAtomicLazyReference<Box>

    /// Creates an unresolved blocking lazy value.
    public init() {
        condition = NSCondition()
        atomicBox = ManagedAtomicLazyReference()
    }

    /// The resolved value, if the value has already been resolved.
    public var value: T? {
        return atomicBox.load()?.value
    }

    /// Waits until the value is resolved.
    ///
    /// - Returns: The resolved value.
    public func wait() -> T {
        if let box = atomicBox.load() {
            return box.value
        }

        return condition.withLock {
            while true {
                if let box = atomicBox.load() {
                    return box.value
                }

                condition.wait()
            }
        }
    }

    /// Waits until the value is resolved or the deadline expires.
    ///
    /// - Parameter deadline: The deadline that bounds how long the call may wait.
    /// - Returns: The resolved value, or `nil` if the deadline expires before resolution.
    public func wait(until deadline: Deadline) -> T? {
        if let box = atomicBox.load() {
            return box.value
        }
        if case .forever = deadline {
            return wait()
        }

        let date: Date? = if case .deadline(let time) = deadline {
            Date(dispatchTime: time)
        } else {
            nil
        }

        return condition.withLock {
            while true {
                if let box = atomicBox.load() {
                    return box.value
                }

                guard let date, condition.wait(until: date) else {
                    return nil
                }
            }
        }
    }

    /// A Boolean value that indicates whether the value has been resolved.
    public var isResolved: Bool {
        atomicBox.load() != nil
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
        guard atomicBox.storeIfNilThenLoad(box) === box else {
            return false
        }

        condition.withLock {
            condition.broadcast()
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
