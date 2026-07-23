/// A value recipe drawn and shrunk by Hegel.
public struct Generator<Value> {
    var draw: (borrowing TestCase) throws -> Value

    init(draw: @escaping (borrowing TestCase) throws -> Value) {
        self.draw = draw
    }
}

extension Generator where Value == Int {
    /// Generates integers within a closed range.
    public static func integers(
        in range: ClosedRange<Int> = Int.min...Int.max
    ) -> Self {
        Self { testCase in
            try testCase.integer(in: range)
        }
    }
}

extension Generator where Value == Bool {
    /// Generates booleans that are true with the given probability.
    public static func booleans(probability: Double = 0.5) -> Self {
        precondition((0...1).contains(probability))
        return Self { testCase in
            try testCase.boolean(probability: probability)
        }
    }
}

extension Generator {
    /// Generates arrays whose elements are drawn from another generator.
    public static func arrays<Element>(
        of element: Generator<Element>,
        size: ClosedRange<Int> = 0...10,
    ) -> Self where Value == [Element] {
        precondition(size.lowerBound >= 0)
        return Self { testCase in
            try testCase.array(of: element, size: size)
        }
    }
}
