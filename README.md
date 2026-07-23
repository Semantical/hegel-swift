# hegel-swift

An idiomatic Swift interface to [Hegel](https://github.com/hegeldev/hegel-rust), the property-based testing engine built on Hypothesis.

```swift
try await Hegel.test { testCase in
    let values = try testCase.draw(
        .arrays(of: .integers(in: 0...100))
    )

    guard propertyHolds(for: values) else {
        throw PropertyError(values: values)
    }
}
```

When a property throws, Hegel searches for a smaller counterexample and `Hegel.test` reports one `PropertyFailure` containing both the minimal failure and a reproduction blob:

```swift
try await Hegel.test(reproducing: "...") { testCase in
    // The same property and draws.
}
```

## Artifact

The checked-in static library is Hegel 0.30.1 (`f81c6cceabe3c6695a249588c751a5ce93dffa00`) for `arm64-apple-macosx`. It was built from `hegel-c` with:

```sh
cargo build --release -p hegeltest-c
```
