import CHegel

/// Explicit overrides over an engine-resolved profile for a Hegel property-test run.
/// Unspecified fields inherit from the enclosing suite and selected profile.
public struct Settings: Sendable {
    @nonexhaustive
    public enum Database: Sendable {
        /// Resets persistence to the engine's default database location.
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

    /// An explicit seed policy. Omit it to inherit the engine or suite setting.
    public enum Seed: Sendable, Equatable {
        /// Clears a fixed seed; the engine still honors `derandomize` for unseeded runs.
        case automatic
        case fixed(UInt64)
    }

    /// The engine profile to resolve, or `nil` to inherit the suite's selection.
    /// Without a selection, Hegel resolves `default` using `hegel.toml` and the environment.
    public var profile: String?

    /// The maximum number of valid test cases, or `nil` to inherit.
    public var testCases: UInt64?
    /// The amount of engine diagnostic output, or `nil` to inherit.
    public var verbosity: Verbosity?
    /// An explicit seed policy, or `nil` to inherit.
    public var seed: Seed?
    /// Whether an unseeded run derives a stable seed from the test identifier.
    public var derandomize: Bool?
    /// The location used to persist examples, or `nil` to inherit.
    public var database: Database?
    /// The property-test lifecycle phases to run, or `nil` to inherit.
    public var phases: Phases?
    /// Whether to print event statistics, or `nil` to inherit.
    public var showStatistics: Bool?
    /// Whether to print a copy-pasteable reproduction trait after failure, or `nil` to inherit.
    public var printReproduction: Bool?
    /// Health checks to suppress, or `nil` to inherit. An empty set enables every check.
    public var suppressedHealthChecks: HealthChecks?

    public init(
        profile: String? = nil,
        testCases: UInt64? = nil,
        verbosity: Verbosity? = nil,
        seed: Seed? = nil,
        derandomize: Bool? = nil,
        database: Database? = nil,
        phases: Phases? = nil,
        showStatistics: Bool? = nil,
        printReproduction: Bool? = nil,
        suppressedHealthChecks: HealthChecks? = nil,
    ) {
        self.profile = profile
        self.testCases = testCases
        self.verbosity = verbosity
        self.seed = seed
        self.derandomize = derandomize
        self.database = database
        self.phases = phases
        self.showStatistics = showStatistics
        self.printReproduction = printReproduction
        self.suppressedHealthChecks = suppressedHealthChecks
    }

    func merging(_ overrides: Self) -> Self {
        Self(
            profile: overrides.profile ?? profile,
            testCases: overrides.testCases ?? testCases,
            verbosity: overrides.verbosity ?? verbosity,
            seed: overrides.seed ?? seed,
            derandomize: overrides.derandomize ?? derandomize,
            database: overrides.database ?? database,
            phases: overrides.phases ?? phases,
            showStatistics: overrides.showStatistics ?? showStatistics,
            printReproduction: overrides.printReproduction ?? printReproduction,
            suppressedHealthChecks: overrides.suppressedHealthChecks ?? suppressedHealthChecks,
        )
    }
}

@safe
package struct CSettings: ~Copyable {
    var context: Context
    package var handle: OpaquePointer

    package init(
        _ settings: Settings,
        databaseKey: String,
    ) throws {
        let context = try Context()
        var handle: OpaquePointer?
        if let profile = settings.profile {
            guard !profile.utf8.contains(0) else {
                throw HegelError("A Hegel profile name cannot contain a NUL byte.")
            }
            unsafe try profile.withCString { profile in
                try context.check(
                    unsafe hegel_settings_new_for_profile(context.handle, profile, &handle)
                )
            }
        } else {
            try context.check(
                unsafe hegel_settings_new(context.handle, &handle)
            )
        }
        guard let handle = unsafe handle else {
            throw HegelError("Hegel returned an empty settings handle.")
        }

        do {
            if let testCases = settings.testCases {
                try context.check(
                    unsafe hegel_settings_set_test_cases(
                        context.handle,
                        handle,
                        testCases,
                    )
                )
            }
            if let verbosity = settings.verbosity {
                try context.check(
                    unsafe hegel_settings_set_verbosity(
                        context.handle,
                        handle,
                        verbosity.cValue.rawValue,
                    )
                )
            }
            if let seed = settings.seed {
                let value: UInt64?
                switch seed {
                case .automatic: value = nil
                case .fixed(let fixed): value = fixed
                }
                try context.check(
                    unsafe hegel_settings_set_seed(
                        context.handle,
                        handle,
                        value ?? 0,
                        value != nil,
                    )
                )
            }
            if let derandomize = settings.derandomize {
                try context.check(
                    unsafe hegel_settings_set_derandomize(
                        context.handle,
                        handle,
                        derandomize,
                    )
                )
            }
            if let phases = settings.phases {
                try context.check(
                    unsafe hegel_settings_set_phases(
                        context.handle,
                        handle,
                        phases.rawValue,
                    )
                )
            }
            if let suppressedHealthChecks = settings.suppressedHealthChecks {
                try context.check(
                    unsafe hegel_settings_set_suppress_health_check(
                        context.handle,
                        handle,
                        suppressedHealthChecks.rawValue,
                    )
                )
            }
            if let showStatistics = settings.showStatistics {
                try context.check(
                    unsafe hegel_settings_set_show_statistics(
                        context.handle,
                        handle,
                        showStatistics,
                    )
                )
            }
            if let printReproduction = settings.printReproduction {
                try context.check(
                    unsafe hegel_settings_set_print_blob(
                        context.handle,
                        handle,
                        printReproduction,
                    )
                )
            }
            // One thrown invocation should produce one Swift Testing issue.
            try context.check(
                unsafe hegel_settings_set_report_multiple_failures(
                    context.handle,
                    handle,
                    false,
                )
            )

            switch settings.database {
            case nil:
                break
            case .default:
                try context.check(
                    unsafe hegel_settings_set_database(context.handle, handle, nil)
                )
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

    func shouldPrintReproduction() throws -> Bool {
        var enabled = false
        try context.check(
            unsafe hegel_settings_get_print_blob(context.handle, handle, &enabled)
        )
        return enabled
    }

    deinit {
        _ = unsafe hegel_settings_free(context.handle, handle)
    }
}

// MARK: - C values

extension Settings.Verbosity {
    var cValue: hegel_verbosity_t {
        switch self {
        case .quiet: HEGEL_VERBOSITY_QUIET
        case .normal: HEGEL_VERBOSITY_NORMAL
        case .verbose: HEGEL_VERBOSITY_VERBOSE
        case .debug: HEGEL_VERBOSITY_DEBUG
        }
    }
}
