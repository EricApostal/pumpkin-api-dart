# create

The server side of the [Create](https://github.com/Creators-of-Create/Create)
mod as a Pumpkin plugin written in Dart (dart2wasm component). The foundation
(`lib/src/core`, `lib/src/plugin`) is the module system, registry, block entity
framework with batched ticking, payload networking, config, saved data and the
NeoForge declaration. The game content lives in modules under
`lib/src/<module>/`; `lib/src/modules.dart` is the load order.

Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The content manifest
under `lib/src/manifest/` is extracted from the Java mod and is also the
canonical registration order (`lib/src/manifest/canonical_order.dart`), so the
ids a real Create client uses match the Java mod's registries.

## Modules

| Module | Content |
|---|---|
| `protocol` | the payload bus: all 119 Create/Catnip/Ponder channels |
| `infrastructure` | configs, `/create` commands, worldgen (ores), server speed |
| `content` | damage types, enchantments, sounds, particles, data components, tags, advancements, materials |
| `kinetics` | kinetic network: shafts, cogwheels, gearboxes, clutches, chain drives, motors, water wheels, flywheel, turntable, speed controller, steam engine, gantry shafts, ... |
| `fluids` | pipes, pumps, valves, tanks, spouts, drains, hose pulleys, potions, boiler source |
| `processing` | crushing wheels, millstone, press, mixer, basin, blaze burner, saw, drill, fan/air currents, crafter, deployer, arm, depot |
| `logistics` | packages and package entity, packagers, package ports, stock ticker/link, redstone requester, factory gauge, item hatch, filters, table cloth |
| `conveyance` | belts, chain conveyors, chutes, funnels, tunnels, item vaults, crates, depot/ejector |
| `contraptions` | assembly/disassembly, contraption entities, movement actors (harvester, plough, roller, seats, PSI, controls), actuators (bearings, pistons, pulleys, gantries, elevators, minecart contraptions, chassis, super glue) |
| `trains` | track graph, tracks, signals, observers, stations, schedules, trains, carriages, relocation, train map |
| `redstone` | links, controllers, diodes, display links, nixie tubes, observers, threshold switch, contacts, rails, bells, levers, lamps |
| `equipment` | wrench, zapper, symmetry wand, potato cannon, backtanks, toolbox, bells, blueprint, clipboard, armor |
| `decoration` | palettes, windows/panes, doors, girders, brackets, copycats, placards, whistles, ladders, copper weathering |
| `schematics` | schematic table, schematicannon, uploads, checklist, printer, safe-NBT processors |
| `datapack` | the embedded Create data pack (recipes, loot tables, advancements, tags) |

Client-only content (renderers, visuals, screens, models, particles, sounds)
is intentionally out of scope; the server sends the data a Create client needs.

## Build and test

```sh
puro dart run build_runner build   # regenerate *.mapper.dart after editing models
puro dart test                     # VM tests of the pure parts
puro dart analyze
puro dart run pumpkin_tools build  # build/create.wasm
wasm-tools validate --features all build/create.wasm
```

(`dart` from `$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin` works the
same if `puro` is not on `PATH`.)

Set `"core": {"debug_smoke_test": true}` in the plugin's `config.json` to register
`create:smoke_block`, a framework smoke test (block entity that ticks and persists a
counter). The plugin declares the mod to the host's NeoForge handshake by default,
which a real Create client needs to join at all; `"core": {"neoforge": false}`
turns the declaration off for vanilla-only servers.

The declaration names Create and nothing else. An addon (Sable, Simulated,
Aeronautics, Offroad, or a mod of your own) declares *its own* mod through
Create's generic hook: implement `CreateAddon` from `package:create/create.dart`
(`modId`, `version`, and either a `channels` table or a `contribute` override) and
call `context.declareNeoForge(createAddonNeoForgeDeclaration(const MyAddon()))`.
The host merges every plugin's declaration into the one `neoforge:register`
answer, so a client with the addons negotiates instead of being refused, and
adding another addon needs no change to Create. Each addon's channel table lives
in its own package (`example/sable/lib/sable_channels.dart`,
`example/simulated/lib/src/index/sim_channels.dart`, ...) and is checked against the port
inventory (`docs/aero-port-manifest.json`) by
`test/compat_negotiation_test.dart`.

That is **compatibility, not an implementation**: declaring a channel makes a
client that has the mod negotiate instead of being refused, and nothing in Create
decodes or handles another mod's payloads. The versions have to stay the ones the
client sends (`1` for Sable, `0.1` for the other three) or the negotiation fails
on the version check instead.

`tool/dump_client_channels.dart` writes the channel set such a client answers with,
in the format `pumpkin-tester client --query <file>` takes, so the negotiation can
be checked against a real server without launching the game.

## End-to-end tests against a real server

`puro dart test` runs the pure-Dart tests and covers the pure parts of the port. The
Create-specific questions that only a real run can answer — *was the client told?* — live
in `test/e2e/` and are **off by default**, because they boot a real `pumpkin` process, a
real client process and the built plugin component:

```sh
export PATH="$PATH:$HOME/.puro/bin"
PUMPKIN_E2E=1 \
PUMPKIN_BIN=/path/to/Pumpkin/target/fast/pumpkin \
PUMPKIN_TESTER_BIN=/path/to/Pumpkin/target/fast/pumpkin-tester \
  puro dart test test/e2e
```

Build the pieces first:

```sh
# the plugin component the server loads
puro dart run pumpkin_tools build            # -> build/create.wasm

# the server (from a Pumpkin checkout)
cargo build --profile fast -p pumpkin --features plugin-v0_2

# the simulated client (its `client` mode is the only thing that speaks the protocol)
cargo build --profile fast -p pumpkin-tester
```

| Environment variable | Meaning |
|---|---|
| `PUMPKIN_E2E=1` | run the `test/e2e/` suite at all (anything else skips it with a reason) |
| `PUMPKIN_BIN` (or `PUMPKIN_SERVER_BIN`) | the `pumpkin` binary to boot |
| `PUMPKIN_TESTER_BIN` | the `pumpkin-tester` binary; defaults to the `pumpkin` binary's directory |
| `PUMPKIN_PLUGIN_WASM` | the component to load; defaults to `build/create.wasm` |
| `PUMPKIN_BUILD_PLUGIN=1` | build `build/create.wasm` first if it is missing |
| `PUMPKIN_E2E_KEEP=1` | keep each run's scratch server directory and print its path; it holds `server.log` (the server's console output), `server.trace.jsonl`, and per client `client-<name>.trace.jsonl` and `client-<name>.log` |
| `PUMPKIN_E2E_SETTLE_MS`, `PUMPKIN_E2E_STARTUP_SECONDS`, `PUMPKIN_E2E_STOP_SECONDS`, `PUMPKIN_E2E_JOIN_SECONDS`, `PUMPKIN_E2E_PORT` | timing and port overrides (defaults: 1500 ms of ticking, 300 s to start, 90 s to stop, 60 s to join, a free port) |

How one test reads (`test/support/`):

- `PumpkinLab.boot()` writes a scratch server directory with `plugins/create.wasm` and
  its own `pumpkin.toml`, boots the binary headless, waits for its *own* log line
  ("Server is now running") and checks the plugin was loaded — never a blind sleep;
- console commands go to the process's stdin (the console reads it whenever stdin is not
  a TTY), and `/list` is the barrier that says the commands before it have run;
- `lab.connect('Watcher')` spawns the simulated client; **its trace is the authority on
  what a client received**, and the server's own trace (`PUMPKIN_PACKET_TRACE`) says what
  was enqueued, so "never sent" and "sent but never arrived" stay distinguishable;
- `PumpkinTrace` reads both (`test/support/pumpkin_trace.dart`), groups packets into
  bundles from the delimiters and compares two clients with `VisibilityDiff` — the
  "it only shows up after a relogin" shape, which no server-side assertion can see.

Three rules a new scenario has to follow, all of them learned from real runs:

1. **Build the scenario where the client already is.** The server only sends block updates
   and block entities to players that *track* the chunk, and a console `tp` does not change
   what a player tracks (it never sends the destination's chunk), so
   `lab.playerPosition('Watcher')` reads the position from the server and the blocks go
   next to it. Blocks placed elsewhere produce no packets at all, and the failure looks like
   a plugin that sent nothing.
2. **Place through `placeBlock`, not `setblock` typed once.** Chunk generation is
   asynchronous, so the first attempts answer "That position is not loaded";
   `PumpkinServer.commandUntil`/`placeBlock` retry on the console's own reply.
3. **Assert over the scenario's positions** (`VisibilityDiff.between(early, late, focus:
   {...})`): a live world disagrees with itself between two sessions — ambient mob spawns
   are `add_entity` lines the later client saw and the earlier one never did.

The tests assert the client's side of Create's meaning: a merged tank with the payload and
states the client was told (`tank_client_payload_test.dart`), a contraption arriving with
its spawn payload in one bundle (`contraption_spawn_bundle_test.dart`), and the relogin
diff (`relogin_client_diff_test.dart`). The trace format, the bundle grouping and the diff
are covered by `test/pumpkin_trace_test.dart`, which is part of the fast default suite.

## Differential against a Java server

The end-to-end suite answers "what did a client get from *our* server". The differential
answers the harder question a bug report leaves behind: **"what does a client get from the
Java mod that it does not get from the plugin?"** One command runs the same rig against
both servers, records both, decodes both and prints the first semantic difference:

```sh
cd example/create
export PUMPKIN_BIN=/path/to/Pumpkin/target/fast/pumpkin
export PUMPKIN_TESTER_BIN=/path/to/Pumpkin/target/fast/pumpkin-tester
export PUMPKIN_PLUGIN_WASM=build/create.wasm
export MCTRACE_BIN=/path/to/Pumpkin/target/fast/mctrace   # optional: the raw frames
export MCTRACE_JAVA_DIR=$HOME/Documents/mctesting         # a NeoForge install with the working Create jar

puro dart run tool/diff_servers.dart
```

How it is wired, and why each piece is needed:

- **The Java arm is a real dedicated server, built from an install you already have.** The
  harness symlinks that install's `libraries/` and `mods/`, writes its own
  `server.properties` (`online-mode=false`, its own free port, a fixed seed, a fresh world)
  and boots `java @libraries/.../unix_args.txt --nogui` in a scratch directory. The install
  is read, never modified, and no port a running server of yours listens on is touched.
- **The Pumpkin arm** is `PumpkinServer` from `test/support/pumpkin_server.dart` — the same
  process the e2e tests boot.
- **`mctrace` in front of each** records every frame in both directions, which is the only
  way to see a Java server's traffic (there is no `PUMPKIN_PACKET_TRACE` in a NeoForge
  server). It is optional: without the binary the comparison runs on the two clients' own
  traces, and says so.
- **A `pumpkin-tester client` joins each arm** through the proxy. It is the semantic record
  (`test/support/pumpkin_trace.dart` reads it) and the thing that makes a server send
  anything at all. Both arms get the *same* client: it answers the `NeoForge` handshake with
  the channels the plugin declares (`--query`, the set `test/support/differential/channel_manifest.dart`
  builds). A vanilla client on one arm and a `NeoForge` one on the other would differ by
  construction — the host sends `neoforge:auxiliary_light_data` only to a `NeoForge` client —
  and the comparison would report the harness's choice as if it were the plugin's.
- **The rig** comes from `test/support/differential/scenarios.dart`: a bearing that
  assembles one stone, driven by a creative motor, built in the air above the client (the
  only position that means the same thing on two servers that generate their own worlds).

What is compared is *semantics*, never bytes (`test/support/differential/trace_diff.dart`):
events keyed by position, entity and channel; positions translated into rig coordinates
(the two servers put the rig at different absolute coordinates); block state ids, entity
ids, entity type ids and id-shaped payload leaves renamed through **each server's own**
numbering, so only the equality pattern has to match; payloads decoded as NBT and compared
leaf by leaf (with a number's NBT width, so `0.0 (float)` and `0.0 (double)` are not the
same leaf), so a difference is named as a path (`Contents.Value: 1 (int) vs 2 (int)`)
instead of as two blobs. Packets the trace does not model (keep-alives, time updates) are skipped, and
the skip is counted in the report rather than hidden.

Exit codes are the automation contract: **0** the two arms agree (a real finding — it would
mean the difference is not in the play-phase packets at all), **1** they differ (the report
names the first difference with both servers' own packets around it), **2** the run never
got to compare (an arm failed to start or to join, and the report says which and why).
`--json FILE` writes the same result for CI, `--out DIR` keeps each arm's client trace,
wire capture and console log, and `--keep` keeps the scratch server directories.

Two identical arms are how the comparison itself is checked — it must find no difference
between two runs of the same server:

```sh
puro dart run tool/diff_servers.dart --reference pumpkin --candidate pumpkin
```

| Environment variable | Meaning |
|---|---|
| `MCTRACE_JAVA_DIR` | the NeoForge install to mirror (default `~/Documents/mctesting`) |
| `MCTRACE_BIN` | the `mctrace` binary; defaults to `mctrace` next to `PUMPKIN_TESTER_BIN` |

## Parity tests

`test/parity/` turns the differential into assertions: one file per subsystem, each running the
same rig on both servers and asserting that the two clients were told the same *semantic* events.
They are `@Tags(['e2e'])` and skip with the reason when `PUMPKIN_E2E` is unset, and they need a
Java install for the reference arm (`MCTRACE_JAVA_DIR`):

```sh
export PATH="$PATH:$HOME/.puro/bin"
PUMPKIN_E2E=1 \
PUMPKIN_BIN=/path/to/Pumpkin/target/fast/pumpkin \
PUMPKIN_TESTER_BIN=/path/to/Pumpkin/target/fast/pumpkin-tester \
MCTRACE_BIN=/path/to/Pumpkin/target/fast/mctrace \
PUMPKIN_PLUGIN_WASM=build/create.wasm \
  puro dart test test/parity
```

| Test | Level |
|---|---|
| `contraption_parity_test.dart` | a bearing assembles one stone: block updates, block entity payloads, the contraption entity and its spawn bundle |
| `fluid_tank_parity_test.dart` | two stacked tanks merge: a static block entity payload, compared leaf by leaf |
| `channel_negotiation_parity_test.dart` | the registry/channel level: a client with only Create's channels joins both servers, and both negotiate the same `channel -> version` map (read from the wire by `mctrace`, so it skips without it) |
| `negative_control_test.dart` | the suite's own proof that it can fail: a real run, then one event deleted from one arm, which the comparison must report |

**To add a parity test**, write the rig as a `Scenario` in
`test/support/differential/scenarios.dart` (the console commands both arms are driven with, the
box that is compared around the client, the probes that pin what a trace cannot, and the
precondition the reference arm must satisfy) and register it in `parityScenarios`, then add a
`test/parity/<subsystem>_parity_test.dart` whose body is `expectParity(await runParity(<scenario>()))`;
a test that needs a different client channel set or the handshake instead of a trace passes
`clientQuery:`/`compareTraces: false` to `runParity`, and `test/support/differential/parity.dart`
documents the three outcomes (agreement, difference, and "never got to compare" — which fails, never
skips). The same rig is then runnable by hand with
`puro dart run tool/diff_servers.dart --scenario <name>`. Prove the new test can fail before
trusting it: `negative_control_test.dart` runs a real rig, deletes one event from one arm and
requires the comparison (and `expectParity`) to name it — do the same for the new subsystem's
regression class, because a parity test that has only ever seen two agreeing servers has not been
shown to catch anything.

## Known host limitations

The port keeps the Java behaviour where the host can express it. The remaining
gaps are host API limits, documented at their call sites:

- client-only rendering, GUIs, goggles tooltips and Flywheel visuals are not ported;
- `Block.updateFromNeighbourShapes` has no generic hook (the radial wrench writes
  the complete menu state instead);
- item components are not editable, so some item-bound menus and crafting
  remainders are approximate;
- the host has no fluid flow physics, so honey/chocolate do not spread on their own;
- no vanilla recipe-manager query, so a few vanilla crafting/smelting paths
  (press 2x2/3x3, some potion brewing) are not driven;
- no living-drops/effect/mob-conversion hooks, so a few actor and fan side
  effects are omitted;
- entity inventories (chest minecart contents) and vanilla entity save/load are
  not exposed.
