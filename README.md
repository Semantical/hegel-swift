# Hegel for Swift

Property-based testing for [Swift Testing](https://github.com/swiftlang/swift-testing), powered by [Hegel](https://github.com/hegeldev/hegel-rust). Hegel generates test inputs and shrinks failures to small counterexamples.

> [!IMPORTANT]
> `hegel-swift` is very much a work in progress. It ships custom-built Hegel binaries, breaking changes are expected, and `hegel-rust` itself is unstable.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/semantical/hegel-swift", from: "0.2.0")
```

Then add its `Hegel` product to your test target:

```swift
.product(name: "Hegel", package: "hegel-swift")
```

The package requires Swift 6.3 or later. The bundled libraries cover these targets:

| Platform                     | Architectures |
|------------------------------|---------------|
| Linux (glibc)                | arm64, x86_64 |
| macOS 26 or later            | arm64         |
| Windows (MSVC)               | arm64, x86_64 |
| WebAssembly (WASI Preview 1) | wasm32        |

The `HegelMacros` trait is enabled by default. To use Hegel without its state-machine macros, add `traits: []` to the package dependency. When working on this repository, `swift test --disable-default-traits` selects that same configuration.

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

The trait can also be inherited from a containing `@Suite`. For asynchronous code, use `try await property`. Swift Testing parameterized tests are not supported; draw the arguments from the test case instead.

`Gen` includes generators for numbers, strings, collections, and tuples. Compose them with `map`, `flatMap`, or a `Gen { testCase in ... }` closure. Use `recursive` for trees, with separate branch and leaf generators.

For stateful tests, `@StateMachine` collects methods marked with `@Rule` and `@Invariant`. Hegel generates and shrinks sequences of rules. Invariants run at the start and end of each sequence and at points selected by Hegel. See the [state-machine tests](Tests/HegelTests/StateMachineTests.swift) for examples.

## Failures and configuration

The library suppresses intermediate expectation failures while searching and shrinking. Swift Testing reports the failure from the minimized case with a reproduction blob attached. To replay it, temporarily use `@Test(.hegel.reproducing("..."))`, then remove the reproduction setting to resume normal exploration.

By default, Hegel runs up to 100 valid cases and stores failures under `.hegel/examples` for later runs. Add `.hegel/` to your `.gitignore`. Recognized CI environments disable the default database; use `.database(.path("..."))` if you want to keep it in a CI cache.

Configure individual tests or suites through the trait, for example `@Test(.hegel.testCases(1_000).database(.disabled))`. See [Settings](Sources/Hegel/Settings.swift) for the available options.

## Bundled binaries

Hegel is a Rust dependency, so we currently build its static libraries ourselves, pending [upstream static artifact publication](https://github.com/hegeldev/hegel-rust/pull/383). The package includes these builds in `Artifacts/CHegel.artifactbundle`. You do not need a Rust toolchain to use it.

The bundled engine is Hegel 0.34.0.
