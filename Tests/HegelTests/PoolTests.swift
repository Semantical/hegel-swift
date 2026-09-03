import Hegel
import Testing

@Suite
struct PoolTests {
    @Test(.hegel(generationSettings(testCases: 10)))
    func `explicit operations work outside a state machine`() throws {
        try property { tc in
            var values = Pool<Int>()
            try tc.add(1, to: &values)
            let drawn = try tc.draw(from: values)
            let taken = try tc.take(from: &values)
            #expect(drawn == 1)
            #expect(taken == 1)
        }
    }

    @Test(.hegel(searchSettings()))
    func `tracks reusable and consumed values`() async throws {
        try await property { tc in
            try await tc.run(PoolMachine())
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
            let drawn = try tc.draw(from: machine.values)
            #expect(machine.expected.contains(drawn))

            try tc.add(value, to: &machine.values)
            machine.expected.append(value)

            let taken = try tc.take(from: &machine.values)
            let index = try #require(machine.expected.firstIndex(of: taken))
            machine.expected.remove(at: index)
        }

        rule("reuse a value") { machine, tc in
            let value = try tc.draw(from: machine.values)
            #expect(machine.expected.contains(value))
        }

        rule("consume a value") { machine, tc in
            let value = try tc.take(from: &machine.values)
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
