import CHegel

/// A value recipe drawn and shrunk by Hegel.
public struct Generator<Value> {
    var draw: (borrowing TestCase) throws -> Value

    // A known, practically enumerable domain lets unordered collections draw
    // without replacement. `nil` means "not enumerable", not "infinite".
    var enumeratedValues: [Value]?

    init(
        enumeratedValues: [Value]? = nil,
        draw: @escaping (borrowing TestCase) throws -> Value,
    ) {
        self.draw = draw
        self.enumeratedValues = enumeratedValues
    }
}

// MARK: - Composition

extension Generator {
    /// Creates a forward-reference definition for recursive generators.
    public static func deferred() -> DeferredGeneratorDefinition<Value> {
        DeferredGeneratorDefinition()
    }

    /// Always generates the given value.
    public static func just(_ value: Value) -> Self {
        Self(enumeratedValues: [value]) { _ in value }
    }

    /// Generates one of the supplied values.
    public static func sampled(
        from values: some Collection<Value>
    ) -> Self {
        let values = Array(values)
        precondition(!values.isEmpty)
        return Self(enumeratedValues: values) { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_SAMPLED_FROM.rawValue)) {
                let index = try testCase.integer(in: 0...(values.count - 1))
                return values[index]
            }
        }
    }

    /// Generates a value from one of the supplied generators.
    public static func oneOf(_ generators: Self...) -> Self {
        oneOf(generators)
    }

    /// Generates a value from one of the supplied generators.
    public static func oneOf(_ generators: [Self]) -> Self {
        precondition(!generators.isEmpty)
        let domains = generators.compactMap(\.enumeratedValues)
        let enumeratedValues =
            domains.count == generators.count
            ? domains.flatMap { $0 }
            : nil
        return Self(enumeratedValues: enumeratedValues) { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_ONE_OF.rawValue)) {
                let index = try testCase.integer(in: 0...(generators.count - 1))
                return try generators[index].draw(testCase)
            }
        }
    }

    /// Transforms generated values without changing their choices.
    public func map<NewValue>(
        _ transform: @escaping (Value) throws -> NewValue
    ) -> Generator<NewValue> {
        Generator<NewValue>(
            enumeratedValues: try? enumeratedValues?.map(transform)
        ) { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_MAPPED.rawValue)) {
                try transform(draw(testCase))
            }
        }
    }

    /// Chooses a subsequent generator from the generated value.
    public func flatMap<NewValue>(
        _ transform: @escaping (Value) throws -> Generator<NewValue>
    ) -> Generator<NewValue> {
        Generator<NewValue> { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_FLAT_MAP.rawValue)) {
                let generator = try transform(draw(testCase))
                return try generator.draw(testCase)
            }
        }
    }

    /// Keeps only values accepted by the predicate.
    public func filter(
        _ predicate: @escaping (Value) throws -> Bool
    ) -> Self {
        let enumeratedValues = try? enumeratedValues?.filter(predicate)
        if let enumeratedValues {
            guard !enumeratedValues.isEmpty else {
                return Self(enumeratedValues: []) { _ in
                    throw TestControl.invalid
                }
            }
            return .sampled(from: enumeratedValues)
        }
        return Self { testCase in
            try testCase.filtered(self, by: predicate)
        }
    }

    /// Generates either no value or a value from this generator.
    public func optional(probabilityOfSome probability: Double = 0.5) -> Generator<Value?> {
        precondition((0...1).contains(probability))
        return Generator<Value?>(
            enumeratedValues: enumeratedValues.map { [nil] + $0.map(Optional.some) }
        ) { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_OPTIONAL.rawValue)) {
                guard try testCase.boolean(probability: probability) else {
                    return nil
                }
                return try draw(testCase)
            }
        }
    }
}

// MARK: - Scalar values

extension Generator where Value: FixedWidthInteger {
    /// Generates integers within a closed range.
    public static func integers(
        in range: ClosedRange<Value> = Value.min...Value.max
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
        return Self(enumeratedValues: [false, true]) { testCase in
            try testCase.boolean(probability: probability)
        }
    }
}

extension Generator where Value == Float {
    /// Generates floating-point values, including special values when unbounded.
    public static func floats(
        in range: ClosedRange<Float>? = nil,
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        Self { testCase in
            try testCase.float(
                in: range,
                allowingNaN: allowingNaN ?? (range == nil),
                allowingInfinity: allowingInfinity ?? (range == nil),
                allowingSubnormal: allowingSubnormal,
            )
        }
    }
}

extension Generator where Value == Double {
    /// Generates floating-point values, including special values when unbounded.
    public static func floats(
        in range: ClosedRange<Double>? = nil,
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        Self { testCase in
            try testCase.float(
                in: range,
                allowingNaN: allowingNaN ?? (range == nil),
                allowingInfinity: allowingInfinity ?? (range == nil),
                allowingSubnormal: allowingSubnormal,
            )
        }
    }
}

extension Generator where Value == [UInt8] {
    /// Generates byte strings whose sizes fall within the given range.
    public static func bytes(size: ClosedRange<Int> = 0...10) -> Self {
        validate(size: size)
        return Self { testCase in
            try testCase.bytes(size: size)
        }
    }
}

extension Generator where Value == String {
    /// Generates Unicode strings whose scalar counts fall within the given range.
    public static func strings(size: ClosedRange<Int> = 0...10) -> Self {
        validate(size: size)
        let specification = Result {
            try StringGeneratorHandle.text(size: size)
        }
        return Self { testCase in
            try testCase.string(using: specification.get())
        }
    }
}

extension Generator where Value == Unicode.Scalar {
    /// Generates arbitrary Unicode scalar values.
    public static func unicodeScalars() -> Self {
        let specification = Result {
            try StringGeneratorHandle.text(size: 1...1)
        }
        return Self { testCase in
            let string = try testCase.string(using: specification.get())
            guard let scalar = string.unicodeScalars.first else {
                throw HegelError("Hegel generated an empty Unicode scalar.")
            }
            return scalar
        }
    }
}

extension Generator where Value == Character {
    /// Generates single-scalar characters.
    public static func characters() -> Self {
        Generator<Unicode.Scalar>.unicodeScalars().map {
            Character(String($0))
        }
    }
}

// MARK: - Collections and products

extension Generator {
    /// Generates arrays whose elements are drawn from another generator.
    public static func arrays<Element>(
        of element: Generator<Element>,
        size: ClosedRange<Int> = 0...10,
    ) -> Self where Value == [Element] {
        validate(size: size)
        return Self { testCase in
            try testCase.array(of: element, size: size)
        }
    }

    /// Generates a fixed-size inline array.
    public static func inlineArrays<let count: Int, Element>(
        of element: Generator<Element>
    ) -> Self where Value == InlineArray<count, Element> {
        Self { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_TUPLE.rawValue)) {
                try InlineArray<count, Element> { _ in
                    try element.draw(testCase)
                }
            }
        }
    }

    /// Generates sets whose elements are drawn from another generator.
    public static func sets<Element>(
        of element: Generator<Element>,
        size: ClosedRange<Int> = 0...10,
    ) -> Self where Value == Set<Element> {
        validate(size: size)
        return Self { testCase in
            try testCase.set(of: element, size: size)
        }
    }

    /// Generates dictionaries from separate key and value generators.
    public static func dictionaries<Key, Element>(
        keys: Generator<Key>,
        values: Generator<Element>,
        size: ClosedRange<Int> = 0...10,
    ) -> Self where Value == [Key: Element] {
        validate(size: size)
        return Self { testCase in
            try testCase.dictionary(keys: keys, values: values, size: size)
        }
    }

    /// Generates a fixed-shape tuple from its component generators.
    public static func tuple<each Element>(
        _ elements: repeat Generator<each Element>
    ) -> Self where Value == (repeat each Element) {
        Self { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_TUPLE.rawValue)) {
                (repeat try (each elements).draw(testCase))
            }
        }
    }
}

private func validate(size: ClosedRange<Int>) {
    precondition(size.lowerBound >= 0)
}
