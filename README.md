# Hegel for Swift

Property-based testing for [Swift Testing](https://github.com/swiftlang/swift-testing), powered by [Hegel](https://github.com/hegeldev/hegel-rust). Hegel generates test inputs and shrinks failures to small counterexamples.

> [!IMPORTANT]
> `hegel-swift` is a work in progress and breaking changes are expected.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/semantical/hegel-swift", from: "0.2.0")
```

Then add its `Hegel` product to your test target:

```swift
.product(name: "Hegel", package: "hegel-swift")
```



The `HegelMacros` trait is enabled by default. To use Hegel without its state-machine macros, add `traits: []` to the package dependency. When working on this repository, `swift test --disable-default-traits` selects that same configuration.


The package requires Swift 6.3 or later. The libraries cover these targets:

| Platform                     | Architectures |
|------------------------------|---------------|
| Linux (glibc)                | arm64, x86_64 |
| macOS 26 or later            | arm64         |
| Windows (MSVC)               | arm64, x86_64 |
| WASI Preview 1               | wasm32        |

Wasm uses the matching Swift 6.3 Wasm SDK with `--disable-default-traits --disable-xctest`. The package supplies entropy and monotonic time through WASI. The upstream Wasm backend does not support filesystem persistence, `hegel.toml`, environment-based profile selection, or concurrent state machines. Built-in profiles and explicit Swift settings work on Wasm.

## Writing a property

Use `#expect` inside `property`, with the `.hegel` trait on the test:

```swift
import Hegel
import Testing

@Test(.hegel)
func reversingTwice() throws {
    try property { testCase in
        let values = try testCase.draw(.arrays(of: .integers))
        #expect(Array(values.reversed().reversed()) == values)
    }
}
```

The trait can also be inherited from a containing `@Suite`. Swift Testing parameterized tests are not supported; draw the arguments from the test case instead.

`Gen` includes generators for numbers, strings, collections, and tuples. Compose them with `map`, `flatMap`, or a `Gen { testCase in ... }` closure. Use `recursive` for trees, with separate branch and leaf generators. Composed generators retain their component identities for shrinking. Custom `Gen` closures use their declaration site as their identity.

For stateful tests, `@StateMachine` collects methods marked with `@Rule` and `@Invariant`. Hegel generates and shrinks sequences of rules. Invariants run at the start and end of each sequence and at points selected by Hegel. See the [state-machine tests](Tests/HegelTests/StateMachineTests.swift) for examples.

## Failures and configuration

The library suppresses intermediate expectation failures while searching and shrinking. Swift Testing reports the failure from the minimized case with a reproduction blob attached. To replay it, temporarily use `@Test(.hegel.reproducing("..."))`, then remove the reproduction setting to resume normal exploration.

Hegel resolves settings from an engine profile when a property starts. Local runs use `development`: up to 100 valid cases, with failures stored under `.hegel/examples`. Add `.hegel/` to your `.gitignore`. Recognized CI environments select `ci`, which disables the database, enables deterministic unseeded runs, and prints a copy-pasteable reproduction trait.

Define profiles in `hegel.toml` at the package or workspace root:

```toml
[profiles.ci]
test_cases = 1_000

[profiles.nightly]
test_cases = 10_000
```

Select one with `@Test(.hegel.profile("nightly"))`, `HEGEL_DEFAULT_PROFILE=nightly`, or a top-level `default = "nightly"` entry in the file. A custom profile inherits the environment's defaults unless it specifies `extends`; `extends = "base"` selects the plain engine defaults. The engine searches upward from the working directory, or loads the file named by `HEGEL_CONFIG`, and caches the configuration for the process. Invalid configuration is reported as a test error.

Swift settings are explicit overrides: the selected profile is resolved first, then suite overrides and test overrides are applied field by field. For example, a test using `.hegel.verbosity(.quiet)` retains its suite's case count and seed. `@Test(.hegel.profile("nightly").testCases(2_000))` overrides only the profile's case count.
