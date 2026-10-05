# The Lua engine: decision and design

CC: Tweaked's ROM (`bios.lua` and 219 more files) is Lua. A server side that is
compatible with the real mod has to run **that** Lua, in CC's dialect, safely,
inside a `dart2wasm --standalone` plugin. This page records what was
evaluated, why the plugin ships its own VM, and how that VM is built.

* [Requirements](#requirements)
* [Candidates](#candidates)
* [Decision](#decision)
* [The VM in this package](#the-vm-in-this-package)
* [Sandbox and limits](#sandbox-and-limits)
* [Honest status](#honest-status)

## Requirements

Derived from the mod's source ([client-compat.md](client-compat.md), section 4):

1. **CC's dialect**: Lua 5.1 plus `goto`, `_ENV`, `load` with environment,
   `bit32`, `utf8`, `table.pack/unpack/move`, `__len`/`__pairs`, doubles only.
2. **Coroutines that yield across `pcall`, metamethods and Lua-to-Lua calls**.
   CraftOS runs everything (shell, multishell, `parallel`, `rednet.run`) as
   coroutines inside one main coroutine; `os.pullEventRaw` is `coroutine.yield`
   called from arbitrarily deep, usually inside `pcall`.
3. **A step/time budget**: `while true do end` must not freeze the server
   thread. CC itself aborts after 7 s ("Too long without yielding"); the VM
   must be *resumable after an interruption*, because computers share the tick.
4. The standard library CraftOS uses: full **string library with patterns**
   (`find`, `match`, `gmatch`, `gsub`, `%b`, `%f`, captures, `format`), `table`
   (`sort` with comparators), `math`, `os.*` hooks provided by the host,
   `loadstring`, `load(chunk, name, mode, env)`, `setfenv`, `debug.getinfo`.
5. **dart2wasm compatibility**: no `dart:io`, `dart:mirrors`, `dart:html`,
   `dart:ffi`, no isolates; code that runs inside the plugin's microtask loop.

## Candidates

### ApolloVM (`apollovm` 0.1.48 on pub.dev), the engine the user asked for

* **Languages**: Dart, Java 11, Kotlin, C#, JavaScript, TypeScript, **Lua** and
  Python parse into one shared AST that a tree-walking interpreter runs;
  there is also a WebAssembly compiler. `package:apollovm/apollovm.dart`
  exports only the Dart, Java 11, C# and Wasm front ends; the Lua front end
  (`lib/src/languages/lua/`, 2 300 lines) is reached with
  `SourceCodeUnit('lua', ...)`.
* **Can it run CC's Lua? No.** The Lua front end is a *translation* subset:
  top-level and `local` functions, `local`/global variables, `if/elseif/else`,
  `while`, numeric and generic `for` (`for k, v in ipairs/pairs(expr)` only),
  table constructors, and a table-based "class" convention (`Name = {}`,
  `function Name:method()`). Not present (`lua_grammar.dart`, README feature
  table): varargs (`...`), metatables (`setmetatable`, `__index`, ...),
  coroutines, `pcall`/`error`, `goto`, `try`, closures over mutated upvalues in
  the Lua sense, the `string`/`table`/`math` libraries, `load`, environments.
  `bios.lua` fails to parse at its first `local expect`/`loadstring` block.
* **Host binding model**: external *global functions* are mapped by name on an
  `ApolloRunner` (`mapExternalFunction0..4`, 3 and 4 parameter variants have
  typing bugs, `ASTExternalFunction.call` indexes parameter 4 instead of 3);
  there are no host objects, so a `term.write(...)` style API needs generated
  guest classes on top.
* **Execution limits**: none in the interpreter (`grep` for step, timeout,
  budget, cancel in `lib/` finds nothing outside the Wasm backend). Every AST
  node `await`s, so a runaway guest loop spins in the microtask queue, which
  the plugin runtime drains without returning to the server.
* **dart2wasm**: verified. A plugin that creates an `ApolloVM`, loads a Lua
  code unit and runs it **compiles with `pumpkin build`** (4.3 MB wasm, built in
  6 s, from a throwaway package outside this repository). `package:apollovm`
  imports `dart:io`/`dart:html`/`js_interop` only behind conditional imports
  (`wasm_runtime.dart`: `dart.library.js_interop`, `dart.library.html`,
  `dart.library.io`, with a generic fallback), so the standalone target takes
  the fallback. Its dependencies (`swiss_knife`, `petitparser`,
  `async_extension`, `data_serializer`, `crypto`, `wasm_run`, `wasm_interop`,
  `web`, `path`) are only pulled in as unused code. Whether it *runs* correctly
  there was not tested (no server runs).

Verdict: ApolloVM is fine as a sandboxed Dart/Java scripting engine for the
earlier "CC-like API" idea, and compiles to wasm, but it **cannot execute
CraftOS** and has no preemption, so it is not the engine for the real mod.

### `lua_dardo` (0.0.5)

A Lua 5.3 VM in Dart. Rejected: the package constraint is `sdk <3.0`; it uses
`dart:io` in `basic_lib`, `os_lib`, `package_lib` and the state; **no
coroutines at all** (no `yield`/`resume` anywhere in `lib/`), `xpcall` throws
`todo!`, no instruction hook, integer/float subtypes (`10/2` prints `5.0`,
which breaks CC's output), 5.3 bit operators.

### Other options considered

* Porting Cobalt (the Java VM CC uses): thousands of lines of Java with a
  custom `LuaThread`/`UnwindThrowable` continuation scheme tied to the JVM.
  Not a small port.
* A Dart AST interpreter built on `async`/`await` or `sync*` generators: gives
  coroutines for free but costs an order of magnitude in speed, and the plugin
  runtime drains microtasks without a time check.
* Lua compiled to a bytecode with an explicit frame stack, written in Dart
  (what real Lua and Cobalt do): the only design that gives *all* of: yield
  from anywhere, instruction-level preemption and cheap resume.

## Decision

**A new Lua VM, pure Dart, in `lib/src/lua/`**, about 6 100 lines, binding
free (it analyses and compiles for the Dart VM and for `dart2wasm`), written
for this plugin. It is a compiler (source -> AST -> bytecode) plus a stack
machine with explicit call frames.

## The VM in this package

| File | Role |
| ---- | ---- |
| `value.dart` | value model: `null`, `bool`, `double`, byte `String`, `LuaTable` (array part + insertion ordered hash with tombstones, so `next` survives clearing during traversal), closures, natives, `%.14g` number formatting |
| `lexer.dart`, `parser.dart`, `ast.dart` | Lua 5.1 + `goto`/labels, `\z`, `\xNN`, `\u{}`, hex floats, long strings; names are resolved while parsing (local / upvalue / global) so the compiler knows which locals closures capture |
| `compiler.dart`, `bytecode.dart` | stack-machine bytecode; captured locals live in heap `Cell`s created at their declaration (so loops make fresh cells and `goto` needs no "close upvalue" logic); line table and name hints for error messages ("attempt to call a nil value (global 'x')") |
| `vm.dart` | the interpreter loop, `Coroutine`s with their own stack and frame list, `pcall`/`xpcall` as marker frames, metamethods called as ordinary frames, error unwinding, time slicing |
| `stdlib/` | base, `string` (full pattern matcher ported from `lstrlib.c`, `string.format`), `table`, `math`, `coroutine`, `bit32`, `utf8`, `debug` (tracebacks, `getinfo`, `getmetatable`, `getregistry`) |

Key properties, all of them requirements above:

* **No Dart recursion for Lua calls.** A Lua call pushes a `Frame`; return pops
  it. `pcall` pushes a marker frame and the error handler unwinds frames to the
  nearest marker. Metamethods (`__index`, `__newindex`, `__call`, arithmetic,
  comparison, `__concat`, `__len`, `__unm`) are called by pushing a frame whose
  results land where the instruction's result would be, so a metamethod can
  yield and the call depth is not limited by the Dart stack. Comparison
  metamethods use a result transform (boolean / negated boolean).
* **Coroutines switch stacks.** `coroutine.resume` runs the target's loop
  (recursion only in the number of *nested resumes*, limited to 100);
  `coroutine.yield` returns from that loop with the values. The main CraftOS
  coroutine yields to the host, which resumes it with the next event.
* **Preemption.** Every 256 instructions the loop reads a `Stopwatch`; past
  `deadlineMicros` it stops with all state in the coroutine and `resume`
  returns `Preempted`; the next `resume` continues. Nested resumes propagate it
  (the `CALL` is re-executed with its arguments still on the stack).
* **`_ENV`/environments.** Every closure has an environment table (Lua 5.1
  `setfenv`); a bare `_ENV` is that table, and a user-declared `local _ENV`
  redirects free names. `load(..., env)` sets it; nested functions inherit it.
  This is what `os.loadAPI`, `os.run` and the ROM's `local fs = _ENV` rely on.
* **Strings are bytes**: a Dart `String` whose code units are 0..255, so files,
  the terminal and `#s` behave like CC (UTF-8 appears as several characters).
* **Library errors** carry the position of the calling Lua function
  (`file:line:`), `error(msg, level)` walks the frame list, and tracebacks use
  the frames.
* **Compiled chunks are shared.** `ProtoCache` keeps the compiled `bios.lua`
  and ROM files (immutable prototypes) across computers, so a second computer
  boots without parsing again.

Not implemented (documented deviations): `string.pack/unpack/packsize/dump`,
`os.execute`-style functions (CC has none), `debug.getlocal/getupvalue`
(return nothing), `collectgarbage` (CC has none), `__gc`/`__mode`/`__close`,
integer division and bitwise *operators* (CC has none), `%g` patterns.
Yielding from a `table.sort` comparator or a `string.gsub` callback raises
"attempt to yield across a C-call boundary" (real Lua 5.1 does the same;
Cobalt allows it).

## Sandbox and limits

* The VM has no I/O: the only way out is the native functions the machine
  installs (`term`, `fs`, `os`, `peripheral`, `rs`). `fs` is confined to the
  computer's own mount (`..` is resolved at the root) plus the read-only ROM.
  There is no `io`, `os.execute`, `require` of host code, `http` (CC itself
  removes `http` when disabled; the plugin does not implement it).
* **Time**: each tick every computer runs for at most `slice_ms` (default 3 ms)
  and all together for `tick_budget_ms` (default 12 ms), round robin so that no
  computer is always last. A program that does not yield for `timeout_seconds`
  of *execution time* (7, as in CC) gets the error "Too long without yielding"
  once; if it still does not yield `abort_grace_seconds` (1.5) later the
  computer is shut down with that message, exactly like CC.
* **Code that cannot be preempted** (a `table.sort` comparator, a `gsub`
  callback, any library function that calls back into Lua) may overshoot the
  slice by up to 2 s before it fails with the same error. This is the one place
  the server tick can stall.
* **Memory**: `string.rep` and `..` stop at 64 MiB; call depth is limited to
  7000 frames ("stack overflow"); events are limited to 256 per computer;
  open files to 128; disks to 1 000 000 bytes. Tables have no limit (as in CC).

## Honest status

The VM, the machine and everything else in this package were **written without
ever being executed**: the task rules forbade tests, scripts and test clients,
and no server runs here. What was checked is that `dart analyze` is clean and
that the plugin builds to a wasm component. Expect bugs in a ~6 100 line VM and
a ~3 800 line machine layer on first contact with the real `bios.lua`; the
design above (small instruction set, explicit state) is meant to make them easy
to find. A first thing to try on a server is `/cc new` followed by
`/cc term <id>` with the built-in fallback BIOS, then with the mod jar.
