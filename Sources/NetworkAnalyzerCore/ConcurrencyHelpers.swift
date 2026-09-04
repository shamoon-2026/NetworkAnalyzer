import Foundation

/// Resumes a `CheckedContinuation` exactly once, even when the underlying delegate-style API
/// (e.g. `NWConnection.stateUpdateHandler`, a `DispatchQueue.asyncAfter` timeout racing it) isn't
/// provably single-threaded to the compiler under Swift 6 strict concurrency.
final class OneShotContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(with value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Wraps a single non-Sendable value (e.g. a C `OpaquePointer` handle) that's only ever touched
/// from one queue/thread at a time, to cross an `@Sendable` closure boundary the compiler can't
/// otherwise verify.
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

/// A lock-protected box for state written from a delegate callback and read afterwards, for the
/// same "not provably single-threaded" reason as `OneShotContinuation`.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
