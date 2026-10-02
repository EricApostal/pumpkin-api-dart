# How the generated API maps WIT

`native/wit_bindgen_dart` turns the WIT into `packages/pumpkin_api/lib/src/bindings.g.dart`.
Beyond a literal translation it applies a few rules, so the raw API already feels
like Dart:

| WIT | Dart |
| --- | --- |
| `option<T>` | `T?` (only `option<option<T>>` keeps the `Option` wrapper, since `T??` collapses) |
| `get-foo` / `set-foo(x)` on a resource | a `foo` property next to the `getFoo()` / `setFoo()` methods (skipped if the types differ or the name is taken) |
| `get-x-data` / `set-x-data(variant)`, a variant whose cases hold records | one *view* per case: the resource known to be of that kind, with the record's fields as properties, plus `asKind()` casts (`entity.asZombie()`) |
| `record` | an immutable class with `copyWith` |
| `own<T>` / `borrow<T>` | a `Resource`, released when the callback returns, see [lifetimes](lifetimes.md) |

```dart
final zombie = entity.asZombie();   // Entity -> Mob -> Zombie view, or null
zombie?.isBaby = true;              // read, copyWith, write back
```

## `copyWith` and optional fields

Optional fields are nullable, so `null` can't also mean "keep the current value".
They get a `clear<Field>` flag instead:

```dart
data.copyWith(signature: bytes);          // set
data.copyWith(clearSignature: true);      // reset to none
```

## When to write a wrapper by hand

Only for real design decisions that aren't in the WIT: defaults, validation,
builders, naming a concept better, accepting a `String` where the host wants a
`TextComponent`. Everything mechanical belongs in the generator, so it stays in
sync with the WIT.
