# hegel-swift

An idiomatic Swift interface to [Hegel](https://github.com/hegeldev/hegel-rust), 
the property-based testing engine based on Hypothesis.

```swift
import HegelTesting
import Testing

@Test(.hegel)
func sorting() async throws {
    try await Hegel.test { testCase in
        let values = try testCase.draw(.arrays(of: .integers()))
        #expect(values.sorted().count == values.count)
    }
}
```

Expectation failures produced while Hegel searches and shrinks are suppressed.
Swift Testing reports the first expectation from the minimal counterexample with
Hegel's reproduction blob attached as a comment.

Generators compose:

```swift
let identifier = Generator<UInt64>.integers()
let name = Generator<String>.strings(size: 1...40)
let user = Generator<(UInt64, String)>.tuple(identifier, name)

let users = Generator<[(UInt64, String)]>.arrays(
    of: user.filter { !$0.1.isEmpty },
    size: 0...100,
)
```

The core generator vocabulary includes `map`, `flatMap`, `filter`, `oneOf`,
`optional`, and `sampled(from:)`, along with fixed-width integers,
floating-point values, booleans, bytes, strings, arrays, sets, dictionaries,
and arbitrary tuple arities.

Hegel stores minimized failures under `.hegel/examples` and tries them before
generating new examples. The `.hegel` trait keys this database by Swift
Testing's test identity. Swift Testing parameterized tests are therefore not
supported; draw arguments from the Hegel test case instead.

Treat `.hegel/` as a generated local cache and exclude it from version control.
Hegel disables the default database in recognized CI environments; configure a
custom database path if it is backed by a persistent CI cache.

To debug one exact failure, temporarily configure the test with its reproduction
blob:

```swift
@Test(.hegel(reproducing: "AAEAAAAACgEAAAAF"))
```

Remove the reproduction trait after fixing the failure so the test resumes
exploration. Reproduction blobs are debugging artifacts; the database provides
automatic regression reuse between exploratory runs.

## Artifact

The checked-in static library is Hegel 0.30.1 (`f81c6cceabe3c6695a249588c751a5ce93dffa00`) 
for `arm64-apple-macosx`. It was built from `hegel-c` with:

```sh
cargo build --release -p hegeltest-c
```
