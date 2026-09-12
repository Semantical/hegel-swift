import Hegel
import Testing

@Suite
struct SettingsTests {
    @Test(
        .hegel
            .testCases(3)
            .verbosity(.quiet)
            .database(.disabled)
            .phases([.generate])
    )
    func `configures the number of test cases`() throws {
        var calls = 0

        try property { tc in
            calls += 1
            _ = try tc.draw(Gen<UInt64>.integers)
        }

        #expect(calls == 3)
    }

    @Test(.hegel.verbosity(.quiet).database(.disabled).phases([]))
    func `can disable every lifecycle phase`() throws {
        var calls = 0

        try property { _ in
            calls += 1
        }

        #expect(calls == 0)
    }

    @Test(
        .hegel
            .testCases(10)
            .verbosity(.quiet)
            .seed(0xC0FFEE)
            .database(.disabled)
            .phases([.generate])
    )
    func `a fixed seed reproduces generated choices`() throws {
        var first: [UInt64] = []
        var second: [UInt64] = []

        try property { tc in
            first.append(try tc.draw(.integers))
        }
        try property { tc in
            second.append(try tc.draw(.integers))
        }

        #expect(first == second)
    }

    @Test(
        .hegel
            .testCases(10)
            .verbosity(.quiet)
            .derandomize(true)
            .database(.disabled)
            .phases([.generate])
    )
    func `derandomization stabilizes unseeded runs`() throws {
        var first: [UInt64] = []
        var second: [UInt64] = []

        try property { tc in
            first.append(try tc.draw(.integers))
        }
        try property { tc in
            second.append(try tc.draw(.integers))
        }

        #expect(first == second)
    }
}

@Suite(.hegel.testCases(3).seed(42).database(.disabled).phases([.generate]))
struct InheritedSettingsTests {
    @Test(.hegel.verbosity(.quiet))
    func `a test override preserves unrelated suite settings`() throws {
        var first: [UInt64] = []
        var second: [UInt64] = []
        try property { first.append(try $0.draw(.integers)) }
        try property { second.append(try $0.draw(.integers)) }
        #expect(first.count == 3)
        #expect(first == second)
    }

    @Suite(.hegel.testCases(5))
    struct Nested {
        @Test(.hegel.verbosity(.quiet))
        func `nested suite overrides compose with test overrides`() throws {
            var calls = 0
            try property { tc in
                calls += 1
                _ = try tc.draw(Gen<UInt64>.integers)
            }
            #expect(calls == 5)
        }

        @Test(.hegel.testCases(2))
        func `the test wins over both suite layers`() throws {
            var calls = 0
            try property { tc in
                calls += 1
                _ = try tc.draw(Gen<UInt64>.integers)
            }
            #expect(calls == 2)
        }
    }
}
