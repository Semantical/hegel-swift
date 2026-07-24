import CHegel
import Synchronization

/// Values created by earlier state-machine rules and selectable by later ones.
///
/// Equal values remain distinct pool entries. The pool is noncopyable because
/// it uniquely mirrors engine-owned variable identifiers.
public struct Pool<Value>: ~Copyable {
    var testCase: PoolTestCase?
    var id: Int64?
    var values: [Int64: Value]

    public init() {
        self.testCase = nil
        self.id = nil
        self.values = [:]
    }

    public var count: Int {
        values.count
    }

    public var isEmpty: Bool {
        values.isEmpty
    }

    /// Adds another active value to the pool.
    public mutating func add(_ value: Value) throws {
        try bind()
        guard let testCase else {
            preconditionFailure("A bound pool must own a test case.")
        }
        let poolID = try testCase.withValue { testCase in
            try id(using: &testCase)
        }
        let variableID = try testCase.withValue { testCase in
            var variableID: Int64 = 0
            try testCase.checkDraw(
                unsafe hegel_pool_add(
                    testCase.context.handle,
                    testCase.handle,
                    poolID,
                    &variableID,
                )
            )
            return variableID
        }
        if case .some = values.updateValue(value, forKey: variableID) {
            preconditionFailure("Hegel reused an active pool variable identifier.")
        }
    }

    /// Draws an active value without removing it from the pool.
    public borrowing func draw() throws -> Value {
        let testCase = try boundTestCase()
        guard let id else {
            throw TestControl.invalid
        }
        let variableID = try testCase.withValue { testCase in
            try variable(
                using: &testCase,
                poolID: id,
                consuming: false,
            )
        }
        guard let value = values[variableID] else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    /// Draws and removes an active value from the pool.
    public mutating func take() throws -> Value {
        let testCase = try boundTestCase()
        guard let id else {
            throw TestControl.invalid
        }
        let variableID = try testCase.withValue { testCase in
            try variable(
                using: &testCase,
                poolID: id,
                consuming: true,
            )
        }
        guard let value = values.removeValue(forKey: variableID) else {
            throw HegelError("Hegel selected an unknown pool variable.")
        }
        return value
    }

    mutating func bindToCurrentStateMachine() throws {
        guard let currentTestCase = _HegelScope.current.poolTestCase else {
            return
        }
        if let testCase {
            guard testCase === currentTestCase else {
                throw HegelError("A pool cannot be reused across state-machine runs.")
            }
            return
        }
        self.testCase = currentTestCase
    }

    private mutating func bind() throws {
        let currentTestCase = try currentTestCase()
        if let testCase {
            guard testCase === currentTestCase else {
                throw HegelError("A pool cannot be reused across state-machine runs.")
            }
            return
        }
        self.testCase = currentTestCase
    }

    private borrowing func boundTestCase() throws -> PoolTestCase {
        let currentTestCase = try currentTestCase()
        guard let testCase else {
            throw TestControl.invalid
        }
        guard testCase === currentTestCase else {
            throw HegelError("A pool cannot be reused across state-machine runs.")
        }
        return testCase
    }

    private borrowing func currentTestCase() throws -> PoolTestCase {
        guard let testCase = _HegelScope.current.poolTestCase else {
            throw HegelError(
                "Context-free pool operations require a running state machine."
            )
        }
        return testCase
    }

    private mutating func id(
        using testCase: inout sending TestCase
    ) throws -> Int64 {
        if let id {
            return id
        }
        var id: Int64 = 0
        try testCase.checkDraw(
            unsafe hegel_new_pool(
                testCase.context.handle,
                testCase.handle,
                &id,
            )
        )
        self.id = id
        return id
    }

    private borrowing func variable(
        using testCase: inout sending TestCase,
        poolID: Int64,
        consuming: Bool,
    ) throws -> Int64 {
        var variableID: Int64 = 0
        try testCase.checkDraw(
            unsafe hegel_pool_generate(
                testCase.context.handle,
                testCase.handle,
                poolID,
                consuming,
                &variableID,
            )
        )
        return variableID
    }
}

/// The independent stream used by context-free pool operations in one state-machine run.
///
/// All pools serialize access to this handle. Their engine objects remain
/// shared with the original test case because both handles belong to one family.
final class PoolTestCase: Sendable {
    private let value: Mutex<TestCase>

    init(_ value: borrowing TestCase) throws(HegelError) {
        self.value = Mutex(try value.clone())
    }

    func withValue<Result: ~Copyable>(
        _ body: (inout sending TestCase) throws -> sending Result
    ) throws -> sending Result {
        try value.withLock { value in
            try body(&value)
        }
    }
}

extension TestCase {
    /// Adds another active value to a state-machine pool.
    public func add<Value>(_ value: Value, to pool: inout Pool<Value>) throws {
        try pool.bindToCurrentStateMachine()
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
