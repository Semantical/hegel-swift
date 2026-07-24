import Hegel
import HegelTesting
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

private struct PoolMachine: ~Copyable, StateMachine {
    var expected: [Int] = []
    var values = Pool<Int>()

    static var rules: Rules {
        rule("add duplicate values") { machine, testCase in
            let value = try testCase.draw(.integers(in: 0...10))
            try testCase.add(value, to: &machine.values)
            try testCase.add(value, to: &machine.values)
            machine.expected.append(contentsOf: [value, value])

            let reused = try testCase.draw(from: machine.values)
            #expect(machine.expected.contains(reused))

            let taken = try testCase.take(from: &machine.values)
            let index = try #require(machine.expected.firstIndex(of: taken))
            machine.expected.remove(at: index)
        }

        rule("reuse a value") { machine, testCase in
            let value = try testCase.draw(from: machine.values)
            #expect(machine.expected.contains(value))
        }

        rule("consume a value") { machine, testCase in
            let value = try testCase.take(from: &machine.values)
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
        try await Hegel.test { testCase in
            try await testCase.run(Self())
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

        try await Hegel.test { testCase in
            try await testCase.run(Self())
        }

        let issue = try #require(capturedStateMachineIssue.withLock { $0 })
        let failure = try #require(issue.error as? StateMachineFailure)
        #expect(failure.steps == 3)
    }
}
