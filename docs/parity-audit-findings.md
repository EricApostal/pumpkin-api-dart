# Parity audit: consolidated findings

Outcome of the port/26.3 ↔ upstream ↔ Dart audit fleet. Every entry was
confirmed against source on both sides; "unconfirmed" entries say so.

The audit ran in three directions, and the direction of the defect was not what
it first appeared to be:

- **Java port vs upstream Create** — defects introduced by the 26.3 port.
- **Dart plugin vs Java** — defects introduced by the reimplementation.
- **Host (Rust) vs what the plugin needs** — capabilities that do not exist yet.

A meaningful fraction of the "Dart divergences" turned out to be **the Dart
mirror diverging from a Java reference that was already correct** (equip sounds,
belt-funnel shape, pipe constructor width, gantry carriage facing). That is why
every finding below cites file:line on both sides rather than "the Dart looks
reasonable".

---

## 1. Fixed in this sweep

### Load-fatal

| Defect | Cause | Fix |
|---|---|---|
| Plugin aborts on load: `ComponentEncodeException(minecraft:equippable): create:copper_armor_equip is not a known sound event` | `equip_sound` is a `Holder<SoundEvent>` resolved through the **host's** sound registry (`packages/pumpkin_api/lib/src/data_component_codec.dart:288-290`). The plugin registers no sound events — `CreateSounds` only maps names onto vanilla ones for playback. | The three copper wearables name `minecraft:item.armor.equip_gold`, the event the wrapper delegates to (`example/create/lib/src/equipment/equipment_items.dart:88-91`). Audibly identical; subtitle differs. Regression test in `test/equipment_components_test.dart`. |

The module failure rethrows deliberately (`create_plugin.dart:79` — a half
registered module would shift the ids of everything after it), so one bad
component takes the whole plugin down. The `Tried to schedule async operation`
line that follows is the abort path's last message, not a second defect: read
the **first** error.

### Server-killing

| Defect | Cause | Fix |
|---|---|---|
| `Train.burnFuel` NPE on every fuel burn | Passed `null` as `LootContext`; `ResolvableInt.Reference#get` dereferences it unconditionally, and every vanilla fuel is a Reference. | Build a real context from the `ServerLevel`, after the `fuelTicks > 0` early return. |
| `SimpleDatagenIngredient` `AssertionError` on every compat recipe | Was an `ICustomIngredient` whose `test()`/`items()` threw. NeoForge dispatches on `neoforge:ingredient_type`, so datagen emitted the custom form and runtime hit the throwing `test()`. | No longer a custom ingredient: `of(...)` returns a plain `Ingredient` from a stand-alone `Holder.Reference`. `AllIngredients` deleted. 376 recipes regenerated. |
| Item loss on block break (crafter, deployer, brackets, item drain, crushing wheel) | Port had not migrated to `preRemoveSideEffects`. | Migrated per block; `FluidPropagator.propagateChangedPipe` deliberately **left** in `affectNeighborsAfterRemoval` (world-state work, not block-entity work). |
| Sable wire: 4 payload ids wrong | Java `sablePath` strings are `..._sub_level`; the port had `..._sublevel`. | Fixed. A real client saw unknown payload types for every tracking/movement packet. |
| Sable: negative plot chunk decoded as `0xFFFFFFFF` | `ChunkPos.getX/getZ` were not sign-extended. | Fixed. |
| Sable: stale `.slvl` files resurrected on reopen | Region storage did not delete them when an oversized payload was rewritten inline. | Fixed. |
| Sable: `updateMergedMassData` threw on a null tracker | Java no-ops. | Fixed. |

### Wrong behaviour

| Area | Defect | Reference |
|---|---|---|
| Belt run assembly | `createBelts` never created the belt block entities nor ran `initBelt`, so `controllerPos => controller ?? p` made every segment its own controller. `_switch` per segment was **not** the cause (it degraded to a plain `setBlockState`; removed). | `BeltBlockEntity.java:448-468`, `BeltConnectorItem.java:139-142` |
| Cart assembler redstone | `stateIndex` in a neighbour event is a **per-block** index (`block_registry.rs:1185-1190`), not a global state id; decoding it yielded a vanilla block and the guard returned before the `powered` write. | `dynamic.rs:201-221` |
| Contraption capture | No frontier dedup: two neighbours reaching one block captured it twice. | `Contraption.java:241,312-316` |
| Contraption bearing routing | `_moveBearing` ran for windmill/clockwork too, creating phantom stabilized sub-contraptions. | `Contraption.java:366-372` |
| Contraption `shouldUpdateAfterMovement` | False for everything, so vanilla doors stopped notifying neighbours. | `Contraption.java:1409-1416` |
| Funnel filter | All three `extractMatching` passed `(_) => true`; brass funnels with a filter extracted unfiltered items. | `InvManipulationBehaviour.java:117-123` |
| Belt-funnel eligibility | A plain funnel above a depot/ejector was treated as an output. | `DirectBeltInputBehaviour.java:116-136` |
| Chain conveyor | `addConnectionTo` called `prepareStats` instead of `_calculateConnectionStats`; packages did not move on newly chained conveyors. Also stale `reversed`, missing port-route purge, no player-range check. | `ChainConveyorBlockEntity.java:512-524`, `PackagePortTarget.java:167-172`, `BlockEntityConfigurationPacket.java` |
| Deployer | Fake player look never set; 36-slot inventory not serialised (drops lost on unload); `DeployerMode` fallback was `use` not `punch`. | `DeployerBlockEntity.java:333-337` |
| Train | `assemblyDirection` written as enum name not lowercase; bell/custom-head sounds wrong; 17 `create.train.status*` keys missing; paused trains fell through to `RUNNING_MANUALLY`. | `CarriageContraption.java:193`, `ArrivalSoundQueue.java:132`, `TrainMapSync.java:277-293` |
| Fluid network | Portable fluid interface not pipe-connectable; nether evaporation missing; tank comparators and light not updated; smart-pipe placement and valve axis wrong; pipe transforms unreachable. | `PortableFluidInterfaceBlockEntity.java:57-133`, `FluidTankBlock.java:115-122`, `DirectionalAxisKineticBlock.java:55-99` |
| Redstone | `e.face` **is** vanilla `side` (`dynamic.rs:585`), so contact/bell/lever were inverted. Observer container pulse used a per-tick latch. | `RedstoneContactBlock.java:137-140`, `AnalogLeverBlock.java:83-85`, `DeskBellBlock.java:104-106`, `SmartObserverBlockEntity.java:141-157` |
| Item attributes | Invented components (`washable`, `smeltable`, …) replaced with real recipe lookups; `max_enchanted`, `equipable`, shulker fill level, colour set, book generation. | `AllItemAttributeTypes.java:51-93` |
| Placement rules | 5 of 8 reported divergences were real; 3 were audit error (gantry carriage takes `getClickedFace()`, chassis sneak fall-through is `RotatedPillarKineticBlock`'s rule). | see `example/create/docs/placement-host-gaps.md` |
| Java render | `VirtualRenderWorld` returned the dimension's cardinal lighting instead of flat `1f`; station markers lost with the 26.3 codec rewrite; tank surface culled; potion tint unregistered. | `VirtualRenderWorld.java:332-335`, `MapItemSavedData.java:48-61`, `FluidTankRenderer.java:120-123` |

---

## 2. Host capability gaps

Each entry is a capability the plugin needs and the host does not expose.
Implementing them is the single highest-leverage remaining work: several Dart
features are written, tested and inert without them.

### P0 — blocks a shipped feature

| Gap | Why it matters | Where it bites |
|---|---|---|
| `setBlockState` deadlocks when the target block has an `onPlaced` hook | A plugin calling `setBlockState` on such a block re-enters the host while the first call holds the lock. | Any plugin placement path. |
| No `clear-fluid-ticks` / `clear-area` | Placing a fluid source cannot cancel the ticks the old state scheduled, so the fluid re-flows. | `FluidFillingBehaviour.java:196-201` |
| No plugin sound-event registration | Any `Holder<SoundEvent>` naming a plugin sound throws at component encode, which aborts the module and then the plugin. | `data_component_codec.dart:288-290`; worked around in §1. |
| Only one block may link to one item | Java maps 16 sail colours onto `create:sail` item semantics. | Dyed sails unplaceable. |
| Sable: no `PhysicsConstraintHandle.setMotor` | Alignment and swivel-hinge gains are computed and cannot be applied. | `example/simulated` swivel bearing, `aeronautics` gyroscopic tilt |
| Sable: `ServerLevelPlot.actorAt` is `null` | Actors (spring, plate, propeller) get no physics tick. | all of `example/simulated` |
| Sable: `MassTracker`/`MergedMassTracker` unimplemented | `onSubLevelAdded` throws on the first assembled sub-level; masses never merge. | every sub-level |

### P1 — wrong or missing behaviour in normal play

| Gap | Why it matters |
|---|---|
| Entity query by AABB | Propeller push maths is complete and unit-tested but no candidates arrive. |
| Block clip / raycast | Balloon airtight scan falls back to a vertical scan instead of `Level.clip`. |
| Entity-ticking / simulation-distance query | `isActiveChunk` degrades to `isLoaded`; trains tick in unloaded-simulation chunks. |
| Entity serialiser | Mobs do not travel through portals with a carriage. |
| Leash holder | A mob cannot be matched to the player leading it. |
| Container view of an entity | `MountedContraptionHooks.externalInventory` unimplemented. |
| Furnace-minecart fuel get/set | `OrientedContraptionHooks.powerFurnace` unimplemented. |
| Placement vocabulary (6 gaps) | `looking-axis`, `clicked-block-property`, `clicked-horizontal-face`, `refuse-when-clicked-face-axis`, `neighbour-shaft-axis`, `when-clicked-face-axis`. Exact WIT shapes in `example/create/docs/placement-host-gaps.md`. |
| Sable: no UDP server | Tracking always uses TCP; the client's UDP handshake never completes. |
| Sable: no static/no-physics pipeline | A level without a physics backend has no fallback. |
| Sable P0: plot chunk tickets, chunk send, entity collision boxes | Sub-levels cannot be sent to a client. |

The full Sable inventory (34 gaps, 7 critical, each with the required exposure
and an interim workaround) is `example/sable/lib/src/sublevel/vanilla/host_gap.dart`.

---

## 3. Known limitations accepted deliberately

- `mayInteract` (spawn protection/claims) has no host binding; the host's break
  events remain the protection hook.
- Break particles are client-only.
- `CarriagePassenger.saveAsPassenger` returns `null` (no entity serialiser).
- `GlobalStation.mailHooks` is null: the logistics module has no postbox block
  entity or package inventory to implement `MailTransferHooks` against.
- `in_item_group` item attribute is always empty: the plugin API exposes neither
  creative tabs nor their contents.
- Attribute selection for logistics filters is stored in `custom_data` rather
  than `attribute_filter_matched_attributes`: the `create:item_attribute_type`
  registry is not registered with the host, so there is no type id and no codec
  that delimits per-type payloads. Declared `approximate` in
  `example/create/lib/src/content/components.dart:96-105`.
- One deliberate Java deviation: the arrow-impact patch subtracts a ship-local
  position from a level-space hit location; the port keeps the arrow's delta in
  level space so the arrow actually reaches the hit point
  (`example/sable/lib/src/sublevel/vanilla/projectile_handlers.dart`).
