/// A single-assignment generator definition for recursive generator graphs.
public struct DeferredGeneratorDefinition<Value>: ~Copyable {
    private final class Storage {
        var implementation: Gen<Value>?
    }

    private var storage: Storage

    init() {
        self.storage = Storage()
    }

    /// A generator that delegates to the eventual implementation.
    ///
    /// Any number of handles may be created before calling ``set(_:)``.
    /// Drawing from one before the definition is completed is a programmer error.
    public var generator: Gen<Value> {
        Gen { [storage] testCase in
            guard let implementation = storage.implementation else {
                preconditionFailure("deferred generator was drawn before being set")
            }
            return try implementation.draw(testCase)
        }
    }

    /// Completes the definition and consumes it, enforcing single assignment.
    public consuming func set(_ generator: Gen<Value>) {
        storage.implementation = generator
    }
}
