import Hegel
import Testing

@Suite
struct PoolTests {
    @Test(.hegel(generationSettings(testCases: 10)))
    func `context-free operations require a state machine`() async throws {
        try await property { tc in
            var values = Pool<Int>()
            #expect(throws: HegelError.self) {
                try values.add(1)
            }

            try tc.add(1, to: &values)
            let drawn = try tc.draw(from: values)
            let taken = try tc.take(from: &values)
            #expect(drawn == 1)
            #expect(taken == 1)
            #expect(throws: HegelError.self) {
                try values.draw()
            }
        }
    }

    @Test(.hegel(searchSettings()))
    func `tracks reusable and consumed values`() async throws {
        try await property { tc in
            try await tc.run(PoolMachine())
        }
    }

    @Test(.hegel(generationSettings(testCases: 50)))
    func `cannot be reused across state-machine runs`() async throws {
        try await property { tc in
            let box = PoolBox()
            try await tc.run(PoolBindingMachine(box: box))
            try tc.assume(!box.values.isEmpty)
            try await tc.run(PoolReuseMachine(box: box))
        }
    }
}

private struct PoolMachine: ~Copyable, StateMachine {
    var expected: [Int] = []
    var values = Pool<Int>()

    static var rules: Rules {
        rule("add duplicate values") { machine, tc in
            let value = try tc.draw(.integers(in: 0...10))

            try tc.add(value, to: &machine.values)
            machine.expected.append(value)
            let drawn = try machine.values.draw()
            #expect(machine.expected.contains(drawn))

            try machine.values.add(value)
            machine.expected.append(value)

            let taken = try tc.take(from: &machine.values)
            let index = try #require(machine.expected.firstIndex(of: taken))
            machine.expected.remove(at: index)
        }

        rule("reuse a value") { machine, _ in
            let value = try machine.values.draw()
            #expect(machine.expected.contains(value))
        }

        rule("consume a value") { machine, _ in
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
}

private final class PoolBox {
    var values = Pool<Int>()
}

private struct PoolBindingMachine: StateMachine {
    var box: PoolBox

    static var rules: Rules {
        rule("add") { machine, tc in
            try tc.add(1, to: &machine.box.values)
        }
    }
}

private struct PoolReuseMachine: StateMachine {
    var box: PoolBox

    static var rules: Rules {
        rule("no-op") { _, _ in }
    }

    static var invariants: Invariants {
        invariant("reject reuse") { machine in
            let error = #expect(throws: HegelError.self) {
                try machine.box.values.draw()
            }
            #expect(
                error?.description
                    == "A pool cannot be reused across state-machine runs."
            )
        }
    }
}
