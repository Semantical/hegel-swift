import CHegel

/// A value recipe drawn and shrunk by Hegel.
public struct Gen<Value> {
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

extension Gen {
    /// Creates a forward-reference definition for recursive generators.
    public static func deferred() -> DeferredGeneratorDefinition<Value> {
        DeferredGeneratorDefinition()
    }

    /// Always generates the given value.
    public static func just(_ value: Value) -> Self {
        Self(enumeratedValues: [value]) { _ in value }
    }

    /// Generates one of the supplied values.
    public static func sampled(from values: some Collection<Value>) -> Self {
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
    ) -> Gen<NewValue> {
        Gen<NewValue>(
            enumeratedValues: try? enumeratedValues?.map(transform)
        ) { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_MAPPED.rawValue)) {
                try transform(draw(testCase))
            }
        }
    }

    /// Chooses a subsequent generator from the generated value.
    public func flatMap<NewValue>(
        _ transform: @escaping (Value) throws -> Gen<NewValue>
    ) -> Gen<NewValue> {
        Gen<NewValue> { testCase in
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
    public func optional(probabilityOfSome probability: Double = 0.5) -> Gen<Value?> {
        precondition((0...1).contains(probability))
        return Gen<Value?>(
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

extension Gen where Value: FixedWidthInteger {
    /// Generates integers across the type's full range.
    public static func integers() -> Self {
        integers(in: Value.min...Value.max)
    }

    /// Generates integers within the given bounds.
    public static func integers(in range: some RangeBounds<Value>) -> Self {
        let minimum = inclusiveLowerBound(range.lowerEndpoint, default: Value.min)
        let maximum = inclusiveUpperBound(range.upperEndpoint) ?? Value.max
        precondition(minimum <= maximum)
        return Self { testCase in
            try testCase.integer(in: minimum...maximum)
        }
    }
}

extension Gen where Value == Bool {
    /// Generates booleans that are true with the given probability.
    public static func booleans(probability: Double = 0.5) -> Self {
        precondition((0...1).contains(probability))
        return Self(enumeratedValues: [false, true]) { testCase in
            try testCase.boolean(probability: probability)
        }
    }
}

extension Gen where Value == Float {
    /// Generates floating-point values, including special values when unbounded.
    public static func floats(
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        Self { testCase in
            try testCase.float(
                minimum: -.infinity,
                maximum: .infinity,
                allowingNaN: allowingNaN ?? true,
                allowingInfinity: allowingInfinity ?? true,
                allowingSubnormal: allowingSubnormal,
            )
        }
    }

    /// Generates floating-point values within the given bounds.
    public static func floats(
        in range: some RangeBounds<Float>,
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        let lower = range.lowerEndpoint
        let upper = range.upperEndpoint
        let minimum = lower?.value ?? -.infinity
        let maximum = upper?.value ?? .infinity
        precondition(!minimum.isNaN && !maximum.isNaN)
        precondition(minimum <= maximum)
        precondition(
            minimum < maximum
                || (lower?.isInclusive != false && upper?.isInclusive != false)
        )
        return Self { testCase in
            try testCase.float(
                minimum: minimum,
                maximum: maximum,
                allowingNaN: allowingNaN ?? false,
                allowingInfinity: allowingInfinity ?? (lower == nil || upper == nil),
                allowingSubnormal: allowingSubnormal,
                excludingMinimum: lower?.isInclusive == false,
                excludingMaximum: upper?.isInclusive == false,
            )
        }
    }
}

extension Gen where Value == Double {
    /// Generates floating-point values, including special values when unbounded.
    public static func floats(
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        Self { testCase in
            try testCase.float(
                minimum: -.infinity,
                maximum: .infinity,
                allowingNaN: allowingNaN ?? true,
                allowingInfinity: allowingInfinity ?? true,
                allowingSubnormal: allowingSubnormal,
            )
        }
    }

    /// Generates floating-point values within the given bounds.
    public static func floats(
        in range: some RangeBounds<Double>,
        allowingNaN: Bool? = nil,
        allowingInfinity: Bool? = nil,
        allowingSubnormal: Bool = true,
    ) -> Self {
        let lower = range.lowerEndpoint
        let upper = range.upperEndpoint
        let minimum = lower?.value ?? -.infinity
        let maximum = upper?.value ?? .infinity
        precondition(!minimum.isNaN && !maximum.isNaN)
        precondition(minimum <= maximum)
        precondition(
            minimum < maximum
                || (lower?.isInclusive != false && upper?.isInclusive != false)
        )
        return Self { testCase in
            try testCase.float(
                minimum: minimum,
                maximum: maximum,
                allowingNaN: allowingNaN ?? false,
                allowingInfinity: allowingInfinity ?? (lower == nil || upper == nil),
                allowingSubnormal: allowingSubnormal,
                excludingMinimum: lower?.isInclusive == false,
                excludingMaximum: upper?.isInclusive == false,
            )
        }
    }
}

extension Gen where Value == [UInt8] {
    /// Generates byte strings using Hegel's default size budget.
    public static func bytes() -> Self {
        bytes(size: ValidatedSizeBounds())
    }

    /// Generates byte strings whose sizes fall within the given bounds.
    public static func bytes(size: some RangeBounds<Int>) -> Self {
        bytes(size: ValidatedSizeBounds(size))
    }

    private static func bytes(size: ValidatedSizeBounds) -> Self {
        let size = size.resolvedForDirectGeneration()
        return Self { testCase in
            try testCase.bytes(size: size)
        }
    }
}

extension Gen where Value == String {
    /// Generates Unicode strings using Hegel's default size budget.
    public static func strings() -> Self {
        strings(size: ValidatedSizeBounds())
    }

    /// Generates Unicode strings whose scalar counts fall within the given bounds.
    public static func strings(size: some RangeBounds<Int>) -> Self {
        strings(size: ValidatedSizeBounds(size))
    }

    private static func strings(size: ValidatedSizeBounds) -> Self {
        let size = size.resolvedForDirectGeneration()
        let specification = Result {
            try StringGeneratorHandle.text(size: size)
        }
        return Self { testCase in
            try testCase.string(using: specification.get())
        }
    }
}

extension Gen where Value == Unicode.Scalar {
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

extension Gen where Value == Character {
    /// Generates single-scalar characters.
    public static func characters() -> Self {
        Gen<Unicode.Scalar>.unicodeScalars().map {
            Character(String($0))
        }
    }
}

// MARK: - Collections and products

extension Gen {
    /// Generates arrays whose sizes are chosen by Hegel.
    public static func arrays<Element>(
        of element: Gen<Element>
    ) -> Self where Value == [Element] {
        arrays(of: element, size: ValidatedSizeBounds())
    }

    /// Generates arrays whose sizes fall within the given bounds.
    public static func arrays<Element>(
        of element: Gen<Element>,
        size: some RangeBounds<Int>,
    ) -> Self where Value == [Element] {
        arrays(of: element, size: ValidatedSizeBounds(size))
    }

    private static func arrays<Element>(
        of element: Gen<Element>,
        size: ValidatedSizeBounds,
    ) -> Self where Value == [Element] {
        Self { testCase in
            try testCase.array(of: element, size: size)
        }
    }

    /// Generates a fixed-size inline array.
    public static func inlineArrays<let count: Int, Element>(
        of element: Gen<Element>
    ) -> Self where Value == InlineArray<count, Element> {
        Self { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_TUPLE.rawValue)) {
                try InlineArray<count, Element> { _ in
                    try element.draw(testCase)
                }
            }
        }
    }

    /// Generates sets whose sizes are chosen by Hegel.
    public static func sets<Element>(
        of element: Gen<Element>
    ) -> Self where Value == Set<Element> {
        sets(of: element, size: ValidatedSizeBounds())
    }

    /// Generates sets whose sizes fall within the given bounds.
    public static func sets<Element>(
        of element: Gen<Element>,
        size: some RangeBounds<Int>,
    ) -> Self where Value == Set<Element> {
        sets(of: element, size: ValidatedSizeBounds(size))
    }

    private static func sets<Element>(
        of element: Gen<Element>,
        size: ValidatedSizeBounds,
    ) -> Self where Value == Set<Element> {
        Self { testCase in
            try testCase.set(of: element, size: size)
        }
    }

    /// Generates dictionaries whose sizes are chosen by Hegel.
    public static func dictionaries<Key, Element>(
        keys: Gen<Key>,
        values: Gen<Element>,
    ) -> Self where Value == [Key: Element] {
        dictionaries(keys: keys, values: values, size: ValidatedSizeBounds())
    }

    /// Generates dictionaries whose sizes fall within the given bounds.
    public static func dictionaries<Key, Element>(
        keys: Gen<Key>,
        values: Gen<Element>,
        size: some RangeBounds<Int>,
    ) -> Self where Value == [Key: Element] {
        dictionaries(
            keys: keys,
            values: values,
            size: ValidatedSizeBounds(size),
        )
    }

    private static func dictionaries<Key, Element>(
        keys: Gen<Key>,
        values: Gen<Element>,
        size: ValidatedSizeBounds,
    ) -> Self where Value == [Key: Element] {
        Self { testCase in
            try testCase.dictionary(keys: keys, values: values, size: size)
        }
    }

    /// Generates a fixed-shape tuple from its component generators.
    public static func tuple<each Element>(
        _ elements: repeat Gen<each Element>
    ) -> Self where Value == (repeat each Element) {
        Self { testCase in
            try testCase.withSpan(label: UInt64(HEGEL_LABEL_TUPLE.rawValue)) {
                (repeat try (each elements).draw(testCase))
            }
        }
    }
}
