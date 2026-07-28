import CHegel

/// Configuration for a Hegel property-test run.
public struct Settings: Sendable {
    @nonexhaustive
    public enum Database: Sendable {
        /// Uses `.hegel/examples` outside CI and disables the database in CI.
        case `default`
        /// Disables persistence and reuse of interesting examples.
        case disabled
        /// Stores and reuses interesting examples in the given directory.
        case path(String)
    }

    @nonexhaustive
    public enum Verbosity: UInt32, Sendable {
        case quiet
        case normal
        case verbose
        case debug
    }

    public struct Phases: OptionSet, Sendable {
        public var rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Runs hard-coded explicit examples.
        public static var explicit: Self { Self(rawValue: 1 << 0) }
        /// Replays examples from the failure database.
        public static var reuse: Self { Self(rawValue: 1 << 1) }
        /// Generates fresh test cases.
        public static var generate: Self { Self(rawValue: 1 << 2) }
        /// Guides generation toward observed target scores.
        public static var target: Self { Self(rawValue: 1 << 3) }
        /// Minimizes discovered failures.
        public static var shrink: Self { Self(rawValue: 1 << 4) }
        /// Runs every available phase.
        public static var all: Self {
            [.explicit, .reuse, .generate, .target, .shrink]
        }
    }

    public struct HealthChecks: OptionSet, Sendable {
        public var rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Suppresses the check for too many rejected cases.
        public static var filterTooMuch: Self { Self(rawValue: 1 << 0) }
        /// Suppresses the check for unusually slow test cases.
        public static var tooSlow: Self { Self(rawValue: 1 << 1) }
        /// Suppresses the check for impractically large generated data.
        public static var testCasesTooLarge: Self { Self(rawValue: 1 << 2) }
        /// Suppresses the check for a disproportionately large initial case.
        public static var largeInitialTestCase: Self { Self(rawValue: 1 << 3) }
        /// Suppresses every available health check.
        public static var all: Self {
            [.filterTooMuch, .tooSlow, .testCasesTooLarge, .largeInitialTestCase]
        }
    }

    /// The maximum number of valid test cases.
    public var testCases: UInt64
    /// The amount of engine diagnostic output.
    public var verbosity: Verbosity
    /// A fixed seed, or `nil` to choose one at run time.
    public var seed: UInt64?
    /// Whether an unseeded run derives a stable seed from the test identifier.
    public var derandomize: Bool?
    /// The location used to persist and reuse interesting examples.
    public var database: Database
    /// The property-test lifecycle phases to run.
    public var phases: Phases
    /// Health checks that should not fail the run.
    public var suppressedHealthChecks: HealthChecks

    public init(
        testCases: UInt64 = 100,
        verbosity: Verbosity = .normal,
        seed: UInt64? = nil,
        derandomize: Bool? = nil,
        database: Database = .default,
        phases: Phases = .all,
        suppressedHealthChecks: HealthChecks = [],
    ) {
        self.testCases = testCases
        self.verbosity = verbosity
        self.seed = seed
        self.derandomize = derandomize
        self.database = database
        self.phases = phases
        self.suppressedHealthChecks = suppressedHealthChecks
    }
}

@safe
struct CSettings: ~Copyable {
    var context: Context
    var handle: OpaquePointer

    init(
        _ settings: Settings,
        databaseKey: String,
    ) throws {
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
            if let derandomize = settings.derandomize {
                try context.check(
                    unsafe hegel_settings_set_derandomize(
                        context.handle,
                        handle,
                        derandomize,
                    )
                )
            }
            try context.check(
                unsafe hegel_settings_set_phases(
                    context.handle,
                    handle,
                    settings.phases.rawValue,
                )
            )
            try context.check(
                unsafe hegel_settings_set_suppress_health_check(
                    context.handle,
                    handle,
                    settings.suppressedHealthChecks.rawValue,
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
                unsafe try path.withCString { path in
                    try context.check(
                        unsafe hegel_settings_set_database(
                            context.handle,
                            handle,
                            path,
                        )
                    )
                }
            }
            unsafe try databaseKey.withCString { databaseKey in
                try context.check(
                    unsafe hegel_settings_set_database_key(
                        context.handle,
                        handle,
                        databaseKey,
                    )
                )
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
