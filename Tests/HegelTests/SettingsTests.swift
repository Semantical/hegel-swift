import Hegel
import Testing

@Suite
struct SettingsTests {
    @Test(.hegel.testCases(3).database(.disabled).showStatistics())
    func `event APIs forward observations and surface engine errors`() throws {
        try property { tc in
            let value = try tc.draw(Gen<Int16>.integers)
            try tc.event("observed")
            try tc.event("observed")
            try tc.event(Double(value), label: "value")
            try tc.event(0, label: "value")
            #expect(throws: HegelError.self) { try tc.event(.infinity, label: "invalid") }
            #expect(throws: HegelError.self) { try tc.event(.nan, label: "invalid") }
        }
    }

    @Test
    func `omitted health checks preserve the engine defaults`() {
        let settings = Settings()

        #expect(settings.suppressedHealthChecks == nil)
    }

    @Test
    func `empty health checks can explicitly replace the engine defaults`() {
        var settings = Settings()
        settings.suppressedHealthChecks = []

        #expect(settings.suppressedHealthChecks == [])
        #expect(Settings(suppressedHealthChecks: []).suppressedHealthChecks == [])

        settings.suppressedHealthChecks = nil
        #expect(settings.suppressedHealthChecks == nil)
    }

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
