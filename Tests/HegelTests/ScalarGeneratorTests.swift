import Hegel
import Testing

@Suite
struct ScalarGeneratorTests {
    @Test(.hegel(generationSettings(testCases: 50)))
    func `integer generators honor bounded ranges`() throws {
        try property { tc in
            let closed = try tc.draw(.integers(in: -128 ... -100))
            let halfOpen = try tc.draw(.integers(in: -10..<10))
            let unsigned = try tc.draw(
                .integers(UInt64.self, in: (UInt64.max - 100)...UInt64.max)
            )

            #expect((-128 ... -100).contains(closed))
            #expect((-10..<10).contains(halfOpen))
            #expect(((UInt64.max - 100)...UInt64.max).contains(unsigned))
        }
    }

    @Test(.hegel(generationSettings(testCases: 50)))
    func `integer generators honor one-sided ranges`() throws {
        try property { tc in
            let lowerBounded = try tc.draw(.integers(in: 10...))
            let upperBounded = try tc.draw(.integers(in: ...10))
            let exclusiveUpper = try tc.draw(.integers(in: ..<10))

            #expect(lowerBounded >= 10)
            #expect(upperBounded <= 10)
            #expect(exclusiveUpper < 10)
        }
    }

    @Test(.hegel(generationSettings(testCases: 50)))
    func `floating-point generators honor range endpoints`() throws {
        try property { tc in
            let float = try tc.draw(.floats(in: -10..<10))
            let double = try tc.draw(.doubles(in: -10..<10))
            let upperBoundedFloat = try tc.draw(.floats(in: ...10))
            let exclusiveUpperDouble = try tc.draw(.doubles(in: ..<10))

            #expect((-10..<10).contains(float))
            #expect((-10..<10).contains(double))
            #expect(upperBoundedFloat <= 10)
            #expect(exclusiveUpperDouble < 10)
        }
    }
}
