import Hegel

func generationSettings(testCases: UInt64 = 25) -> Settings {
    Settings(
        testCases: testCases,
        verbosity: .quiet,
        seed: .fixed(0xC0FFEE),
        database: .disabled,
        phases: [.generate],
    )
}

func searchSettings(testCases: UInt64 = 200) -> Settings {
    Settings(
        testCases: testCases,
        verbosity: .quiet,
        seed: .fixed(0xC0FFEE),
        database: .disabled,
    )
}
