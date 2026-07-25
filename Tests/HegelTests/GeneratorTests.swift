import Hegel
import HegelTesting
import Synchronization
import Testing

private struct ArrayLengthFailure: Error {
    var values: [Int]
}

private indirect enum Tree {
    case leaf(Int)
    case branch(Tree, Tree)

    var leaves: [Int] {
        switch self {
        case .leaf(let value):
            [value]
        case .branch(let left, let right):
            left.leaves + right.leaves
        }
    }
}

private var generatorSettings: Settings {
    Settings(
        testCases: 200,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
    )
}

private let capturedArrayIssue = Mutex<Issue?>(nil)

@Suite(.hegel(settings: generatorSettings))
struct GeneratorTests {
    @Test
    func `composes generators`() async throws {
        let smallEvens = Gen<Int>.sampled(from: 0...10)
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 2 }
        let dependent = Gen<Int>.integers(in: 20...22)
            .flatMap { .just($0 + 1) }
        let generator = Gen<Int>.oneOf(smallEvens, dependent)
            .optional(probabilityOfSome: 0.8)

        try await property { testCase in
            guard let value = try testCase.draw(generator) else {
                return
            }
            #expect(value.isMultiple(of: 4) || (21...23).contains(value))
        }
    }

    @Test
    func `supports recursive generator definitions`() async throws {
        let tree = Gen<Tree>.deferred()
        let recursive = tree.generator
        let branch = Gen<(Tree, Tree)>.tuple(recursive, recursive)
            .map { Tree.branch($0, $1) }
        tree.set(
            .oneOf(
                Gen<Int>.integers(in: 10...20).map(Tree.leaf),
                branch,
            )
        )

        try await property { testCase in
            let tree = try testCase.draw(recursive)
            #expect(tree.leaves.allSatisfy { (10...20).contains($0) })
        }
    }

    @Test
    func `generates scalar values across their native ranges`() async throws {
        try await property { testCase in
            let signed = try testCase.draw(Gen<Int8>.integers(in: -128 ... -100))
            let unsigned = try testCase.draw(
                Gen<UInt64>.integers(in: (UInt64.max - 100)...UInt64.max)
            )
            let float = try testCase.draw(
                Gen<Float>.floats(in: -10...10)
            )
            let double = try testCase.draw(
                Gen<Double>.floats(in: -10...10)
            )

            #expect((-128 ... -100).contains(signed))
            #expect(((UInt64.max - 100)...UInt64.max).contains(unsigned))
            #expect((-10...10).contains(float))
            #expect((-10...10).contains(double))
        }
    }

    @Test
    func `generates bytes strings characters and fixed products`() async throws {
        let tuple = Gen<(UInt8, String)>.tuple(
            Gen<UInt8>.integers(in: 200...255),
            .strings(size: 2...8),
        )
        let inlineArray = Gen<InlineArray<4, UInt8>>.inlineArrays(
            of: .integers(in: 200...255)
        )

        try await property { testCase in
            let bytes = try testCase.draw(Gen<[UInt8]>.bytes(size: 3...12))
            let (integer, string) = try testCase.draw(tuple)
            let character = try testCase.draw(Gen<Character>.characters())
            let fixed = try testCase.draw(inlineArray)

            #expect((3...12).contains(bytes.count))
            #expect((200...255).contains(integer))
            #expect((2...8).contains(string.unicodeScalars.count))
            #expect(character.unicodeScalars.count == 1)
            #expect(fixed.indices.allSatisfy { (200...255).contains(fixed[$0]) })
        }
    }

    @Test
    func `draws unordered collections without replacement`() async throws {
        let keys = Gen<Int>.sampled(from: [1, 1, 2, 3])

        try await property { testCase in
            let set = try testCase.draw(
                Gen<Set<Int>>.sets(of: keys, size: 3...8)
            )
            let dictionary = try testCase.draw(
                Gen<[Int: Bool]>.dictionaries(
                    keys: keys,
                    values: .booleans(),
                    size: 3...8,
                )
            )
            let generatedSet = try testCase.draw(
                Gen<Set<Int>>.sets(
                    of: .integers(in: 1...3),
                    size: 3...3,
                )
            )

            #expect(set == [1, 2, 3])
            #expect(Set(dictionary.keys) == [1, 2, 3])
            #expect(generatedSet == [1, 2, 3])
        }
    }

    @Test
    func `does not draw values for rejected dictionary keys`() async throws {
        let valueDraws = Mutex(0)
        let values = Gen<Int>.integers().map { value in
            valueDraws.withLock { $0 += 1 }
            return value
        }

        try await property { testCase in
            valueDraws.withLock { $0 = 0 }
            let dictionary = try testCase.draw(
                Gen<[Int: Int]>.dictionaries(
                    keys: .integers(in: 0...0),
                    values: values,
                    size: 1...3,
                )
            )

            #expect(valueDraws.withLock { $0 } == dictionary.count)
        }
    }

    @Test(
        .compactMapIssues { issue in
            guard issue.error is ArrayLengthFailure else {
                return issue
            }
            capturedArrayIssue.withLock { $0 = issue }
            return nil
        },
        .hegel,
    )
    func `shrinks collection structure and elements`() async throws {
        capturedArrayIssue.withLock { $0 = nil }

        try await property { testCase in
            let values = try testCase.draw(
                Gen<[Int]>.arrays(
                    of: .integers(in: 0...100),
                    size: 0...10,
                )
            )
            guard values.count < 2 else {
                throw ArrayLengthFailure(values: values)
            }
        }

        let issue = try #require(capturedArrayIssue.withLock { $0 })
        let failure = try #require(issue.error as? ArrayLengthFailure)
        #expect(failure.values == [0, 0])
    }
}
