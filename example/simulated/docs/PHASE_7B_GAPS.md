// What this package does not have yet: the rest of Simulated's server content,
// and the host features the port needs.
//
// The phase-7a slice and the payload layer are in place (see the barrel
// `lib/simulated.dart`); this file is the checklist for what follows, so the
// gaps are written down where the next workstream will look.
//
// Every gap below that has a place in the code is also marked there with
// `TODO(parity)`.

# Simulated: what is ported, and what is missing

## In place

| Java | Port |
|---|---|
| `PhysicsAssemblerBlock(Entity)`, `DisassemblyPrevention` | `content/blocks/physics_assembler/` — search, assemble, disassemble, alignment, primary check |
| `util/SimAssemblyHelper`, `util/assembly/SimAssemblyContraption`, `SimAssemblyException` | `util/` — assembly search, move, entity moves, split listener |
| `util/SimMathUtils`, `SimLevelUtil` | `util/` |
| `SteeringWheelBlockEntity` | `content/blocks/steering_wheel/` — angle machine, generated speed, comparator output |
| `ThrottleLeverBlock(Entity)` | `content/blocks/throttle_lever/` — lever state, redstone output |
| `SymmetricSailBlock` | `content/blocks/symmetric_sail/` — lift provider, dye, the placement helper (`symmetric_sail_placement.dart`) and `AXIS` from the clicked face (`PlacementRule.clickedAxis`) |
| `PortableEngineBlock`, `PortableEngineBlockEntity`, `PortableEngineInventory` | `content/blocks/portable_engine/` — the sixteen dyed blocks, the fuel table (`manifest/cooking_fuel.g.dart`), the burn state machine, the kinetic generator, the dye swap and the comparator |
| `HoneyGlueEntity`, `HoneyGlueMaxSizing` | `content/entities/honey_glue/` — volume model, tracker, size rules, and the decision of all three honey glue payloads (`honey_glue_packet_logic.dart`) |
| `SpringBlockEntity`, `SpringItemHandler` (length) | `content/blocks/spring/` — length state machine and the placement rules of `PlaceSpringPacket` (`spring_placement.dart`) |
| `TorsionSpringBlockEntity` | `content/blocks/torsion_spring/` |
| `SwivelBearingBlockEntity`, `SwivelBearingPlateBlockEntity` | `content/blocks/swivel_bearing/` |
| `PlaceMergingGluePacket` (rules) | `content/blocks/merging_glue/merging_glue_placement.dart` |
| `LinkedTypewriterEntries`, `KeyboardEntry` | `content/blocks/redstone/linked_typewriter/linked_typewriter_entries.dart` — key table, pending activation/deactivation sets, wire codec |
| `LinkedTypewriterBlockEntity` (state) | `.../linked_typewriter_logic.dart` — current user, typed text, press/release/bind, disconnect, save packet |
| `ServerRopeStrand` (pure part) | `content/blocks/rope/rope_strand.dart` — points, attachments, sync threshold, extension, first-segment lerp |
| `DiagramConfig`, `NoteConfigs` | `content/entities/diagram/diagram_config.dart` — both the stream codec and `makeDefault` |
| `DiagramEntity` (server part) | `content/entities/diagram/diagram_logic.dart` — frame building (`makeDiagramDataPacket`) and the recording queue |
| `EndSeaPhysics` | `content/end_sea/end_sea_physics.dart` — the record, its NBT (`fromCodec`) form and the clientbound payload |
| `PhysicsStaffAction` | `content/physics_staff/physics_staff_action.dart` |
| `network/packets/**` (37) | `network/` — every payload's `StreamCodec`, `sim_payloads.dart` table, `sim_wire.dart` primitives |
| `network/packets/*#handle` (the 6 with a ported target) | `plugin/sim_payload_handlers.dart` — lookup, reach check, apply; the other 31 are declared-only |
| `util/hold_interaction/HoldInteractionRange` | `util/hold_interaction.dart` — the reach check, projected out of sub-levels |
| `SimPacketManager` (the channel table) | `index/sim_channels.dart` (`SimulatedAddon`) — declared through Create's generic `CreateAddon` hook, the handled six through `CreateRegistry.serverbound` |
| `api/` (10) | `api/` — `BearingSlowdownController`, `SimpleResourceManager`, sounds, `IDirectionalAnalogOutput`, `CustomStressImpactTooltipProvider`, `AnalogSignalSource` |
| `config/` (10) | `config/sim_config.dart` — all five server sections, `SimStress` |
| `service/` (14) | `service/sim_services.dart` — `canStickTo`, dye colours, host seam; the loader-only ones are gone |
| `index/`, `registrate/` | `index/sim_blocks.dart`, `sim_items.dart`, `sim_registry.dart`, `sim_lift_providers.dart`, `sim_channels.dart` |

## The payload layer

All 37 channels of `SimPacketManager` are ported and tested:

- `test/payload_codec_test.dart` pins every payload's bytes against an
  independently written big-endian buffer, so a field out of order, a missing
  `ByteBufCodecs.list` count prefix or a raw-double helper where a list codec is
  used fails the test rather than the client.
- `test/sim_subsystems_test.dart` covers the pure state machines above.

The six channels with a handler (`SimHandledPayloads`) are registered on Create's
payload registry in `SimulatedPlugin.onLoad`
(`registry.serverbound(id, codec, handler, version: '0.1')`), and `CreateNetwork`
dispatches them; the other 31 are declared through
`createAddonNeoForgeDeclaration(SimulatedAddon(handled: SimHandledPayloads.idSet),
registry: _registry)`. Both paths end up in the same registry, so the
declaration carries all 37 exactly once — `test/payload_codec_test.dart`
("addon hook") pins that, because a channel registered twice throws
`DuplicateChannelException` and one in neither would vanish from the answer.
This needs `Permissions.neoforge`. Create names nothing of Simulated: the addon
hook (`CreateAddon`) is generic, and the host merges the declarations of both
plugins.

What the declaration does **not** do: handle every payload. `SimPayloadHandlers`
(`lib/src/plugin/sim_payload_handlers.dart`) subscribes to
`Events.playerCustomPayload`, decodes with `SimPayloads.byId` and dispatches the
six serverbound payloads whose content exists:

| payload | target | Java |
|---|---|---|
| `simulated:assemble` | `PhysicsAssemblerBlockEntity.assembleOrDisassemble` | `AssemblePacket.handle` |
| `simulated:throttle_lever_signal` | `ThrottleLeverBlockEntity.setSignal`, reach-checked | `ThrottleLeverSignalPacket.handle` |
| `simulated:steering_wheel_update` | `logic.targetAngleToUpdate` + `setHeld` | `SteeringWheelPacket.handle` |
| `simulated:place_spring` | `SpringPlacement` rules, two spring blocks, item shrink | `PlaceSpringPacket.handle` |
| `simulated:honey_glue_spawn` | `HoneyGluePacketLogic.onSpawn`, plugin entity, tracker | `HoneyGlueSpawnPacket.handle` |
| `simulated:honey_glue_change_bounds` | `HoneyGluePacketLogic.onChangeBounds`, resize or kill | `HoneyGlueChangeBoundsPacket.handle` |

The remaining serverbound payloads decode but are ignored, because their block
entity, entity or item is not ported yet: `be_observed` (no `Observable`
interface), `configure_altitude_sensor`, `configure_modulating_linked_reciever`,
`nameplate_change_name`, the five typewriter payloads, `place_merging_glue` (no
merging glue block), `update_player_handle`, `ride_rope`, `break_rope`, the two
physics staff payloads, `request_diagram_data` and `save_diagram`. Each is one
case in `SimPayloadHandlers.dispatch` once its target lands.

The reach check is `HoldInteractionRange.within` (`lib/src/util/hold_interaction.dart`):
the block interaction range attribute plus a buffer, measured from the eye, with
the target projected out of its sub-level (`Sable.HELPER.projectOutOfSubLevel`).

## Missing

- **Handlers for the remaining payloads** — see the table above. The pure
  decision each one needs is already there (`HoneyGluePacketLogic`,
  `TypewriterSaveLogic`, `SpringPlacement`, `MergingGluePlacement`,
  `DiagramForces`); what is missing is the block entity or entity they act on.
- **redstone (33 files)** — `redstone_accumulator`, `redstone_inductor`,
  `directional_receiver`, `modulating_receiver`, `analog_transmission`,
  `directional_gearshift`, and the typewriter *block/entity/item/menu* (the key
  table and its state machine are ported, the block is not).
- **rope (19)** — `rope_winch`, `rope_connector`, `RopeStrandHolderBehavior`, the
  `ServerLevelRopeManager`/`ServerRopeTrackingSystem` send paths, and the
  constraint half of `ServerRopeStrand` (`reattachConstraints`: a free
  constraint with motors on every axis, `TODO(parity)` in `rope_strand.dart`).
- **lasers (12)** — `laser_pointer`, `laser_sensor`, `optical_sensor` (needs
  `SimBlockConfig.laserPointerRange` / `opticalSensorRange`, both already in the
  config).
- **auger (10)** — `auger_shaft`, `auger_cog`, encasing.
- **docking (9)** — `docking_connector`, `paired_docking_connector`; needs
  `SimInventoryService` equivalents (battery/tank/inventory) that the host does
  not expose.
- **nav table (7)** — `nav_table`, `navigation_target` datapack registry,
  `SimNavigationTargets`.
- **sensors** — `altitude_sensor`, `gimbal_sensor`, `velocity_sensor`,
  `nameplate`, `lodestone_compass` behaviour (the payloads are ported).
- **diagrams** — the `contraption_diagram` entity, item and screen. The config
  codec, the frame builder and the recording queue are ported; the entity is
  not.
- **end sea** — the dimension overrides (`EndSeaPhysics.physicsTick`, which needs
  Sable's queued force groups and mass tracker). The record and the payload are
  ported.
- **misc content** — `handle`, `physics_staff` (item and
  server handler), `plunger_launcher`, `absorbed` blocks.
- **`compat/` (25)** — mostly out of scope (other mods), except the CC: Tweaked
  peripherals, which are ported under `lib/src/compat/computercraft/`: the twelve
  peripherals of `simulated/common/.../compat/computercraft`, their registry and
  the `AttachedComputerHandler`, over the seam in `api/sim_peripheral.dart`.
  `simulated` imports no computer mod; `example/cc_tweaked` holds the adapter
  (`lib/src/compat/simulated_peripherals.dart`) and the world driver
  (`lib/src/compat/simulated_driver.dart`). Each peripheral is written against a
  small source interface, and the block entity that implements it is only ported
  for the swivel bearing and the torsion spring; the other ten wait for their
  block (`altitude_sensor`, `gimbal_sensor`, `nav_table`, `linked_typewriter`,
  `optical_sensor`, `velocity_sensor`, `directional_receiver`,
  `modulating_receiver`, `docking_connector`, `nameplate`). The docking
  connector's wired element is the noop one, because the Dart CC plugin has no
  wired network.
- **`ponder/` (48)** — client only, out of scope.

## Registry surface

The package registers 39 of the 95 blocks, 25 of the 86 items and 8 of the 30
block entity types, and it **names no registry** in its NeoForge declaration
(`createNeoForgeDeclaration` sets no `NeoForgeRegistryAddition`). That is the
safe state for a partial port, confirmed against the host's sync rules:

* a snapshot is never additive — ids are positions, so a partial list replaces
  what the client has and removes the rest;
* a registry is only sent when the declaration *names* it, and a named
  host-numbered registry (`minecraft:block`, `item`, `block_entity_type`,
  `entity_type`, `menu`, `sound_event`, …) is then filled from the **host's**
  dynamic-registry list, not from the declaration's list;
* naming nothing therefore sends nothing for `simulated`: a client with the mod
  keeps its own ids and the connection is fine.

Expanding to the full surface is what turns a named registry on, and it needs the
complete, name-exact list for the mod — `docs/aero-port-inventory.md` §3.3 and
Appendix B for the order — plus the properties of each block, because the state
ids are derived from them. Until then, do not name `minecraft:block` (or any
other) for this mod.

`TODO(parity)` on the expansion, tracked with `RegistrySyncConnect` (their
answer: expand first, name the registries after the names are verified).

## Host gaps the portable engine hit

* **An item's own data components are not readable.** `ItemStack.getComponents`
  answers with the stack's *patched* components only
  (`pumpkin-wasm-host-v0_2/src/item_stack.rs:701`), and
  `DataComponentCodec.notReadByHost` lists `minecraft:cooking_fuel` as having no
  reader — while the fuel of a vanilla item is a *default* component of its item
  definition. The port therefore carries the resolved table
  (`manifest/cooking_fuel.g.dart`, `tool/generate_cooking_fuel.py`) and a fuel
  component on an item added by a plugin or a datapack does not burn. A host
  import for "the resolved value of component X of this stack" would remove the
  table.
* **No per-state light level.** A plugin block's `luminance` is one number for all
  of its states, so a lit portable engine does not glow (Java: 6 when `lit`).
* **The slot cannot be served by a custom handler.** The host gives a plugin block
  entity a *fixed* inventory it owns (`PluginInventories`, reachable only with the
  asynchronous `ItemHandler` calls); the engine's burn step runs in the synchronous
  block entity tick, so the slot is the entity's own `SmartInventory` and a hopper
  cannot feed the engine (the same gap `create/lib/src/fluids/drain.dart`
  documents). Java's `PortableEngineInventory` is exactly a fixed one-slot
  inventory, so a synchronous handler interface would close this.

## Host gaps that block the slice from being playable

Each is marked in the code where it happens.

1. **Constraint motors — assembler done, bearing pending.** sable's
   `PhysicsConstraintHandle` now has `setMotor`. The assembler's disassembly
   alignment uses it: `PhysicsAssembler._attachAlignmentConstraint` builds the
   spherical joint and `AssemblyAlignmentMotors` (`util/physics_constraints.dart`)
   drives the six axes each tick, so a tilted sub-level is pulled onto the grid
   instead of only being placed when it happens to be close. The swivel bearing
   still computes gains without applying them
   (`SwivelBearingLogic.motorFor` is tested): attaching its hinge needs the
   rotary joint plus the plate's sub-level, which is the same shape but has no
   caller yet.
2. **Sub-level actors inside plots** — `ServerLevelPlot.actorAt` is `null` in sable, so the spring, the swivel plate and the propeller never receive `sable$physicsTick`. The block entities implement `BlockEntitySubLevelActor`; the plot needs the plugin's store behind that hook.
3. **Honey glue as an assembly input** — `PumpkinSimAssemblyWorld.honeyGluesIn` returns nothing: the volumes are plugin entities and the tracker exists (`honeyGlueTrackerOf`), but no entity spawn/remove listener fills it yet.
4. **Sound playback** — `SimSoundIds` is filled by nobody; `playSound` is a no-op. The sound keys and their ids are registered.
5. **Neighbour redstone** — `bestNeighbourSignal` returns a cached value refreshed by nothing; the swivel bearing's lock state therefore stays at its default. `World.getBestNeighborSignal` is async and cannot be awaited from `tick()`.
6. **Entities in a box** — no box query in the plugin API, so
   `PumpkinSimAssemblyEntities.entitiesIn` filters `World.getEntities()` by the
   entity's real bounding box (shared shape with Aeronautics'
   `HostPropellerPushWorld`; both switch to a box query together when the host
   grows one). Movement and removal now work
   (`setPositionRotationDelta` carrying velocity, `Entity.remove`); only
   *spawning* a moved super glue box is a stub, because the plugin API cannot
   summon a vanilla entity type. Honey glue volumes are re-created in the
   plugin's tracker instead.
7. **Chunk serialization for plots** — sable's `PlotChunkHost` gaps (documented in sable) still apply, so a sub-level's plot chunks cannot be saved or loaded by the host.
8. **Statistics and advancements** — the Java handlers award stats
   (`SimStats.INTERACT_WITH_ASSEMBLER`, `TYPEWRITER_KEY_PRESSES`,
   `INTERACT_WITH_STEERING_WHEEL`) and advancements (`UNPOWERED_STEERING`,
   `NOT_GONNA_SUGARCOAT_IT`). The package has no table for either, so the ported
   handlers mark them `TODO(parity)` where Java awards them.
9. **Item durability** — `honeyGlueItem.hurtAndBreak(1, …)` has no host
   equivalent; a stack of one is consumed, a larger stack loses a count.
