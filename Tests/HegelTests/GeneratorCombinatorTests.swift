import Hegel
import Synchronization
import Testing

private struct FilterFailure: Error {}

private struct SampleFailure: Error {
    var value: Int
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

    var depth: Int {
        switch self {
        case .leaf:
            0
        case .branch(let left, let right):
            1 + max(left.depth, right.depth)
        }
    }
}

private enum Direction: CaseIterable {
    case north
    case east
    case south
    case west
}

@Suite
struct GeneratorCombinatorTests {
    @Test(.hegel(generationSettings()))
    func `builds generators from draw closures`() throws {
        let generator = Gen<(Int, Bool)> { tc in
            let integer = try tc.draw(.integers(in: 10...20))
            let boolean = try tc.draw(.booleans)
            return (integer, boolean)
        }

        try property { tc in
            let (integer, _) = try tc.draw(generator)
            #expect((10...20).contains(integer))
        }
    }

    @Test(.hegel(generationSettings()))
    func `maps filtered enumerable values`() throws {
        let generator = Gen.sampled(from: 0...10)
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 2 }

        try property { tc in
            let value = try tc.draw(generator)
            #expect(value.isMultiple(of: 4))
            #expect((0...20).contains(value))
        }
    }

    @Test(.hegel(generationSettings()))
    func `flatMap can depend on an earlier draw`() throws {
        let generator = Gen.integers(in: 20...22)
            .flatMap { value in
                .constant((value, value + 1))
            }

        try property { tc in
            let (first, second) = try tc.draw(generator)
            #expect(second == first + 1)
        }
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `oneOf ignores absent generators`() throws {
        let generator = Gen.oneOf(
            Gen.sampledIfPresent(from: [Int]()),
            Gen.sampledIfPresent(from: [42]),
            nil,
        )

        try property { tc in
            let value = try tc.draw(generator)
            #expect(value == 42)
        }
    }

    @Test
    func `recognizes empty samples in every ordering mode`() {
        let ordered = Gen<Int>.sampledIfPresent(from: [Int]())
        let sorted = Gen<Int>.sampledIfPresent(
            from: AnyCollection<Int>([]),
            sortedBy: <,
        )

        #expect(ordered == nil)
        #expect(sorted == nil)
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `optional honors deterministic probabilities`() throws {
        let generator = Gen.constant(42)

        try property { tc in
            let none = try tc.draw(generator.optional(probabilityOfSome: 0))
            let some = try tc.draw(generator.optional(probabilityOfSome: 1))
            #expect(none == nil)
            #expect(some == 42)
        }
    }

    @Test(.hegel(generationSettings(testCases: 1)))
    func `filter retries non-enumerable generators`() throws {
        var draws = 0
        let generator = Gen { _ in
            draws += 1
            return draws % 3
        }
        .filter { $0 == 0 }

        try property { tc in
            let value = try tc.draw(generator)
            #expect(value == 0)
        }

        #expect(draws == 3)
    }

    @Test(.hegel(generationSettings(testCases: 3)))
    func `filter propagates predicate errors without leaving an open span`() throws {
        let generator = Gen { _ in 0 }
            .filter { _ throws(FilterFailure) -> Bool in
                throw FilterFailure()
            }

        try property { tc in
            #expect(throws: FilterFailure.self) {
                try tc.draw(generator)
            }
            let followup = try tc.draw(.integers(in: 0...0))
            #expect(followup == 0)
        }
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `generates every CaseIterable case exactly once`() throws {
        let allCases = Set(Direction.allCases)
        let generator = Gen<Set<Direction>>.sets(of: .cases, size: allCases.count)

        try property { tc in
            let cases = try tc.draw(generator)
            #expect(cases == allCases)
        }
    }

    @Test(.hegel(generationSettings()))
    func `supports recursive generator definitions`() throws {
        let recursive = Gen<Tree>.recursive(
            maxDepth: 8,
            maxLeaves: 16,
        ) { tree in
            Gen<(Tree, Tree)>.tuple(tree, tree)
                .map { Tree.branch($0, $1) }
        } leaf: {
            Gen.integers(in: 10...20).map(Tree.leaf)
        }

        try property { tc in
            let tree = try tc.draw(recursive)
            #expect(tree.leaves.allSatisfy { (10...20).contains($0) })
            #expect(tree.leaves.count <= 16)
            #expect(tree.depth <= 8)
        }
    }

    @Suite
    struct OrderedSamplingTests {
        private static let minimum = Mutex<Int?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard let failure = issue.error as? SampleFailure else {
                    return issue
                }
                OrderedSamplingTests.minimum.withLock { $0 = failure.value }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks in collection order`() throws {
            Self.minimum.withLock { $0 = nil }

            try property { tc in
                let value = try tc.draw(.sampled(from: [30, 20, 10]))
                throw SampleFailure(value: value)
            }

            #expect(Self.minimum.withLock { $0 } == 30)
        }
    }

    @Suite
    struct ExplicitlySortedSamplingTests {
        private static let minimum = Mutex<Int?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard let failure = issue.error as? SampleFailure else {
                    return issue
                }
                ExplicitlySortedSamplingTests.minimum.withLock {
                    $0 = failure.value
                }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks in the supplied order`() throws {
            Self.minimum.withLock { $0 = nil }
            let values = AnyCollection([30, 20, 10])

            try property { tc in
                let value = try tc.draw(.sampled(from: values, sortedBy: <))
                throw SampleFailure(value: value)
            }

            #expect(Self.minimum.withLock { $0 } == 10)
        }
    }
}
