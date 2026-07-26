import Hegel
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

private enum Direction: CaseIterable {
    case north
    case east
    case south
    case west
}

private var generatorSettings: Settings {
    Settings(
        testCases: 200,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
    )
}

private let capturedArrayFailure = Mutex<ArrayLengthFailure?>(nil)

@Suite(.hegel(settings: generatorSettings))
struct GeneratorTests {
    @Test
    func `composes generators`() async throws {
        let smallEvens = Gen<Int>.sampled(from: 0...10)
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 2 }
        let dependent = Gen<Int>.integers(in: 20...22)
            .flatMap { .constant($0 + 1) }
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
    func `builds generators from draw closures`() async throws {
        let generator = Gen<(Int, Bool)> { ctx in
            let integer = try ctx.draw(.integers(in: 10...20))
            let boolean = try ctx.draw(.booleans)
            return (integer, boolean)
        }

        try await property { ctx in
            let (integer, _) = try ctx.draw(generator)
            #expect((10...20).contains(integer))
        }
    }

    @Test
    func `generates CaseIterable cases`() async throws {
        let allCases = Set(Direction.allCases)
        let generator = Gen<Set<Direction>>.sets(of: .cases, size: allCases.count)

        try await property { ctx in
            let cases = try ctx.draw(generator)
            #expect(cases == allCases)
        }
    }

    @Test
    func `supports recursive generator definitions`() async throws {
        let recursive = Gen<Tree>.recursive { tree in
            let branch = Gen<(Tree, Tree)>.tuple(tree, tree)
                .map { Tree.branch($0, $1) }
            return .oneOf(
                Gen<Int>.integers(in: 10...20).map(Tree.leaf),
                branch,
            )
        }

        try await property { testCase in
            let tree = try testCase.draw(recursive)
            #expect(tree.leaves.allSatisfy { (10...20).contains($0) })
        }
    }

    @Test
    func `generates scalar values across their native ranges`() async throws {
        try await property { testCase in
            let signed = try testCase.draw(.integers(in: -128 ... -100))
            let halfOpenInteger = try testCase.draw(.integers(in: -10..<10))
            let lowerBoundedInteger = try testCase.draw(.integers(in: 10...))
            let upperBoundedInteger = try testCase.draw(.integers(in: ...10))
            let exclusiveUpperInteger = try testCase.draw(.integers(in: ..<10))
            let unsigned = try testCase.draw(
                .integers(UInt64.self, in: (UInt64.max - 100)...UInt64.max)
            )
            let float = try testCase.draw(.floats(in: -10..<10))
            let double = try testCase.draw(.doubles(in: -10..<10))
            let upperBoundedFloat = try testCase.draw(.floats(in: ...10))
            let exclusiveUpperDouble = try testCase.draw(.doubles(in: ..<10))

            #expect((-128 ... -100).contains(signed))
            #expect((-10..<10).contains(halfOpenInteger))
            #expect(lowerBoundedInteger >= 10)
            #expect(upperBoundedInteger <= 10)
            #expect(exclusiveUpperInteger < 10)
            #expect(((UInt64.max - 100)...UInt64.max).contains(unsigned))
            #expect((-10..<10).contains(float))
            #expect((-10..<10).contains(double))
            #expect(upperBoundedFloat <= 10)
            #expect(exclusiveUpperDouble < 10)
        }
    }

    @Test
    func `generates bytes strings characters and fixed products`() async throws {
        let tuple = Gen<(UInt8, String)>.tuple(
            Gen.integers(UInt8.self, in: 200...255),
            .strings(size: ...8),
        )
        let inlineArray = Gen<[4 of UInt8]>.inlineArrays(
            of: .integers(in: 200...255)
        )

        try await property { testCase in
            let bytes = try testCase.draw(.bytes(size: ..<13))
            let (integer, string) = try testCase.draw(tuple)
            let character = try testCase.draw(.characters)
            let fixed = try testCase.draw(inlineArray)

            #expect(bytes.count < 13)
            #expect((200...255).contains(integer))
            #expect(string.unicodeScalars.count <= 8)
            #expect(character.unicodeScalars.count == 1)
            #expect(fixed.indices.allSatisfy { (200...255).contains(fixed[$0]) })
        }
    }

    @Test
    func `supports lower bounded generator sizes`() async throws {
        let keys = Gen<Int>.sampled(from: 0..<20)

        try await property { testCase in
            let bytes = try testCase.draw(.bytes(size: 11...))
            let string = try testCase.draw(.strings(size: 11...))
            let array = try testCase.draw(.arrays(of: .booleans, size: 11...))
            let set = try testCase.draw(.sets(of: keys, size: 11...))
            let dictionary = try testCase.draw(
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

    @Test
    func `draws unordered collections without replacement`() async throws {
        let keys = Gen<Int>.sampled(from: [1, 1, 2, 3])

        try await property { testCase in
            let set = try testCase.draw(.sets(of: keys, size: 3..<9))
            let dictionary = try testCase.draw(
                .dictionaries(
                    keys: keys,
                    values: .booleans,
                    size: 3..<9,
                )
            )
            let generatedSet = try testCase.draw(
                .sets(of: .integers(in: 1...3), size: 3)
            )

            #expect(set == [1, 2, 3])
            #expect(Set(dictionary.keys) == [1, 2, 3])
            #expect(generatedSet == [1, 2, 3])
        }
    }

    @Test
    func `does not draw values for rejected dictionary keys`() async throws {
        let valueDraws = Mutex(0)
        let values = Gen<Int>.integers.map { value in
            valueDraws.withLock { $0 += 1 }
            return value
        }

        try await property { testCase in
            valueDraws.withLock { $0 = 0 }
            let dictionary = try testCase.draw(
                .dictionaries(
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
            guard let failure = issue.error as? ArrayLengthFailure else {
                return issue
            }
            capturedArrayFailure.withLock { $0 = failure }
            return nil
        },
        .hegel,
    )
    func `shrinks collection structure and elements`() async throws {
        capturedArrayFailure.withLock { $0 = nil }

        try await property { testCase in
            let values = try testCase.draw(
                .arrays(of: .integers(in: 0...100), size: 0...10)
            )
            guard values.count < 2 else {
                throw ArrayLengthFailure(values: values)
            }
        }

        let failure = try #require(capturedArrayFailure.withLock { $0 })
        #expect(failure.values == [0, 0])
    }
}
