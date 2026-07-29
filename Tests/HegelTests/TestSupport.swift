import Hegel

func generationSettings(testCases: UInt64 = 25) -> Settings {
    Settings(
        testCases: testCases,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
        phases: [.generate],
    )
}

func searchSettings(testCases: UInt64 = 200) -> Settings {
    Settings(
        testCases: testCases,
        verbosity: .quiet,
        seed: 0xC0FFEE,
        database: .disabled,
    )
}
