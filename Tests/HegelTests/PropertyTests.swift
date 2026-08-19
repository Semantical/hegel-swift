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

private let minimalIntegerReproduction = "AAEAAAAACgEAAAAF"
private var minimalIntegerComment: [Comment] {
    ["Hegel reproduction: \(minimalIntegerReproduction)"]
}

@Suite
struct PropertyTests {
    @Test
    func `issue context preserves its first assertion origin`() {
        let context = _HegelIssueContext(fallbackOrigin: "property.swift:1")

        #expect(
            context.record(
                SourceLocation(
                    fileID: "Module/First.swift",
                    filePath: "/tmp/First.swift",
                    line: 12,
                    column: 34,
                )
            )
        )
        #expect(
            !context.record(
                SourceLocation(
                    fileID: "Module/Second.swift",
                    filePath: "/tmp/Second.swift",
                    line: 56,
                    column: 78,
                )
            )
        )
        #expect(context.issueOrigin == "Module/First.swift:12:34")
    }

    @Test
    func `issue context falls back to the property origin`() {
        let context = _HegelIssueContext(fallbackOrigin: "property.swift:1")

        #expect(context.record(nil))
        #expect(context.issueOrigin == "property.swift:1")
    }

    @Test
    func `requires the Hegel trait`() async {
        let error = await #expect(throws: HegelError.self) {
            try await property { _ in }
        }
        #expect(error?.description == "`property` requires the `.hegel` trait.")
    }

    @Test(.hegel(generationSettings(testCases: 3)))
    func `rejects cases that violate assumptions`() async throws {
        var attempts = 0
        var accepted: [Int] = []

        try await property { tc in
            attempts += 1
            let value = try tc.draw(.integers(in: 0...1))
            try tc.assume(value == 1)
            accepted.append(value)
        }

        #expect(attempts > accepted.count)
        #expect(!accepted.isEmpty)
        #expect(accepted.allSatisfy { $0 == 1 })
    }

    @Test(.hegel(generationSettings(testCases: 1)))
    func `propagates cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await property { _ in
                throw CancellationError()
            }
        }
    }

    @Test(.hegel(generationSettings(testCases: 3)))
    func `rejects duplicate targeting labels`() async throws {
        try await property { tc in
            try tc.target(1, label: "size")
            #expect(throws: HegelError.self) {
                try tc.target(2, label: "size")
            }
        }
    }

    @Suite
    struct ThrownErrorTests {
        private static let capturedIssue = Mutex<Issue?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard issue.comments == minimalIntegerComment else {
                    return issue
                }
                ThrownErrorTests.capturedIssue.withLock { $0 = issue }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks thrown errors`() async throws {
            Self.capturedIssue.withLock { $0 = nil }

            try await property { tc in
                let value = try tc.draw(.integers(in: 0...100))
                guard value < 5 else {
                    throw BoundaryFailure(value: value)
                }
            }

            let issue = try #require(Self.capturedIssue.withLock { $0 })
            let failure = try #require(issue.error as? BoundaryFailure)
            #expect(failure.value == 5)
        }
    }

    @Suite
    struct ExpectationTests {
        private static let capturedIssue = Mutex<Issue?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard issue.comments == minimalIntegerComment else {
                    return issue
                }
                ExpectationTests.capturedIssue.withLock { $0 = issue }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks Swift Testing expectations`() async throws {
            Self.capturedIssue.withLock { $0 = nil }

            try await property { tc in
                let value = try tc.draw(.integers(in: 0...100))
                #expect(value < 5)
            }

            let issue = try #require(Self.capturedIssue.withLock { $0 })
            #expect(String(describing: issue).contains("< 5"))
        }
    }

    @Test(.hegel.reproducing(minimalIntegerReproduction))
    func `replays an example configured by the trait`() async throws {
        try await property { tc in
            let value = try tc.draw(.integers(in: 0...100))
            #expect(value == 5)
        }
    }

    @Test(.hegel.reproducing(minimalIntegerReproduction))
    func `reports a rejected replay`() async {
        let error = await #expect(throws: HegelError.self) {
            try await property { tc in
                try tc.assume(false)
            }
        }
        #expect(error?.description == "The reproduced test case was rejected.")
    }

    @Test(.hegel.reproducing(minimalIntegerReproduction))
    func `reports replay draw mismatches`() async {
        let error = await #expect(throws: HegelError.self) {
            try await property { tc in
                _ = try tc.draw(.integers(in: 0...100))
                _ = try tc.draw(.integers(in: 0...100))
            }
        }
        #expect(
            error?.description
                == "The reproduction no longer matches the property's draws."
        )
    }

    @Test(.hegel.reproducing("not-a-reproduction"))
    func `rejects malformed reproductions`() async {
        await #expect(throws: HegelError.self) {
            try await property { _ in }
        }
    }

    @Suite
    struct DatabaseTests {
        private static let capturedIssueCount = Mutex(0)
        private static let propertyCalls = Mutex(0)

        private static var path: String {
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "hegel-swift-\(ProcessInfo.processInfo.processIdentifier)"
                )
                .path
        }

        private static var settings: Settings {
            var settings = searchSettings()
            settings.database = .path(path)
            return settings
        }

        private static func runProperty() async throws {
            try await property { tc in
                propertyCalls.withLock { $0 += 1 }
                let value = try tc.draw(.integers(in: 0...100))
                guard value < 5 else {
                    throw BoundaryFailure(value: value)
                }
            }
        }

        @Test(
            .compactMapIssues { issue in
                guard issue.comments == minimalIntegerComment else {
                    return issue
                }
                DatabaseTests.capturedIssueCount.withLock { $0 += 1 }
                return nil
            },
            .hegel(DatabaseTests.settings),
        )
        func `reuses persisted counterexamples`() async throws {
            try? FileManager.default.removeItem(atPath: Self.path)
            defer {
                try? FileManager.default.removeItem(atPath: Self.path)
            }
            Self.capturedIssueCount.withLock { $0 = 0 }
            Self.propertyCalls.withLock { $0 = 0 }

            try await Self.runProperty()
            let explorationCalls = Self.propertyCalls.withLock { $0 }

            Self.propertyCalls.withLock { $0 = 0 }
            try await Self.runProperty()
            let reuseCalls = Self.propertyCalls.withLock { $0 }

            #expect(reuseCalls < explorationCalls)
            #expect(Self.capturedIssueCount.withLock { $0 } == 2)
        }
    }
}
