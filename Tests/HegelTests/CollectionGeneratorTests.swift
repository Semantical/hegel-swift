import Hegel
import Synchronization
import Testing

@Suite
struct CollectionGeneratorTests {
    @Test(.hegel(generationSettings(testCases: 50)))
    func `variable-sized generators honor lower bounds`() async throws {
        let keys = Gen.sampled(from: 0..<20)

        try await property { tc in
            let bytes = try tc.draw(.bytes(size: 11...))
            let string = try tc.draw(.strings(size: 11...))
            let array = try tc.draw(.arrays(of: .booleans, size: 11...))
            let set = try tc.draw(.sets(of: keys, size: 11...))
            let dictionary = try tc.draw(
                .dictionaries(
                    keys: keys,
                    values: .booleans,
                    size: 11...,
                )
            )

            #expect(bytes.count >= 11)
            #expect(string.unicodeScalars.count >= 11)
            #expect(array.count >= 11)
            #expect(set.count >= 11)
            #expect(dictionary.count >= 11)
        }
    }

    @Test(.hegel(generationSettings(testCases: 50)))
    func `byte and string generators honor upper bounds`() async throws {
        try await property { tc in
            let bytes = try tc.draw(.bytes(size: ..<13))
            let string = try tc.draw(.strings(size: ...8))

            #expect(bytes.count < 13)
            #expect(string.unicodeScalars.count <= 8)
        }
    }

    @Test(.hegel(generationSettings()))
    func `character generators produce one Unicode scalar`() async throws {
        try await property { tc in
            let character = try tc.draw(.characters)
            #expect(character.unicodeScalars.count == 1)
        }
    }

    @Test(.hegel(generationSettings()))
    func `fixed product generators preserve their element domains`() async throws {
        let tuple = Gen<(UInt8, String)>.tuple(
            Gen.integers(UInt8.self, in: 200...255),
            .strings(size: ...8),
        )
        let inlineArray = Gen<[4 of UInt8]>.inlineArrays(
            of: .integers(in: 200...255)
        )

        try await property { tc in
            let (integer, string) = try tc.draw(tuple)
            let fixed = try tc.draw(inlineArray)

            #expect((200...255).contains(integer))
            #expect(string.unicodeScalars.count <= 8)
            #expect(fixed.indices.allSatisfy { (200...255).contains(fixed[$0]) })
        }
    }

    @Test(.hegel(generationSettings()))
    func `unordered collections use each finite-domain value at most once`() async throws {
        let keys = Gen.sampled(from: [1, 1, 2, 3])

        try await property { tc in
            let set = try tc.draw(.sets(of: keys, size: 3..<9))
            let dictionary = try tc.draw(
                .dictionaries(
                    keys: keys,
                    values: .booleans,
                    size: 3..<9,
                )
            )
            let generatedSet = try tc.draw(
                .sets(of: .integers(in: 1...3), size: 3)
            )

            #expect(set == [1, 2, 3])
            #expect(Set(dictionary.keys) == [1, 2, 3])
            #expect(generatedSet == [1, 2, 3])
        }
    }

    @Test(.hegel(generationSettings()))
    func `does not draw values for rejected dictionary keys`() async throws {
        let valueDraws = Mutex(0)
        let values = Gen.integers.map { value in
            valueDraws.withLock { $0 += 1 }
            return value
        }

        try await property { tc in
            valueDraws.withLock { $0 = 0 }
            let dictionary = try tc.draw(
                .dictionaries(
                    keys: .integers(in: 0...0),
                    values: values,
                    size: 1...3,
                )
            )

            #expect(valueDraws.withLock { $0 } == dictionary.count)
        }
    }

    @Suite
    struct ShrinkingTests {
        private struct Failure: Error {
            var values: [Int]
        }

        private static let capturedFailure = Mutex<Failure?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard let failure = issue.error as? Failure else {
                    return issue
                }
                ShrinkingTests.capturedFailure.withLock { $0 = failure }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks collection structure and elements`() async throws {
            Self.capturedFailure.withLock { $0 = nil }

            try await property { tc in
                let values = try tc.draw(
                    .arrays(of: .integers(in: 0...100), size: 0...10)
                )
                guard values.count < 2 else {
                    throw Failure(values: values)
                }
            }

            let failure = try #require(Self.capturedFailure.withLock { $0 })
            #expect(failure.values == [0, 0])
        }
    }
}
