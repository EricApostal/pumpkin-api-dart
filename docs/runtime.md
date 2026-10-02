# The Dart runtime in plugins

Plugins are compiled with `dart2wasm --standalone`, which has no JavaScript host
and leaves the platform's text, number and time functions to an *embedder*. That
embedder is `packages/wasm_components` (`lib/src/embedder`). This is what works.

| Area | Status |
| --- | --- |
| Strings: concatenation, search, `replaceAll`/`replaceFirst`/`replaceRange`, case conversion, code units, `String.fromCharCode(s)` | works |
| `RegExp`: full ECMAScript syntax (groups, named groups, lookahead/lookbehind, lazy quantifiers, back references, `i`/`m`/`s`/`u` flags), `replaceAll(RegExp, ...)`, `allMatches` | works, pure Dart engine in `lib/src/text/regexp.dart` |
| `double`: `toString`, `toStringAsFixed`/`Precision`/`Exponential`, `double.parse`/`tryParse` | works, exact (BigInt) arithmetic in `lib/src/text/double_format.dart` |
| `dart:math` (`sqrt`, `pow`, `sin`, `log`, `Random`, `Random.secure`) | works (libm in `native/runtime_helpers`, randomness through `wasi:random`) |
| `DateTime.now()`, `Stopwatch`, `Duration` | works, always UTC |
| `dart:convert`: `jsonEncode`, `jsonDecode`, `utf8` | works |
| `Set`/`Map` of any object, `BigInt`, `Uri`, `runtimeType` | works |
| `async`/`await`, `Future.delayed`, `Timer`, `Timer.periodic` | works on the server's tick loop, see [async.md](async.md) |
| `print` | goes to the server log at info level |
| `Expando`, `WeakReference`, `Finalizer` | work, but there is no garbage collector hook in a component, so weak references never clear, expandos never drop entries and finalizers never run |
| `dart:io`, `dart:isolate`, `dart:ffi` | not available. Use the host API (and WASI, with the plugin permissions) instead |

The regexp and number algorithms are covered by differential tests against the
Dart VM (`dart test packages/wasm_components`), thousands of random inputs
each. `tool/runtime_check.sh` runs the whole table above inside a real server
and is the first thing to run after changing the compiler or the embedder.

## Writing embedder functions

The SDK declares what it needs in `dart:_embedder`
(`sdk/lib/_internal/wasm/standalone/embedder.dart`); the matching functions are
exported from `lib/src/embedder/*.dart` with `@pragma('wasm:export')`. The
compiler links each SDK import against the export of the same name. A program
that references an import without an implementation fails to build with
`Unknown import dart:<name>`.
