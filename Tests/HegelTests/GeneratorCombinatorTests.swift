import Hegel
import Testing

private struct FilterFailure: Error {}

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

@Suite
struct GeneratorCombinatorTests {
    @Test(.hegel(generationSettings()))
    func `builds generators from draw closures`() async throws {
        let generator = Gen<(Int, Bool)> { tc in
            let integer = try tc.draw(.integers(in: 10...20))
            let boolean = try tc.draw(.booleans)
            return (integer, boolean)
        }

        try await property { tc in
            let (integer, _) = try tc.draw(generator)
            #expect((10...20).contains(integer))
        }
    }

    @Test(.hegel(generationSettings()))
    func `maps filtered enumerable values`() async throws {
        let generator = Gen.sampled(from: 0...10)
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 2 }

        try await property { tc in
            let value = try tc.draw(generator)
            #expect(value.isMultiple(of: 4))
            #expect((0...20).contains(value))
        }
    }

    @Test(.hegel(generationSettings()))
    func `flatMap can depend on an earlier draw`() async throws {
        let generator = Gen.integers(in: 20...22)
            .flatMap { value in
                .constant((value, value + 1))
            }

        try await property { tc in
            let (first, second) = try tc.draw(generator)
            #expect(second == first + 1)
        }
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `oneOf ignores absent generators`() async throws {
        let generator = Gen.oneOf(nil, .constant(42), nil)

        try await property { tc in
            let value = try tc.draw(generator)
            #expect(value == 42)
        }
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `optional honors deterministic probabilities`() async throws {
        let generator = Gen.constant(42)

        try await property { tc in
            let none = try tc.draw(generator.optional(probabilityOfSome: 0))
            let some = try tc.draw(generator.optional(probabilityOfSome: 1))
            #expect(none == nil)
            #expect(some == 42)
        }
    }

    @Test(.hegel(generationSettings(testCases: 1)))
    func `filter retries non-enumerable generators`() async throws {
        var draws = 0
        let generator = Gen { _ in
            draws += 1
            return draws % 3
        }
        .filter { $0 == 0 }

        try await property { tc in
            let value = try tc.draw(generator)
            #expect(value == 0)
        }

        #expect(draws == 3)
    }

    @Test(.hegel(generationSettings(testCases: 3)))
    func `filter propagates predicate errors without leaving an open span`() async throws {
        let generator = Gen { _ in 0 }
            .filter { _ throws(FilterFailure) -> Bool in
                throw FilterFailure()
            }

        try await property { tc in
            #expect(throws: FilterFailure.self) {
                try tc.draw(generator)
            }
            let followup = try tc.draw(.integers(in: 0...0))
            #expect(followup == 0)
        }
    }

    @Test(.hegel(generationSettings(testCases: 10)))
    func `generates every CaseIterable case exactly once`() async throws {
        let allCases = Set(Direction.allCases)
        let generator = Gen<Set<Direction>>.sets(of: .cases, size: allCases.count)

        try await property { tc in
            let cases = try tc.draw(generator)
            #expect(cases == allCases)
        }
    }

    @Test(.hegel(generationSettings()))
    func `supports recursive generator definitions`() async throws {
        let recursive = Gen<Tree>.recursive { tree in
            let branch = Gen<(Tree, Tree)>.tuple(tree, tree)
                .map { Tree.branch($0, $1) }
            return .oneOf(
                Gen.integers(in: 10...20).map(Tree.leaf),
                branch,
            )
        }

        try await property { tc in
            let tree = try tc.draw(recursive)
            #expect(tree.leaves.allSatisfy { (10...20).contains($0) })
        }
    }
}
