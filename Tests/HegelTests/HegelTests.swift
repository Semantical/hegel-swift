import Foundation
import Hegel
import Synchronization
import Testing

private struct BoundaryFailure: Error, CustomStringConvertible {
    var value: Int

    var description: String {
        "Expected a value below 5, got \(value)."
    }
}

private var deterministicSettings: Settings {
    Settings(
        testCases: 200,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
    )
}

private var databasePath: String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("hegel-swift-\(ProcessInfo.processInfo.processIdentifier)")
        .path
}

private var databaseSettings: Settings {
    var settings = deterministicSettings
    settings.database = .path(databasePath)
    return settings
}

private let capturedExpectationIssue = Mutex<Issue?>(nil)
private let capturedErrorIssue = Mutex<Issue?>(nil)
private let capturedDatabaseIssueCount = Mutex(0)
private let databasePropertyCalls = Mutex(0)
private let minimalIntegerReproduction = "AAEAAAAACgEAAAAF"
private var minimalIntegerComment: [Comment] {
    ["Hegel reproduction: \(minimalIntegerReproduction)"]
}

private func runDatabaseProperty() async throws {
    try await property { testCase in
        databasePropertyCalls.withLock { $0 += 1 }
        let value = try testCase.draw(.integers(in: 0...100))
        guard value < 5 else {
            throw BoundaryFailure(value: value)
        }
    }
}

@Test
func `property requires the Hegel trait`() async {
    let error = await #expect(throws: HegelError.self) {
        try await property { _ in }
    }
    #expect(error?.description == "`property` requires the `.hegel` trait.")
}

@Test(.hegel.testCases(3).verbosity(.quiet).database(.disabled).phases([.generate]))
func `configures test cases directly on the trait`() async throws {
    var calls = 0
    try await property { ctx in
        calls += 1
        _ = try ctx.draw(Gen<UInt64>.integers)
    }
    #expect(calls == 3)
}

@Test(.hegel.verbosity(.quiet).database(.disabled).phases([]))
func `can disable every test lifecycle phase`() async throws {
    var calls = 0
    try await property { _ in
        calls += 1
    }
    #expect(calls == 0)
}

@Suite(.hegel(deterministicSettings))
struct HegelTests {
    @Test
    func `draws structured values`() async throws {
        try await property { testCase in
            let values = try testCase.draw(
                .arrays(of: .integers(in: -10...10), size: 0...20)
            )

            guard
                values.count <= 20,
                values.allSatisfy({ (-10...10).contains($0) })
            else {
                throw HegelError("Generated an out-of-range array.")
            }
        }
    }

    @Test
    func `rejects duplicate targeting labels`() async throws {
        try await property { testCase in
            try testCase.target(1, label: "size")
            #expect(throws: HegelError.self) {
                try testCase.target(2, label: "size")
            }
        }
    }

    @Test(
        .compactMapIssues { issue in
            guard issue.comments == minimalIntegerComment else {
                return issue
            }
            capturedErrorIssue.withLock { $0 = issue }
            return nil
        },
        .hegel,
    )
    func `shrinks thrown errors`() async throws {
        capturedErrorIssue.withLock { $0 = nil }

        try await property { testCase in
            let value = try testCase.draw(.integers(in: 0...100))
            guard value < 5 else {
                throw BoundaryFailure(value: value)
            }
        }

        let issue = capturedErrorIssue.withLock { $0 }
        let requiredIssue = try #require(issue)
        let failure = try #require(requiredIssue.error as? BoundaryFailure)
        #expect(failure.value == 5)
    }

    @Test(
        .compactMapIssues { issue in
            guard issue.comments == minimalIntegerComment else {
                return issue
            }
            capturedExpectationIssue.withLock { $0 = issue }
            return nil
        },
        .hegel,
    )
    func `shrinks Swift Testing expectations`() async throws {
        capturedExpectationIssue.withLock { $0 = nil }

        try await property { testCase in
            let value = try testCase.draw(.integers(in: 0...100))
            #expect(value < 5)
        }

        let issue = capturedExpectationIssue.withLock { $0 }
        let requiredIssue = try #require(issue)
        #expect(String(describing: requiredIssue).contains("< 5"))
    }

    @Test(.hegel.reproducing(minimalIntegerReproduction))
    func `replays an example configured by the trait`() async throws {
        try await property { testCase in
            let value = try testCase.draw(.integers(in: 0...100))
            #expect(value == 5)
        }
    }

    @Test(
        .compactMapIssues { issue in
            guard issue.comments == minimalIntegerComment else {
                return issue
            }
            capturedDatabaseIssueCount.withLock { $0 += 1 }
            return nil
        },
        .hegel(databaseSettings),
    )
    func `reuses persisted counterexamples`() async throws {
        try? FileManager.default.removeItem(atPath: databasePath)
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }
        capturedDatabaseIssueCount.withLock { $0 = 0 }
        databasePropertyCalls.withLock { $0 = 0 }

        try await runDatabaseProperty()
        let explorationCalls = databasePropertyCalls.withLock { $0 }

        databasePropertyCalls.withLock { $0 = 0 }
        try await runDatabaseProperty()
        let reuseCalls = databasePropertyCalls.withLock { $0 }

        #expect(reuseCalls < explorationCalls)
        #expect(capturedDatabaseIssueCount.withLock { $0 } == 2)
    }
}
