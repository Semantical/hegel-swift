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

/// A named property checked initially, finally, and at Hegel-selected join points.
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

        let stateMachine = unsafe try stateMachine(
            rules: rules.map(\.name),
            invariants: invariants.map(\.name),
        )
        defer {
            _ = unsafe hegel_state_machine_free(context.handle, stateMachine)
        }
        guard try await check(invariants, against: machine) else {
            return
        }

        while unsafe try startNextGroup(in: stateMachine) {
            while let index = unsafe try nextRule(in: stateMachine, count: rules.count) {
                issueContext?.recordStateMachineRule(rules[index].name)
                do {
                    try await rules[index].apply(&machine, self)
                } catch TestControl.invalid {
                    guard !hasRecordedIssue else {
                        return
                    }
                    unsafe try rejectRule(in: stateMachine)
                    continue
                }
                guard !hasRecordedIssue else {
                    return
                }
            }
            guard unsafe try await checkSampled(
                invariants,
                against: machine,
                in: stateMachine,
            ) else {
                return
            }
            #if os(WASI)
            await Task.yield()
            #endif
        }
        _ = try await check(invariants, against: machine)
    }

    private func checkSampled<Machine: ~Copyable>(
        _ invariants: [Invariant<Machine>],
        against machine: borrowing Machine,
        in stateMachine: OpaquePointer,
    ) async throws -> Bool {
        for (index, invariant) in invariants.enumerated() {
            guard unsafe try shouldCheckInvariant(index, in: stateMachine) else {
                continue
            }
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
    ) throws -> OpaquePointer {
        let groups = Array(repeating: Int64(0), count: rules.count)
        let rules = CStringArray(rules)
        let invariants = CStringArray(invariants)
        var stateMachine: OpaquePointer?
        var concurrency: Int64 = 0
        try unsafe groups.withUnsafeBufferPointer { groups in
            try unsafe rules.withUnsafePointers { rulePointers, ruleCount in
                try unsafe invariants.withUnsafePointers { invariantPointers, invariantCount in
                    try checkDraw(
                        unsafe hegel_new_state_machine(
                            context.handle,
                            handle,
                            rulePointers,
                            groups.baseAddress,
                            ruleCount,
                            invariantPointers,
                            invariantCount,
                            1,
                            1,
                            &stateMachine,
                            &concurrency,
                        )
                    )
                }
            }
        }
        guard concurrency == 1 else {
            throw HegelError("Hegel selected unexpected state-machine concurrency.")
        }
        guard let stateMachine = unsafe stateMachine else {
            throw HegelError("Hegel returned an empty state-machine handle.")
        }
        return unsafe stateMachine
    }

    private func startNextGroup(in stateMachine: OpaquePointer) throws -> Bool {
        var group = Int64.min
        try checkDraw(
            unsafe hegel_state_machine_next_group(
                context.handle,
                handle,
                stateMachine,
                &group,
            )
        )
        return group != Int64.min
    }

    private func nextRule(in stateMachine: OpaquePointer, count: Int) throws -> Int? {
        var index = Int64.min
        try checkDraw(
            unsafe hegel_state_machine_next_rule(
                context.handle,
                handle,
                stateMachine,
                0,
                &index,
            )
        )
        guard index != Int64.min else {
            return nil
        }
        guard index >= 0, index < count else {
            throw HegelError("Hegel selected an unknown state-machine rule.")
        }
        return Int(index)
    }

    private func rejectRule(in stateMachine: OpaquePointer) throws {
        try checkDraw(
            unsafe hegel_state_machine_rule_rejected(
                context.handle,
                handle,
                stateMachine,
                0,
            )
        )
    }

    private func shouldCheckInvariant(
        _ index: Int,
        in stateMachine: OpaquePointer,
    ) throws -> Bool {
        var shouldCheck = false
        try checkDraw(
            unsafe hegel_state_machine_should_check_invariant(
                context.handle,
                handle,
                stateMachine,
                Int64(index),
                &shouldCheck,
            )
        )
        return shouldCheck
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
