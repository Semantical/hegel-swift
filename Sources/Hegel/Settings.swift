import CHegel

/// Configuration for a Hegel property-test run.
public struct Settings: Sendable {
    /// Controls whether Hegel persists and reuses interesting examples.
    public enum Database: Sendable {
        case `default`
        case disabled
        case path(String)
    }

    /// Controls Hegel's diagnostic output.
    public enum Verbosity: UInt32, Sendable {
        case quiet
        case normal
        case verbose
        case debug
    }

    public var testCases: UInt64
    public var verbosity: Verbosity
    public var seed: UInt64?
    public var database: Database

    public init(
        testCases: UInt64 = 100,
        verbosity: Verbosity = .normal,
        seed: UInt64? = nil,
        database: Database = .default,
    ) {
        self.testCases = testCases
        self.verbosity = verbosity
        self.seed = seed
        self.database = database
    }
}

@safe
struct CSettings: ~Copyable {
    var context: Context
    var handle: OpaquePointer

    init(_ settings: Settings) throws {
        let context = try Context()
        var handle: OpaquePointer?
        try context.check(
            unsafe hegel_settings_new(context.handle, &handle)
        )
        guard let handle = unsafe handle else {
            throw HegelError("Hegel returned an empty settings handle.")
        }

        do {
            try context.check(
                unsafe hegel_settings_set_test_cases(
                    context.handle,
                    handle,
                    settings.testCases,
                )
            )
            try context.check(
                unsafe hegel_settings_set_verbosity(
                    context.handle,
                    handle,
                    settings.verbosity.rawValue,
                )
            )
            try context.check(
                unsafe hegel_settings_set_seed(
                    context.handle,
                    handle,
                    settings.seed ?? 0,
                    settings.seed != nil,
                )
            )
            // One thrown invocation should produce one Swift Testing issue.
            try context.check(
                unsafe hegel_settings_set_report_multiple_failures(
                    context.handle,
                    handle,
                    false,
                )
            )

            switch settings.database {
            case .default:
                break
            case .disabled:
                try context.check(
                    unsafe hegel_settings_set_database(
                        context.handle,
                        handle,
                        "",
                    )
                )
            case .path(let path):
                try path.withCString { path in
                    try context.check(
                        unsafe hegel_settings_set_database(
                            context.handle,
                            handle,
                            path,
                        )
                    )
                }
            }
        } catch {
            _ = unsafe hegel_settings_free(context.handle, handle)
            throw error
        }

        self.context = consume context
        unsafe self.handle = handle
    }

    deinit {
        _ = unsafe hegel_settings_free(context.handle, handle)
    }
}
