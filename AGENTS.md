# hegel-swift

A wrapper of `hegel-rust`, idiomatic to both Swift and Hegel.

## Verification

Use `swift test -q`.

## Code

- Always use `var` over `let` for stored struct properties.
- Push for structured concurrency, avoid unstructured `Task` where possible. No @unchecked Sendable.
- Keep the good path unindented with early returns.
- Add comments when they clarify a non-obvious invariant or tradeoff.
- When deciding location of code: the more similar code is, the closer together it should be. At the same time, do not blindly append to existing files.
- Use `// MARK: - [section title]` for significant thematic breaks. Titles often correspond to names of types.
- Preconditions for internal invariants are encouraged.
- Prefer exhaustive switches.
- Whenever possible use maximum sugar: `T?` over `Optional<T>`, `[T]` over `Array<T>`, `some Protocol` instead of `<T: Protocol>`, etc.
- Wrap judiciously: rarely before column 80; to taste up to 100; swift-format will force wrap after.
- Never use `@testable import`. Use `package` access level where required instead.
