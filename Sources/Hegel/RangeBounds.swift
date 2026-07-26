/// Optional inclusive or exclusive endpoints for generated values.
///
/// Swift's closed, half-open, lower-bounded, and upper-bounded range types
/// all conform.
public protocol RangeBounds<Bound> {
    associatedtype Bound: Comparable

    var lowerEndpoint: (value: Bound, isInclusive: Bool)? { get }
    var upperEndpoint: (value: Bound, isInclusive: Bool)? { get }
}

extension ClosedRange: RangeBounds {
    public var lowerEndpoint: (value: Bound, isInclusive: Bool)? {
        (lowerBound, true)
    }

    public var upperEndpoint: (value: Bound, isInclusive: Bool)? {
        (upperBound, true)
    }
}

extension Range: RangeBounds {
    public var lowerEndpoint: (value: Bound, isInclusive: Bool)? {
        (lowerBound, true)
    }

    public var upperEndpoint: (value: Bound, isInclusive: Bool)? {
        precondition(!isEmpty)
        return (upperBound, false)
    }
}

extension PartialRangeFrom: RangeBounds {
    public var lowerEndpoint: (value: Bound, isInclusive: Bool)? {
        (lowerBound, true)
    }

    public var upperEndpoint: (value: Bound, isInclusive: Bool)? {
        nil
    }
}

extension PartialRangeThrough: RangeBounds {
    public var lowerEndpoint: (value: Bound, isInclusive: Bool)? {
        nil
    }

    public var upperEndpoint: (value: Bound, isInclusive: Bool)? {
        (upperBound, true)
    }
}

extension PartialRangeUpTo: RangeBounds {
    public var lowerEndpoint: (value: Bound, isInclusive: Bool)? {
        nil
    }

    public var upperEndpoint: (value: Bound, isInclusive: Bool)? {
        (upperBound, false)
    }
}

struct ValidatedSizeBounds {
    var minimum: Int
    var maximum: Int?

    init(minimum: Int = 0, maximum: Int? = nil) {
        precondition(minimum >= 0)
        if let maximum {
            precondition(maximum >= minimum)
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    init(_ bounds: some RangeBounds<Int>) {
        self.init(
            minimum: inclusiveLowerBound(
                bounds.lowerEndpoint,
                default: 0,
            ),
            maximum: inclusiveUpperBound(bounds.upperEndpoint),
        )
    }

    var cMaximum: UInt64 {
        maximum.map(UInt64.init) ?? UInt64.max
    }

    /// Resolves APIs whose C entry point requires a concrete upper bound.
    ///
    /// This matches Rust's direct text and byte generation policy: sizes up to
    /// 100 by default, or a further 100 elements when the minimum is larger.
    func resolvedForDirectGeneration() -> ClosedRange<Int> {
        if let maximum {
            return minimum...maximum
        }
        guard minimum > 100 else {
            return minimum...100
        }
        let (maximum, overflow) = minimum.addingReportingOverflow(100)
        return minimum...(overflow ? Int.max : maximum)
    }
}

func inclusiveLowerBound<Bound: FixedWidthInteger>(
    _ endpoint: (value: Bound, isInclusive: Bool)?,
    default defaultValue: Bound,
) -> Bound {
    guard let endpoint else {
        return defaultValue
    }
    guard !endpoint.isInclusive else {
        return endpoint.value
    }
    let (value, overflow) = endpoint.value.addingReportingOverflow(1)
    precondition(!overflow)
    return value
}

func inclusiveUpperBound<Bound: FixedWidthInteger>(
    _ endpoint: (value: Bound, isInclusive: Bool)?
) -> Bound? {
    guard let endpoint else {
        return nil
    }
    guard !endpoint.isInclusive else {
        return endpoint.value
    }
    let (value, overflow) = endpoint.value.subtractingReportingOverflow(1)
    precondition(!overflow)
    return value
}
