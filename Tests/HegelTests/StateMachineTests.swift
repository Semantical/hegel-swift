import Hegel
import Synchronization
import Testing

private struct StateMachineFailure: Error {
    var steps: Int
}

private var stateMachineSettings: Settings {
    Settings(
        testCases: 200,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
    )
}

private let capturedStateMachineIssue = Mutex<Issue?>(nil)

@Test(.hegel(settings: stateMachineSettings))
private func `requires a state machine for context-free pool operations`() async throws {
    try await property { ctx in
        var values = Pool<Int>()
        #expect(throws: HegelError.self) {
            try values.add(1)
        }

        try ctx.add(1, to: &values)
        #expect(try ctx.draw(from: values) == 1)
        #expect(throws: HegelError.self) {
            try values.draw()
        }
    }
}

private struct PoolMachine: ~Copyable, StateMachine {
    var expected: [Int] = []
    var values = Pool<Int>()

    static var rules: Rules {
        rule("add duplicate values") { machine, ctx in
            let value = try ctx.draw(.integers(in: 0...10))
            try machine.values.add(value)
            try ctx.add(value, to: &machine.values)
            machine.expected.append(contentsOf: [value, value])

            let reused = try machine.values.draw()
            #expect(machine.expected.contains(reused))

            let taken = try machine.values.take()
            let index = try #require(machine.expected.firstIndex(of: taken))
            machine.expected.remove(at: index)
        }

        rule("reuse a value") { machine, ctx in
            let value = try machine.values.draw()
            #expect(machine.expected.contains(value))
        }

        rule("consume a value") { machine, ctx in
            let value = try machine.values.take()
            let index = try #require(machine.expected.firstIndex(of: value))
            machine.expected.remove(at: index)
        }
    }

    static var invariants: Invariants {
        invariant("pool mirrors the model") { machine in
            #expect(machine.values.count == machine.expected.count)
            #expect(machine.values.isEmpty == machine.expected.isEmpty)
        }
    }

    @Test(.hegel(settings: stateMachineSettings))
    static func `tracks reusable and consumed values`() async throws {
        try await property { ctx in
            try await ctx.run(Self())
        }
    }
}

private struct ShrinkingMachine: StateMachine {
    var steps = 0

    static var rules: Rules {
        rule("increment") { machine, _ in
            machine.steps += 1
            guard machine.steps < 3 else {
                throw StateMachineFailure(steps: machine.steps)
            }
        }
    }

    @Test(
        .compactMapIssues { issue in
            guard issue.error is StateMachineFailure else {
                return issue
            }
            capturedStateMachineIssue.withLock { $0 = issue }
            return nil
        },
        .hegel(settings: stateMachineSettings),
    )
    static func `shrinks rule sequences`() async throws {
        capturedStateMachineIssue.withLock { $0 = nil }

        try await property { ctx in
            try await ctx.run(Self())
        }

        let issue = try #require(capturedStateMachineIssue.withLock { $0 })
        let failure = try #require(issue.error as? StateMachineFailure)
        #expect(failure.steps == 3)
        #expect(
            issue.comments.last == """
                Hegel state machine:
                Step 1: increment
                Step 2: increment
                Step 3: increment
                """
        )
    }
}

#if HegelMacros
@StateMachine
private struct MacroPoolMachine: ~Copyable {
    var expected: [Int] = []
    var values = Pool<Int>()

    @Rule
    mutating func add(ctx: borrowing TestCase) throws {
        let value = try ctx.draw(.integers(in: 0...10))
        try values.add(value)
        expected.append(value)
    }

    @Rule
    mutating func reuse() throws {
        let value = try values.draw()
        #expect(expected.contains(value))
    }

    @Invariant
    func `pool mirrors model`() {
        #expect(values.count == expected.count)
        #expect(values.isEmpty == expected.isEmpty)
    }

    @Test(.hegel(settings: stateMachineSettings))
    static func `derives state machine descriptors`() async throws {
        try await property { ctx in
            try await ctx.run(Self())
        }
    }
}
#endif
