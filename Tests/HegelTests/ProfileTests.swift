import CHegel
import Hegel
import Testing

@Suite
struct ProfileTests {
    @Test
    func `verbosity maps to the engine levels`() throws {
        for (value, expected) in [
            (Settings.Verbosity.normal, HEGEL_VERBOSITY_NORMAL),
            (.quiet, HEGEL_VERBOSITY_QUIET),
            (.verbose, HEGEL_VERBOSITY_VERBOSE),
            (.debug, HEGEL_VERBOSITY_DEBUG),
        ] {
            let settings = try CSettings(
                Settings(profile: "base", verbosity: value),
                databaseKey: "verbosity",
            )
            var actual = HEGEL_VERBOSITY_NORMAL
            try #require(
                unsafe hegel_settings_get_verbosity(nil, settings.handle, &actual) == HEGEL_OK
            )
            #expect(actual == expected)
        }
    }

    @Test
    func `Swift overrides preserve the remaining profile values`() throws {
        // Build the fixture directly through C so Swift's bridge is only on the
        // side under test. Registration leaves every other test's default intact.
        let name = "swift-settings-overlay-test"
        var profile: OpaquePointer?
        try #require(unsafe hegel_settings_new_for_profile(nil, "base", &profile) == HEGEL_OK)
        let handle = unsafe try #require(profile)
        defer { _ = unsafe hegel_settings_free(nil, handle) }
        try #require(unsafe hegel_settings_set_test_cases(nil, handle, 17) == HEGEL_OK)
        try #require(unsafe hegel_settings_set_seed(nil, handle, 42, true) == HEGEL_OK)
        try #require(
            unsafe hegel_settings_set_phases(nil, handle, HEGEL_PHASE_GENERATE.rawValue) == HEGEL_OK
        )
        try #require(
            unsafe hegel_settings_set_suppress_health_check(
                nil,
                handle,
                HEGEL_HC_TOO_SLOW.rawValue,
            ) == HEGEL_OK
        )
        let registered = unsafe name.withCString { name in
            unsafe hegel_settings_register_profile(nil, name, handle)
        }
        try #require(registered == HEGEL_OK)

        for (overrides, expectedCount, expectedSeed, expectedChecks) in [
            (
                Settings(profile: name), UInt64(17), UInt64(42) as UInt64?,
                HEGEL_HC_TOO_SLOW.rawValue,
            ),
            (
                Settings(
                    profile: name,
                    testCases: 3,
                    seed: .automatic,
                    suppressedHealthChecks: [],
                ), 3, nil, 0,
            ),
        ] {
            let settings = try CSettings(overrides, databaseKey: "overlay")
            var count: UInt64 = 0
            var seed: UInt64 = 0
            var hasSeed = false
            var phases: UInt32 = 0
            var checks: UInt32 = 0
            try #require(
                unsafe hegel_settings_get_test_cases(nil, settings.handle, &count) == HEGEL_OK
            )
            try #require(
                unsafe hegel_settings_get_seed(nil, settings.handle, &seed, &hasSeed) == HEGEL_OK
            )
            try #require(
                unsafe hegel_settings_get_phases(nil, settings.handle, &phases) == HEGEL_OK
            )
            try #require(
                unsafe hegel_settings_get_suppress_health_check(nil, settings.handle, &checks)
                    == HEGEL_OK
            )
            #expect(count == expectedCount)
            #expect((hasSeed ? seed : nil) == expectedSeed)
            #expect(phases == HEGEL_PHASE_GENERATE.rawValue)
            #expect(checks == expectedChecks)
        }
    }
}
