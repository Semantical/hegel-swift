import Hegel
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

@Suite
struct HegelTests {
    @Test
    func `draws structured values`() async throws {
        try await Hegel.test(settings: deterministicSettings) { testCase in
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
    func `shrinks and replays a failure`() async throws {
        let failure = await #expect(throws: PropertyFailure.self) {
            try await Hegel.test(settings: deterministicSettings) {
                testCase in
                let value = try testCase.draw(.integers(in: 0...100))
                guard value < 5 else {
                    throw BoundaryFailure(value: value)
                }
            }
        }
        let propertyFailure = try #require(failure)

        #expect(propertyFailure.cause == BoundaryFailure(value: 5).description)

        let replayed = await #expect(throws: BoundaryFailure.self) {
            try await Hegel.test(
                reproducing: propertyFailure.reproduction,
                settings: deterministicSettings,
            ) { testCase in
                let value = try testCase.draw(.integers(in: 0...100))
                guard value < 5 else {
                    throw BoundaryFailure(value: value)
                }
            }
        }

        #expect(try #require(replayed).value == 5)
    }
}
