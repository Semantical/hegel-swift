import CHegel

/// Values created by earlier state-machine rules and selectable by later ones.
///
/// Equal values remain distinct pool entries. The pool is noncopyable because
/// it uniquely mirrors engine-owned variable identifiers.
@safe
public struct Pool<Value>: ~Copyable {
    var handle: OpaquePointer?
    var values: [Int64: Value]

    public init() {
        unsafe self.handle = nil
        self.values = [:]
    }

    deinit {
        _ = unsafe hegel_pool_free(nil, handle)
    }

    public var count: Int {
        values.count
    }

    public var isEmpty: Bool {
        values.isEmpty
    }
}

extension TestCase {
    /// Adds another active value to a state-machine pool.
    public func add<Value>(_ value: Value, to pool: inout Pool<Value>) throws {
        let poolHandle = unsafe try handle(for: &pool)
        var variableID: Int64 = 0
        try checkDraw(
            unsafe hegel_pool_add(
                context.handle,
                handle,
                poolHandle,
                &variableID,
            )
        )
        if case .some = pool.values.updateValue(value, forKey: variableID) {
            preconditionFailure("Hegel reused an active pool variable identifier.")
        }
    }

    /// Draws an active value without removing it from the pool.
    public func draw<Value>(from pool: borrowing Pool<Value>) throws -> Value {
        guard let poolHandle = unsafe pool.handle else {
            throw TestControl.invalid
        }
        let variableID = unsafe try poolVariable(in: poolHandle, consuming: false)
        guard let value = pool.values[variableID] else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    /// Draws and removes an active value from the pool.
    public func take<Value>(from pool: inout Pool<Value>) throws -> Value {
        guard let poolHandle = unsafe pool.handle else {
            throw TestControl.invalid
        }
        let variableID = unsafe try poolVariable(in: poolHandle, consuming: true)
        guard let value = pool.values.removeValue(forKey: variableID) else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    private func handle<Value>(for pool: inout Pool<Value>) throws -> OpaquePointer {
        if let handle = unsafe pool.handle {
            return unsafe handle
        }
        var handle: OpaquePointer?
        try checkDraw(
            unsafe hegel_new_pool(
                context.handle,
                self.handle,
                &handle,
            )
        )
        guard let handle = unsafe handle else {
            throw HegelError("Hegel returned an empty pool handle.")
        }
        unsafe pool.handle = handle
        return unsafe handle
    }

    private func poolVariable(
        in poolHandle: OpaquePointer,
        consuming: Bool,
    ) throws -> Int64 {
        var variableID: Int64 = 0
        try checkDraw(
            unsafe hegel_pool_generate(
                context.handle,
                handle,
                poolHandle,
                consuming,
                &variableID,
            )
        )
        return variableID
    }
}
