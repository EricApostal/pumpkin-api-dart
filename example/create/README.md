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
counter). `"core": {"neoforge": true}` declares the mod to the host's NeoForge
handshake.

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
