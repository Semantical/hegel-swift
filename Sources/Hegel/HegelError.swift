/// An error reported by the Hegel runtime or its Swift binding.
public struct HegelError: Error, CustomStringConvertible, Sendable {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// A minimal counterexample found by Hegel.
public struct PropertyFailure: Error, CustomStringConvertible, Sendable {
    /// The source location that identifies the failed property.
    public var origin: String

    /// Hegel's opaque, deterministic reproduction blob.
    public var reproduction: String

    /// The error produced by replaying the minimal counterexample.
    public var cause: String

    public init(
        origin: String,
        reproduction: String,
        cause: String,
    ) {
        self.origin = origin
        self.reproduction = reproduction
        self.cause = cause
    }

    public var description: String {
        """
        Property failed after shrinking at \(origin):
        \(cause)

        Reproduce with:
        try await Hegel.test(reproducing: "\(reproduction)") { testCase in
            // property
        }
        """
    }
}
