/// A single-assignment generator definition for recursive generator graphs.
struct DeferredGeneratorDefinition<Value>: ~Copyable {
    // could use UniqueBox instead if it weren't for its platform requirements
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
    var generator: Gen<Value> {
        .unspanned { [storage] testCase in
            guard let implementation = storage.implementation else {
                preconditionFailure("deferred generator was drawn before being set")
            }
            return try implementation.draw(testCase)
        }
    }

    /// Completes the definition and consumes it, enforcing single assignment.
    consuming func set(_ generator: Gen<Value>) {
        storage.implementation = generator
    }
}
