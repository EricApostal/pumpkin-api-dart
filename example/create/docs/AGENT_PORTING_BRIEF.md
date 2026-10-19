# Porting brief for agents

This file is the shared context for the agents porting Create to Dart in parallel.
Read it before starting.

## Paths

- Project: `/Users/eric/Documents/development/languages/dart/pumpkin-api-dart`
- Target package: `example/create` (Dart, compiled to a wasm Pumpkin plugin)
- Java reference (read-only, Create mid-port to MC 26.3):
  `/Users/eric/Documents/development/languages/java/Create/src/main/java/com/simibubi/create/`
- Host API docs: `/Users/eric/Documents/development/languages/dart/pumpkin-api-dart/docs/`
- Package docs: `/Users/eric/Documents/development/languages/dart/pumpkin-api-dart/packages/pumpkin_api/`

The `read_file` tool cannot leave the project. Read Java files with the terminal, e.g.

```sh
sed -n '1,240p' /Users/eric/Documents/development/languages/java/Create/src/main/java/.../Contraption.java
grep -n "someSymbol" /Users/.../X.java
```

The terminal sandbox only allows writes inside `example/create`.

## Start by reading

- `example/create/docs/ARCHITECTURE.md` (the module contract, registry, block entities, networking,
  config, saved data, testing).
- `example/create/lib/src/core/module.dart`, `registry.dart`, `block_entity.dart`, `blocks.dart`,
  `config.dart`, `network.dart`, `payload.dart`.
- `example/create/lib/src/api/block_state.dart`, `example/create/lib/src/common/*.dart`.
- A complete module for style: `lib/src/redstone/redstone_module.dart` and its subfolders, and
  `lib/src/kinetics/kinetics_module.dart`.
- The generated manifest for exact ids, properties, block entity types, entities, fluids, recipe
  types and payloads: `lib/src/manifest/{blocks.g.dart,items.g.dart,registries.g.dart,network.g.dart,tags.g.dart}`.
  Never hand-edit the manifest; use it.

## Rules

- Only modify files inside `example/create`. Never edit `lib/src/modules.dart`, `pubspec.yaml`,
  `build.yaml`, generated `*.mapper.dart`, or files owned by another agent (each task says which
  files it owns).
- Do not commit.
- Keep pure logic (no host bindings) in files that do not import
  `package:pumpkin_api/pumpkin_api.dart`, so `dart test` can load them. Host-touching code imports
  `package:pumpkin_api/pumpkin_api.dart`.
- Registry keys are `create:<path>`. Dart file names `snake_case`. Classes `<Thing>Block`,
  `<Thing>BlockEntity`, payloads `<Thing>Packet`.
- Do not add `@MappableClass` and do not run `build_runner` (it races with other agents). Use
  hand-written NBT / JSON for new state.
- No TODOs or empty stubs: port the server behaviour faithfully. Client-only rendering, visuals,
  screens, models, particles and sounds are out of scope unless a server decision needs their data.
- Follow the existing code style. Comments explain intent, constraints and Java references; do not
  restate the code.
- Do not duplicate work another module already does. Search before writing (grep for the block id,
  the class name, the service).

## Baseline

`dart analyze` currently reports errors only for the missing files
`lib/src/contraptions/core/contraption.dart` and
`lib/src/trains/track/track_targeting_behaviour.dart` (other agents are creating them). Ignore
those, and do not create them unless your task owns them. All 615 tests in `test/` pass.

## Verification

```sh
cd /Users/eric/Documents/development/languages/dart/pumpkin-api-dart/example/create
/Users/eric/.puro/envs/master/flutter/bin/cache/dart-sdk/bin/dart analyze 2>&1 | grep -E "error|warning" | head -60
/Users/eric/.puro/envs/master/flutter/bin/cache/dart-sdk/bin/dart test
```

If a dart command crashes with a telemetry `FileSystemException`, prefix it with
`HOME=$TMPDIR PUB_CACHE=/Users/eric/.pub-cache`.

Run `dart test` once at the end; the existing tests must still pass.

## Final message

List files created/modified, what is implemented, anything not ported and why, and the
analyzer/test results.
