import CHegel

/// Values created by earlier state-machine rules and selectable by later ones.
///
/// Equal values remain distinct pool entries. The pool is noncopyable because
/// it uniquely mirrors engine-owned variable identifiers.
public struct Pool<Value>: ~Copyable {
    var id: Int64?
    var values: [Int64: Value]

    public init() {
        self.id = nil
        self.values = [:]
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
        let poolID = try id(for: &pool)
        var variableID: Int64 = 0
        try checkDraw(
            unsafe hegel_pool_add(
                context.handle,
                handle,
                poolID,
                &variableID,
            )
        )
        if case .some = pool.values.updateValue(value, forKey: variableID) {
            preconditionFailure("Hegel reused an active pool variable identifier.")
        }
    }

    /// Draws an active value without removing it from the pool.
    public func draw<Value>(from pool: borrowing Pool<Value>) throws -> Value {
        guard let poolID = pool.id else {
            throw TestControl.invalid
        }
        let variableID = try poolVariable(in: poolID, consuming: false)
        guard let value = pool.values[variableID] else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    /// Draws and removes an active value from the pool.
    public func take<Value>(from pool: inout Pool<Value>) throws -> Value {
        guard let poolID = pool.id else {
            throw TestControl.invalid
        }
        let variableID = try poolVariable(in: poolID, consuming: true)
        guard let value = pool.values.removeValue(forKey: variableID) else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    private func id<Value>(for pool: inout Pool<Value>) throws -> Int64 {
        if let id = pool.id {
            return id
        }
        var id: Int64 = 0
        try checkDraw(
            unsafe hegel_new_pool(
                context.handle,
                handle,
                &id,
            )
        )
        pool.id = id
        return id
    }

    private func poolVariable(
        in poolID: Int64,
        consuming: Bool,
    ) throws -> Int64 {
        var variableID: Int64 = 0
        try checkDraw(
            unsafe hegel_pool_generate(
                context.handle,
                handle,
                poolID,
                consuming,
                &variableID,
            )
        )
        return variableID
    }
}
