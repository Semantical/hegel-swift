import CHegel

@resultBuilder
public enum _StaticListBuilder<Element> {
    public static func buildExpression(_ element: Element) -> Element {
        element
    }

    public static func buildBlock(_ elements: Element...) -> [Element] {
        elements
    }
}

/// A named state transition selected and shrunk by Hegel.
public struct Rule<Machine: ~Copyable> {
    var name: StaticString
    var apply: (inout Machine, borrowing TestCase) async throws -> Void

    public init(
        _ name: StaticString,
        _ apply: @escaping (inout Machine, borrowing TestCase) async throws -> Void,
    ) {
        self.name = name
        self.apply = apply
    }
}

/// A named property checked initially and after every successful rule.
public struct Invariant<Machine: ~Copyable> {
    var name: StaticString
    var check: (borrowing Machine, borrowing TestCase) async throws -> Void

    public init(
        _ name: StaticString,
        _ check: @escaping (borrowing Machine, borrowing TestCase) async throws -> Void,
    ) {
        self.name = name
        self.check = check
    }

    public init(
        _ name: StaticString,
        _ check: @escaping (borrowing Machine) async throws -> Void,
    ) {
        self.name = name
        self.check = { machine, _ in
            try await check(machine)
        }
    }
}

/// Mutable model and resources exercised by a fixed vocabulary of rules.
///
/// A machine's ordered rules and invariants must remain stable across every
/// generated example and replay.
public protocol StateMachine: ~Copyable {
    typealias Rules = [Rule<Self>]
    typealias Invariants = [Invariant<Self>]

    @_StaticListBuilder<Rule<Self>>
    static var rules: Rules { get }

    @_StaticListBuilder<Invariant<Self>>
    static var invariants: Invariants { get }
}

extension StateMachine where Self: ~Copyable {
    public static var invariants: Invariants {
        []
    }

    public static func rule(
        _ name: StaticString,
        _ apply: @escaping (inout Self, borrowing TestCase) async throws -> Void,
    ) -> Rule<Self> {
        Rule(name, apply)
    }

    public static func invariant(
        _ name: StaticString,
        _ check: @escaping (borrowing Self, borrowing TestCase) async throws -> Void,
    ) -> Invariant<Self> {
        Invariant(name, check)
    }

    public static func invariant(
        _ name: StaticString,
        _ check: @escaping (borrowing Self) async throws -> Void,
    ) -> Invariant<Self> {
        Invariant(name, check)
    }
}

extension TestCase {
    /// Runs a fresh state machine until Hegel exhausts its chosen rule sequence.
    public func run<Machine: StateMachine & ~Copyable>(
        _ machine: consuming Machine
    ) async throws {
        let rules = Machine.rules
        let invariants = Machine.invariants
        precondition(!rules.isEmpty, "A state machine requires at least one rule.")
        let issueContext = _HegelScope.current.issueContext
        issueContext?.beginStateMachine()

        let stateMachineID = try stateMachine(
            rules: rules.map(\.name),
            invariants: invariants.map(\.name),
        )
        guard try await check(invariants, against: machine) else {
            return
        }

        while let index = try nextRule(in: stateMachineID, count: rules.count) {
            issueContext?.recordStateMachineRule(rules[index].name)
            do {
                try await rules[index].apply(&machine, self)
            } catch TestControl.invalid {
                guard !hasRecordedIssue else {
                    return
                }
                continue
            }
            guard !hasRecordedIssue else {
                return
            }
            guard try await check(invariants, against: machine) else {
                return
            }
        }
    }

    private var hasRecordedIssue: Bool {
        _HegelScope.current.issueContext?.hasRecordedIssue == true
    }

    private func check<Machine: ~Copyable>(
        _ invariants: [Invariant<Machine>],
        against machine: borrowing Machine,
    ) async throws -> Bool {
        for invariant in invariants {
            do {
                try await invariant.check(machine, self)
            } catch TestControl.invalid where hasRecordedIssue {
                return false
            }
            guard !hasRecordedIssue else {
                return false
            }
        }
        return true
    }

    private func stateMachine(
        rules: [StaticString],
        invariants: [StaticString],
    ) throws -> Int64 {
        let rules = CStringArray(rules)
        let invariants = CStringArray(invariants)
        var stateMachineID: Int64 = 0
        try unsafe rules.withUnsafePointers { rulePointers, ruleCount in
            try unsafe invariants.withUnsafePointers { invariantPointers, invariantCount in
                try checkDraw(
                    unsafe hegel_new_state_machine(
                        context.handle,
                        handle,
                        rulePointers,
                        ruleCount,
                        invariantPointers,
                        invariantCount,
                        &stateMachineID,
                    )
                )
            }
        }
        return stateMachineID
    }

    private func nextRule(in stateMachineID: Int64, count: Int) throws -> Int? {
        var index = Int64(HEGEL_STATE_MACHINE_DONE)
        try checkDraw(
            unsafe hegel_state_machine_next_rule(
                context.handle,
                handle,
                stateMachineID,
                &index,
            )
        )
        guard index != HEGEL_STATE_MACHINE_DONE else {
            return nil
        }
        guard index >= 0, index < count else {
            throw HegelError("Hegel selected an unknown state-machine rule.")
        }
        return Int(index)
    }
}

private struct CStringArray {
    var storage: [CChar]
    var offsets: [Int]

    init(_ strings: [StaticString]) {
        var storage: [CChar] = []
        var offsets: [Int] = []
        for string in strings {
            offsets.append(storage.count)
            storage.append(contentsOf: String(describing: string).utf8CString)
        }
        self.storage = storage
        self.offsets = offsets
    }

    func withUnsafePointers<Result>(
        _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) throws -> Result
    ) rethrows -> Result {
        unsafe try storage.withUnsafeBufferPointer { storage in
            let pointers: [UnsafePointer<CChar>?] = unsafe offsets.map { offset in
                unsafe storage.baseAddress?.advanced(by: offset)
            }
            return unsafe try pointers.withUnsafeBufferPointer { pointers in
                try unsafe body(pointers.baseAddress, pointers.count)
            }
        }
    }
}
