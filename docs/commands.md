# Commands

`context.command(...)` builds, registers and documents a command in one call:
the command tree, tab completion, usage errors, guards, and the permission node
with its default. The raw `Command`/`CommandNode` API still works underneath.

```dart
@override
void onLoad(Context context) {
  context.command(
    'home',
    description: 'Teleport to a home',
    aliases: ['h'],
    permission: 'teleport:command.home',           // allowed for everyone
    (c) => c
      ..runs((ctx) => goHome(ctx.player, 'home'))    // /home
      ..arg('name', ArgumentTypes.word,              // /home [name]
          optional: true,
          suggestsWith: (s) => homeNames(s.senderName),
          runs: (ctx) => goHome(ctx.player, ctx.stringOrNull('name') ?? 'home'))
      ..sub('set',                                   // /home set <name>
          description: 'Save your position',
          build: (s) => s.arg('name', ArgumentTypes.word,
              runs: (ctx) => setHome(ctx.player, ctx.string('name'))))
      ..requirePlayer()
      ..cooldown(const Duration(seconds: 3), bypass: 'teleport:bypass'),
  );
  context.registerHelp('teleport');                // /teleport [help [command]]
}
```

## The builder

`CommandBuilder` is one node of the tree. The closure you pass to `command`
receives the command itself, `sub` and `arg` hand you a child. Everything is a
cascade-friendly `void` method:

| Method | Does |
| --- | --- |
| `runs(handler)` | runs when the command ends at this node |
| `runsRaw(handler)` | same, for an old `(sender, server, args)` handler |
| `sub(name, {description, aliases, permission, runs, build})` | literal subcommand |
| `arg(name, type, {runs, suggests, suggestsWith, optional, permission, build})` | typed argument |
| `requirePlayer()`, `requirePermission(node)`, `cooldown(d, {bypass})`, `guard(middleware)` | guards for this node and everything below |
| `describe(text)`, `usage` | help text, generated usage lines |

* **Optional arguments.** `arg(..., optional: true, runs: h)` makes both
  `/x` and `/x <arg>` run `h` (unless `/x` has its own `runs`). Read the
  argument with `ctx.stringOrNull(...)`.
* **Handlers** return `void` (success, result `1`) or an `int` result code, and
  may be `async`. The async rules of [async.md](async.md) apply: `ctx`,
  `ctx.sender` and `ctx.server` are only valid until the first `await`.
* Nodes are configured fully before the tree is handed over to the host, which
  consumes them (see [lifetimes](lifetimes.md)); you never touch a node.
* `aliases` of a subcommand build the subtree once per word.

## `CommandContext`

`ctx.sender`, `ctx.server`, `ctx.args` (raw) plus:

* sender: `senderName`, `isPlayer`, `isConsole`, `player` (throws
  `Only players can use this command.`; owned by the callback, `keep()` it to
  hold on), `playerOrNull`, `hasPermission(node)`
* replies: `reply(text)`, `replyLines(lines)`, `replyError(text)`
* failing: `fail(message)` throws a `CommandException`; `usage` is the usage
  text; `failUsage([problem])` throws a `UsageException` that prints it
* arguments: `string`, `integer`, `number`, `boolean`, `blockPos`, `duration`,
  `players` and the `...OrNull` variants. `targetPlayer('x')` /
  `targetPlayers('x')` resolve an `ArgumentTypes.player`/`players` argument
  and fail with `No player was found.` when nothing matches.

The raw `ConsumedArgs` extension has the `...OrNull` variants too. The host
reports a missing argument as empty text, so `stringOrNull` is `null` for it.

## Argument sugar

```dart
ArgumentTypes.oneOf(['survival', 'creative'])  // word + completion + validation
ArgumentTypes.enumValues(GameMode.values)      // same, from enum names
ArgumentTypes.duration                         // 10s, 5m, 1h30m, 2d, 1w, 250ms
ArgumentTypes.player                           // a player or selector
```

`oneOf` matches ignoring case, `ctx.string` returns the spelling you declared,
and a wrong value fails with `Unknown option "x". Choose one of: ...` before
your handler runs. `ctx.duration('time')` parses with `parseDuration`, a pure
function you can also use directly (`parseDuration('1h30m')`).

Tab completion: `suggests: ['a', 'b']` is a fixed list, `suggestsWith: (s) =>
...` gets a `SuggestionContext` (`sender`, `senderName`, `player`, `typed`,
`hasPermission`). Matches are filtered by what was typed, ignoring case.

## Permissions

`permission:` takes a node string or a `CommandPermission`:

```dart
permission: 'teleport:command.home'                       // default: everyone
permission: CommandPermission('x:y', description: '...')  // same, described
permission: CommandPermission.op('x:y', description: '...')   // ops (level 2)
permission: CommandPermission.deny('x:y')                 // nobody by default
```

The permission is registered with the server in the same call (once per node
per plugin; a failed registration logs a warning). The host enforces the
command's permission; the permission of a `sub`/`arg` is registered and
additionally enforced when it runs. Nodes must be `<plugin>:<name>`. With no
`permission:` the node is `<commandNamespace>:command.<name>`: set
`commandNamespace = info.name;` once in `onLoad`, otherwise `command` throws.

## Guards

A guard is a `CommandMiddleware`: `(ctx, next) => ...`, which calls `next()`
to continue or throws a `CommandException`. Built in (`Guards.*`, and the same
named methods on the builder): `requirePlayer`, `requirePermission(node)`,
`cooldown(duration, {bypass})`. A cooldown is tracked per sender name, doesn't
apply to the console, doesn't start when the command fails, and tells the
sender how long to wait. Guards on a node cover everything under it, outermost
first. `guardedHandler(body, middleware)` applies the same wrapping to a handler
you register yourself.

## Usage and help

Usage is generated from the tree: `/home [name]`, `/home set <name>` (an
optional argument folds into its parent's line). `ctx.usage` and
`builder.usage` give it, `ctx.failUsage('Bad amount.')` shows it.

`context.registerHelp('teleport')` registers `/teleport` and
`/teleport help [command]`, listing `usage - description` for every command
registered through the builder (the `commandRegistry`), only lines the sender
may use. Pass `help: false` to `command` to leave one out. Call it after the
other commands.

## Testing

Usage, help, parsing, suggestions filtering and the cooldown tracker are in
`command_help.dart`, which doesn't import the bindings, so they run on the Dart
VM (`dart test`, see `test/command_*_test.dart`). `CooldownTracker` takes a
clock.
