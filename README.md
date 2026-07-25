# hegel-swift

An idiomatic Swift interface to [Hegel](https://github.com/hegeldev/hegel-rust), 
the property-based testing engine based on Hypothesis.

```swift
import Hegel
import Testing

@Test(.hegel)
func sorting() async throws {
    try await property { ctx in
        let values = try ctx.draw(.arrays(of: .integers()))
        #expect(values.sorted().count == values.count)
    }
}
```

`property` runs inside a Swift Testing test with the `.hegel` trait, applied
directly or inherited from a containing suite.

Expectation failures produced while Hegel searches and shrinks are suppressed.
Swift Testing reports the first expectation from the minimal counterexample with
Hegel's reproduction blob attached as a comment.

Generators compose:

```swift
let identifier = Gen<UInt64>.integers()
let name = Gen<String>.strings(size: 1...40)
let user = Gen<(UInt64, String)>.tuple(identifier, name)

let users = Gen<[(UInt64, String)]>.arrays(
    of: user.filter { !$0.1.isEmpty },
    size: 0...100,
)
```

The core generator vocabulary includes `map`, `flatMap`, `filter`, `oneOf`,
`optional`, and `sampled(from:)`, along with fixed-width integers,
floating-point values, booleans, bytes, Unicode scalars, characters, strings,
arrays, sets, dictionaries, and arbitrary tuple arities.

State machines exercise systems through sequences of named rules. Hegel chooses
and shrinks the rule sequence, while invariants are checked initially and after
every successful rule.

Declare rules and invariants as ordinary instance methods:

```swift
@StateMachine
struct TextMachine {
    var text = ""
    var model: [Character] = []

    @Rule
    mutating func append(ctx: borrowing TestCase) throws {
        let character = try ctx.draw(.characters())
        text.append(character)
        model.append(character)
    }

    @Rule
    mutating func removeLast(ctx: borrowing TestCase) throws {
        try ctx.assume(!model.isEmpty)
        #expect(text.popLast() == model.removeLast())
    }

    @Invariant
    func textMatchesModel() {
        #expect(Array(text) == model)
    }

    @Test(.hegel)
    static func property() async throws {
        try await property { ctx in
            try await ctx.run(Self())
        }
    }
}
```

`Pool<Value>` lets later rules draw values created by earlier rules. While a
state machine is running, its pools share an independent choice stream and can
use the context-free operations below. Equal values remain distinct. A draw
reuses an active value, while `take()` consumes it. A machine containing a pool
is noncopyable and declares `~Copyable` explicitly:

```swift
@StateMachine
struct Machine: ~Copyable {
    var ids = Pool<Int>()

    @Rule
    mutating func create(ctx: borrowing TestCase) throws {
        let id = try ctx.draw(.integers())
        try ids.add(id)
    }

    @Rule
    mutating func remove() throws {
        let id = try ids.take()
        // Remove id from the system under test.
    }
}
```

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
