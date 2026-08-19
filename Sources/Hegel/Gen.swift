import CHegel

// "SWIFT" followed by 1, reserved for custom generator spans.
private let compositeSpanLabel: UInt64 = 0x5357494654_01

/// A value recipe drawn and shrunk by Hegel.
public struct Gen<Value> {
    var draw: (borrowing TestCase) throws -> Value

    // A known, practically enumerable domain lets unordered collections select
    // distinct entries directly. `nil` means "not enumerable", not "infinite".
    var enumeratedValues: [Value]?

    /// Creates a generator from an imperative sequence of draws.
    public init(
        _ draw: @escaping (borrowing TestCase) throws -> Value
    ) {
        self.init(enumeratedValues: nil) { testCase in
            try testCase.withSpan(label: compositeSpanLabel) {
                try draw(testCase)
            }
        }
    }

    init(
        enumeratedValues: [Value]?,
        draw: @escaping (borrowing TestCase) throws -> Value,
    ) {
        self.draw = draw
        self.enumeratedValues = enumeratedValues
    }

    static func unspanned(
        _ draw: @escaping (borrowing TestCase) throws -> Value
    ) -> Self {
        Self(enumeratedValues: nil, draw: draw)
    }
}

// MARK: - Composition

extension Gen {
    /// Always generates the given value.
    public static func constant(_ value: Value) -> Self {
        Self(enumeratedValues: [value]) { _ in value }
    }

    /// Generates one of the supplied values in their stable iteration order.
    public static func sampled(
        from values: some BidirectionalCollection<Value>
    ) -> Self {
        let values = Array(values)
        precondition(!values.isEmpty)
        return Self(enumeratedValues: values) { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_SAMPLED_FROM) {
                let index = try testCase.integer(in: 0...(values.count - 1))
                return values[index]
            }
        }
    }

    /// Generates one of the supplied values after putting them in a deterministic total order.
    public static func sampled(
        from values: some Collection<Value>,
        sortedBy areInIncreasingOrder: (Value, Value) -> Bool
    ) -> Self {
        sampled(from: values.sorted(by: areInIncreasingOrder))
    }

    /// Returns a generator over the supplied values, or `nil` when they are empty.
    public static func sampledIfPresent(
        from values: some BidirectionalCollection<Value>
    ) -> Self? {
        guard !values.isEmpty else { return nil }
        return sampled(from: values)
    }

    /// Returns a stably ordered generator, or `nil` when no values are supplied.
    public static func sampledIfPresent(
        from values: some Collection<Value>,
        sortedBy areInIncreasingOrder: (Value, Value) -> Bool
    ) -> Self? {
        guard !values.isEmpty else { return nil }
        return sampled(from: values, sortedBy: areInIncreasingOrder)
    }

    /// Generates a value from one of the supplied generators.
    public static func oneOf(_ generators: Self?...) -> Self {
        oneOf(generators.compactMap(\.self))
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
            try testCase.withSpan(label: HEGEL_LABEL_ONE_OF) {
                let index = try testCase.integer(in: 0...(generators.count - 1))
                return try generators[index].draw(testCase)
            }
        }
    }

    /// Creates a generator whose definition can refer to itself.
    public static func recursive(_ definition: (Self) -> Self) -> Self {
        let deferred = DeferredGeneratorDefinition<Value>()
        let recursive = deferred.generator
        deferred.set(definition(recursive))
        return recursive
    }

    /// Transforms generated values without changing their choices.
    public func map<NewValue>(
        _ transform: @escaping (Value) throws -> NewValue
    ) -> Gen<NewValue> {
        Gen<NewValue>(
            enumeratedValues: try? enumeratedValues?.map(transform)
        ) { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_MAPPED) {
                try transform(draw(testCase))
            }
        }
    }

    /// Chooses a subsequent generator from the generated value.
    public func flatMap<NewValue>(
        _ transform: @escaping (Value) throws -> Gen<NewValue>
    ) -> Gen<NewValue> {
        .unspanned { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_FLAT_MAP) {
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
        return .unspanned { testCase in
            try testCase.filtered(self, by: predicate)
        }
    }

    /// Generates either no value or a value from this generator.
    public func optional(probabilityOfSome probability: Double = 0.5) -> Gen<Value?> {
        precondition((0...1).contains(probability))
        return Gen<Value?>(
            enumeratedValues: enumeratedValues.map { [nil] + $0.map(Optional.some) }
        ) { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_OPTIONAL) {
                guard try testCase.boolean(probability: probability) else {
                    return nil
                }
                return try draw(testCase)
            }
        }
    }
}

extension Gen where Value: CaseIterable, Value.AllCases: BidirectionalCollection {
    /// Generates one of the type's cases.
    public static var cases: Self {
        sampled(from: Value.allCases)
    }
}

// MARK: - Scalar values

extension Gen where Value: FixedWidthInteger {
    /// Generates integers across the type's full range.
    public static var integers: Self {
        integers(in: Value.min...Value.max)
    }

    /// Generates integers of the given type across its full range.
    public static func integers(_: Value.Type) -> Self {
        integers
    }

    /// Generates integers within the given bounds.
    public static func integers(in range: some RangeBounds<Value>) -> Self {
        let minimum = inclusiveLowerBound(range.lowerEndpoint, default: Value.min)
        let maximum = inclusiveUpperBound(range.upperEndpoint) ?? Value.max
        precondition(minimum <= maximum)
        return .unspanned { testCase in
            try testCase.integer(in: minimum...maximum)
        }
    }

    /// Generates integers of the given type within the given bounds.
    public static func integers<Bounds>(
        _: Value.Type,
        in range: Bounds,
    ) -> Self where Bounds: RangeBounds<Value> {
        integers(in: range)
    }
}

extension Gen where Value == Int {
    /// Generates integers across `Int`'s full range.
    public static var integers: Self {
        integers(in: Int.min...Int.max)
    }
}

extension Gen where Value == Bool {
    /// Generates uniformly distributed booleans.
    public static var booleans: Self {
        booleans()
    }

    /// Generates booleans that are true with the given probability.
    public static func booleans(probability: Double = 0.5) -> Self {
        precondition((0...1).contains(probability))
        return Self(enumeratedValues: [false, true]) { testCase in
            try testCase.boolean(probability: probability)
        }
    }
}

extension Gen where Value == Float {
    /// Generates floating-point values, including special values.
    public static var floats: Self {
        floats()
    }

    /// Generates floating-point values within the given bounds.
    public static func floats(
        in range: some RangeBounds<Float> = -.infinity ... .infinity,
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
        return .unspanned { testCase in
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
    /// Generates floating-point values, including special values.
    public static var doubles: Self {
        doubles()
    }

    /// Generates floating-point values within the given bounds.
    public static func doubles(
        in range: some RangeBounds<Double> = -.infinity ... .infinity,
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
        return .unspanned { testCase in
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
    public static var bytes: Self {
        bytes(size: ValidatedSizeBounds())
    }

    /// Generates byte strings whose sizes fall within the given bounds.
    public static func bytes(size: some RangeBounds<Int>) -> Self {
        bytes(size: ValidatedSizeBounds(size))
    }

    private static func bytes(size: ValidatedSizeBounds) -> Self {
        let size = size.resolvedForDirectGeneration()
        return .unspanned { testCase in
            try testCase.bytes(size: size)
        }
    }
}

extension Gen where Value == String {
    /// Generates Unicode strings using Hegel's default size budget.
    public static var strings: Self {
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
        return .unspanned { testCase in
            try testCase.string(using: specification.get())
        }
    }
}

extension Gen where Value == Unicode.Scalar {
    /// Generates arbitrary Unicode scalar values.
    public static var unicodeScalars: Self {
        let specification = Result {
            try StringGeneratorHandle.text(size: 1...1)
        }
        return .unspanned { testCase in
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
    public static var characters: Self {
        Gen<Unicode.Scalar>.unicodeScalars.map {
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
        .unspanned { testCase in
            try testCase.array(of: element, size: size)
        }
    }

    /// Generates a fixed-size inline array.
    public static func inlineArrays<let count: Int, Element>(
        of element: Gen<Element>
    ) -> Self where Value == [count of Element] {
        .unspanned { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_TUPLE) {
                try [count of Element] { _ in
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
        .unspanned { testCase in
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
        .unspanned { testCase in
            try testCase.dictionary(keys: keys, values: values, size: size)
        }
    }

    /// Generates a fixed-shape tuple from its component generators.
    public static func tuple<each Element>(
        _ elements: repeat Gen<each Element>
    ) -> Self where Value == (repeat each Element) {
        .unspanned { testCase in
            try testCase.withSpan(label: HEGEL_LABEL_TUPLE) {
                (repeat try (each elements).draw(testCase))
            }
        }
    }
}
