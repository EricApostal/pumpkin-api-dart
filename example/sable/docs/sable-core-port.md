# Sable core port — what is here

The sub-level core (inventory slice **S1**): the sub-level and plot model, the
container, storage, tickets, tracking points, the tracking system and the
physics boundary. Everything below is pure — it loads on the plain Dart VM, and
`test/` exercises it against in-memory host fakes.

Java tree: `sable/common/src/main/java/dev/ryanhcode/sable` at `227077f`
(`port/26.3`). One Dart file per Java class, with the Java site in the header.

## Ported

| Java | Dart | Notes |
|---|---|---|
| `sublevel/SubLevel.java` | `model/sub_level.dart` | pose, global bounds, removal flag, plot creation |
| `sublevel/ServerSubLevel.java` | `model/server_sub_level.dart` | tracking players, networked pose/bounds, queued forces, split-from, mass tracker, **full `prePhysicsTick`** |
| `api/sublevel/SubLevelContainer.java` | `model/sub_level_container.dart` | plot yard, occupancy, allocation, lookup, removal |
| `api/sublevel/ServerSubLevelContainer.java` | `model/server_sub_level_container.dart` | force-load tickets, holding chunk map, dependency chain, close/dispose |
| `sublevel/plot/LevelPlot.java`, `ServerLevelPlot.java` | `model/level_plot.dart`, `model/server_level_plot.dart` | chunk grid, bounds, save/load, lift providers, contraptions |
| `sublevel/plot/PlotChunkHolder.java` | `model/plot_chunk_holder.dart` | chunk bounds, block changes |
| `sublevel/storage/**` | `storage/**` | holding chunk map, region files, serializer, saved data |
| `sublevel/system/SubLevelTrackingSystem.java` | `system/tracking_system.dart` | full sync, tracking set, bounds updates, snapshot batching |
| `sublevel/system/SubLevelPhysicsSystem.java` | `system/physics_system.dart` | substeps, poses, punches, chunk tickets |
| `sublevel/tracking_points/**` | `tracking_points/tracking_point.dart`, `tracking_point_observer.dart` | points, save/load, `take`, **projection on removal** |
| `api/SubLevelHelper.java` | `api/sub_level_helper.dart` | entity projection, velocity, dependency chains |
| `api/block/**` | `api/block/**` | lift providers, actors, collision shapes, custom centre of mass |
| `api/physics/**` | `api/physics.dart`, `api/physics_pipeline.dart`, `api/physics_capabilities.dart`, `api/physics_pipeline_provider.dart`, `api/physics_constraint.dart`, `api/physics_rope.dart` | force groups, handles, mass, constraints, the provider registry, the capability declarations |
| `api/physics/PhysicsPipelineProvider.java`, `physics/impl/none/StaticPhysicsPipeline*.java` | `api/physics_pipeline_provider.dart`, `physics/impl/none/static_physics_pipeline.dart` | priority selection and the no-op fallback pipeline |
| `api/math/**`, `util/**` | `math/**`, `util/**` | vectors, poses, boxes, bit grids, NBT, UUIDs |
| `index/SableAttributes.java`, `SableTags.java`, `SableToasts.java` | `index/sable_index.dart` | two attributes + `getPushCooldownTicks`, seven tags, three toast tokens |
| `network/**` | `network/**` | 17 TCP payloads, 6 UDP kinds, codecs |

### Closed in this wave

These were stubs or missing before:

* `ServerSubLevel.prePhysicsTick` — the whole force pipeline: block-entity
  actors, lift/drag from the plot **and from kinematic contraptions**, the
  `-1/2.1 · dt · gravity` velocity term, the floating-block controller, the
  reaction-wheel manager and the final impulse pair
  (`ServerSubLevel.java:303-398`).
* `ServerSubLevel.setName` now sends `ClientboundChangeSubLevelNamePacket` to the
  tracking players (`ServerSubLevel.java:420-425`) through an installed
  `SubLevelPacketSink` instead of dropping it.
* `SubLevelTrackingPointObserver` — tracking points are projected into world
  space when their sub-level is deleted (`SubLevelTrackingPointObserver.java:26-44`).
* `ServerSubLevelContainer.collectForceLoadedSubLevels` now walks
  `SubLevelHelper.getLoadingDependencyChain` (`ServerSubLevelContainer.java:238-257`).
* `ServerSubLevelContainer.isInvalid` / `destroyAllBlocks` — an invalid mass
  tracker destroys the blocks and removes the sub-level
  (`SubLevelContainer.java:146-153`).
* `ServerSubLevelContainer.close` disposes the physics pipeline before closing
  the holding map (`ServerSubLevelContainer.java:325-331`).
* The heat map exists when splitting is on: Java constructs it eagerly
  (`ServerSubLevel.java:90-91`) and ticks it at `203-205`; here it is built on
  the first tick that needs it, from the container's config.
* Snapshot batching matches Java: a player whose updates are all
  `stop_moving` gets no snapshot info, and the TCP fallback wraps each batch
  with its own info payload (`SubLevelTrackingSystem.java:370-404`).
* `ServerSubLevelContainer` carries the `SableConfigLike` its sub-levels are
  created with (Java reads the `SableConfig` statics).
* The shared `ChunkPos.pack` helper is used instead of a second copy.

### Closed in this pass (core completion)

* **`StaticPhysicsPipeline` + `StaticPhysicsPipelineProvider`**
  (`physics/impl/none/static_physics_pipeline.dart`): the no-op fallback that
  keeps sub-levels static when no solver is registered. `addSubLevel` returns a
  `StaticBodyHandle`, `readPose` copies `logicalPose`, `teleport` writes it, and
  `getNextRuntimeId` is the Java constant `0`
  (`StaticPhysicsPipeline.java:16-166`).
* **`PhysicsPipelineProviders`** (`api/physics_pipeline_provider.dart`): the
  `ServiceLoader` replacement. `resolve()` picks the highest
  `PhysicsPipelineProvider.loadPriority`, keeps the first on a tie (Java's
  `Stream.max`) and throws when nothing is registered
  (`PhysicsPipelineProvider.java:27-41`). The static provider is `900`, below
  the `1000` default, so it is only the fallback.
* **`GridQuats`** (`util/sable_math_utils.dart`): the five Java bit-pattern
  groups (`ALL`, `X_AXIS`, `Y_AXIS`, `Z_AXIS`, `REAL`) and `opposite()`.
  `SubLevelEntityCollision.getHitBoxYaw` now snaps to `REAL`, as
  `SubLevelEntityCollision.java:507` does; the port used every grid quaternion,
  which produced a different yaw for orientations between the quarter turns.
* **Dependency-chain unloading** (`storage/holding/sub_level_holding_chunk_map.dart`):
  `moveToUnloaded`, the unload path and `saveAll` now walk
  `SubLevelHelper.getLoadingDependencyChain` instead of a one-element chain
  (`SubLevelHoldingChunkMap.java:177,234,615`). A sub-level that intersects
  another (or is named by an actor's loading dependencies) is now saved and
  unloaded with it.
* **`FloatingBlockData.computePressureScale` no longer mutates the pose**
  (`physics/floating_block_data.dart:80-85`). The first port wrote
  `pose.position() + R·weightedPosition/scale` back into the pose's position
  vector; `FloatingBlockData.java:48-53` writes it into its temporary, so every
  pressure sample was teleporting the sub-level. Regression test:
  `test/floating_block_test.dart`, "computePressureScale never mutates the
  sub-level pose".
* **`SubLevelAssemblyHelper.kickFromContainingSubLevel` no longer corrupts the
  kick** (`api/sub_level_assembly_helper.dart:238-255`). Two in-place bugs, both
  from Dart's `Vector3d.sub`/`cross` mutating their receiver where JOML's
  `sub(other, dest)`/`cross(other, dest)` write into a `dest`:
  the local offset was subtracted from the sub-level's own position vector, and
  the `ω × r` cross product was written into `containingAngularVelocity`, so the
  angular velocity handed to the pipeline was `ω × r + v` instead of `ω`.
  Regression test: `test/lifecycle_state_test.dart`, "the kick uses ω × r + v
  and leaves the input velocities untouched".
* **`BlockSubLevelLiftProvider.contributeLiftAndDrag` no longer mutates the
  angular velocity** (`api/block/block_sub_level_lift_provider.dart:181-184`).
  Java takes both velocities as read-only `Vector3dc`; the port's
  `angularVelocity.cross(temp)` overwrote the caller's vector, so the second
  lift provider on a sub-level (and the floating-block controller after it)
  saw `ω × r` instead of `ω`. Regression test:
  `test/w3_actor_api_test.dart`, "the contribution never mutates the velocity
  arguments".
* `/sable translate` computes its destination into a temporary instead of
  adding in place to `logicalPose.position()`
  (`SablePhysicsCommands.java:257`).
* `NetworkNbtMap`/`NbtFields` and `SubLevelDataAccessor` are exported from the
  barrel (they are pure, and the tests and other slices use them).

### Tests added in this pass

| File | Covers |
|---|---|
| `test/physics_boundary_test.dart` | provider selection/priority/ties, the static pipeline's body/box/rope handles, `readPose`/`teleport`/impulses, constraint axis constants and configurations, `RopeAttachmentPoint` |
| `test/floating_block_test.dart` | `FloatingBlockData` accumulation/removal/outer product/pressure sampling (including the pose regression), `FloatingClusterContainer` grouping and queued changes, material NBT, the material registry, controller centre-of-mass nudges |
| `test/lifecycle_state_test.dart` | `SubLevelTicketLoadingSystem` add/unload/remove, `SubLevelHoldingChunkMap` pack/unpack/status/dependency-chain unload, `SubLevelDataAccessor`, `SableCommandState` |
| `test/pure_helpers_test.dart` | `SableMathUtils.getAngularVelocity` and `GridQuats`/`clampQuaternionToGrid`, `HeatDataChunkSection`, `WaterOcclusionContainer` (with and without a pose), the schematic context and its restore-on-throw, `NbtFields`, `EntitySubLevelUtil` |

## The plugin wire-up (`lib/src/plugin/`)

Java attaches a `ServerSubLevelContainer` to every `ServerLevel` from a
level-load mixin, so `SubLevelContainer.getContainer(level)` always finds one.
The model cannot do that itself: `SubLevelContainer.of(level)` reads a static map
that only a plugin can fill, and until it is filled every assembly throws
`Level <dimension> has no sub-level container`.

`SablePlugin` now owns that:

* **One container per loaded level.** The host loads plugins on the first tick,
  *after* the worlds are loaded and `worldLoad` has fired, so `onLoad`
  enumerates `Server.getAllWorlds()` (`_openLoadedWorlds`) and keeps the
  `worldLoad` subscription for worlds created later. The kept `World` handles
  back `PumpkinSableLevel`, whose `dimensionId` is the dimension key the
  container map is keyed by.
* **Geometry** comes from the model's constants
  (`SubLevelContainer.defaultLogSizeLength` 7, `defaultLogPlotSize` 7,
  `defaultOrigin` 10000); the Sable config has no keys for them.
* **Storage.** `SubLevelStorage` is rooted at
  `<plugin data>/sublevels/<dimension id, ':' -> '_'>` (`PumpkinFileStore` over
  `DataFolder`, hence `fs.write.data`), and the container is initialized with it
  (`initializeWithStorage`), which installs the ticket loading system, the
  holding chunk map and the load-failure sink.
  `World.getId()` is `world` for *every* dimension in Pumpkin, so keying the
  storage by it made all three dimensions share one store: the nether's and the
  end's empty save overwrote the overworld's saved data (`{tickets: []}`) and
  their holding chunks would have collided. Java roots one shared
  `<save root>/sublevels` for the whole server; the sandbox has no world path, so
  the port keeps the per-dimension split the containers already assume.
  * **The payload codec is Sable's own**: `NbtSubLevelCodec` (gzip NBT, i.e.
    `NbtIo.writeCompressed`/`readCompressed`, what `SubLevelStorageFile` writes;
    the gzip is `util/gzip.dart`, because the wasm component has no `dart:io` and
    the API exposes no compression). `JsonSubLevelCodec` is only for tests; it
    cannot read a Java payload and Java cannot read what it writes.
  * **`saveAll` runs on the level save** (`Events.worldSave`, where Java hooks
    `ServerLevel.save`) and again on unload/shutdown, so the region files (the
    holding chunks' pointers) and the payloads reach disk. Nothing needs to be
    flushed by hand: before this, only payloads were written at close and
    everything unloaded was lost.
  * **The saved data is written too**: `SavedDataFiles` keeps the three Java
    saved-data objects (`sable_sub_level_occupancy`,
    `sable_sub_level_force_load_tickets`, `sable_tracking_points`) as gzip NBT
    files under `sublevels/<dimension>/data/<name>.dat` — the payload bytes are
    Java's, the folder is the plugin's, because the API has no `getWorldPath`.
    The occupancy and the tickets are read back at level open, *before*
    `initializeWithStorage`, so the ticketed sub-levels force-load again, and the
    number snatched back from disk is logged on open
    (`SubLevelHoldingChunkMap.snatchLog`) — a restore that finds nothing must
    say so, because the ticket is the only thing that can load the sub-level.
    `SubLevelLoadingTicketType.registry` installs its built-ins when it is first
    touched: Dart's statics are lazy, so `byName` on a fresh plugin instance
    otherwise searched an empty registry and dropped every saved ticket as an
    "unknown type".
  * **A payload that does not decode is loud**: `SubLevelStorage.onError` is
    installed (the plugin logs at error level, like the Java `LOGGER.error`); with
    no sink the storage throws. `SubLevelStorageFile.read` distinguishes an empty
    slot from an undecodable payload (`SubLevelPayloadException`).
  * **Plot chunk keys are Java's**: `chunks` is keyed by the packed `ChunkPos`
    (`"<packed long>"`); the port's old `"x,z"` form still loads, an unreadable
    key is reported (`ServerLevelPlot.onChunkKeyError`) instead of dropped.
    The chunk *body* is still the port's (`blocks`/`block_entities` from
    `MemoryPlotChunk`, since Pumpkin cannot hand a plugin a real `LevelChunk`),
    so a Java-written plot body is not decoded and a port-written one is not
    read by Java.
* **Registration and announcement**: `SubLevelContainer.register(container)`,
  then `fireSubLevelContainerReady(level, container)`
  (`api/event/sable_sub_level_container_ready_event.dart`, which also calls
  `SablePlatform.onSubLevelContainerReady`).
* **Ticking**: one `worldTick` handler ticks the container of the world that
  ticked; a container whose tick throws is left un-ticked with one error log
  instead of failing on every tick.
* **Physics and tracking.** `PhysicsPipelineProviders` gets the no-op fallback
  registered (`StaticPhysicsPipelineProvider`, priority 900 — the component that
  links a solver registers that instead, at the Java-default priority 1000), and
  each container gets a `SubLevelPhysicsSystem` (`initialize()`d) and a
  `SubLevelTrackingSystem`. The physics system is what runs
  `MassTracker`/`buildMassTracker` and `pipeline.addSubLevel` in
  `onSubLevelAdded`, so a sub-level assembled after this has a mass tracker and a
  physics body. Attaching it **before** `SubLevelContainer.register` matters: an
  assembly allocates a sub-level and immediately reads `massTracker`.
* **Unload**: `worldUnload` (and plugin unload) closes the container, unregisters
  it, closes the tracking system and the storage and releases the kept world
  handle.
* `/sable` is registered over a `SableCommandState` whose `levelOf` resolves a
  command's `World` to the container's level view. The `sub_level`/`target`
  arguments that take a selector (`@e`, `@l`, …) are `greedyString`, not `word`:
  Brigadier's `word()` stops at the `@`, so `sable info @e` was a parse error.
* `SableAssembleCommands`' trailing check is now `_reportAssembly`: an invalid
  (present but empty) tracker still fails the command, but a **missing** tracker
  no longer reports "No blocks to assemble." after the blocks moved — it says the
  level has no physics system, which is the real cause (`massTracker ?? true` used
  to blame the assembly for a missing plugin wire-up).

`plugin/pumpkin_level.dart` holds the host seams: `PumpkinSableLevel`,
`MemoryPlotChunk` + `PumpkinPlotChunkHost` (world chunks through the plugin API,
plot chunks in memory) and `PumpkinFileStore`.

### Cross-plugin ownership: one plugin, one owner, one door

The container registry (`SubLevelContainer._containers`) is a **static map inside
one wasm component**. The host instantiates one `Store` per plugin
(`pumpkin-wasm-host-v0_2/src/lib.rs:548`), and each plugin component is compiled
from its own dependency graph, so `package:sable` is compiled *into* every plugin
that depends on it. Two consequences, both confirmed:

* the compiled simulated plugin contains sable's model: the cwasm blob whose
  strings include `Simulated loaded:` also contains the unique
  `has no sub-level container` message, and it does not contain `Sable declared`;
* `simulated`'s `simulated:assemble` handler, `aeronautics`' balloon hook and
  `sable`'s own `/sable` commands therefore each look at **their own** map.

`SablePlugin` fills the map in sable's component, so `/sable` and anything else
*inside sable's component* works. The physics assembler runs in simulated's
component, where the map is still empty: it needs a Sable server of its own.
Attaching physics in sable's component cannot reach it (a `PhysicsPipeline` is a
Dart object, and IPC between components carries JSON only). The two ways out:

1. **One owner, asked over IPC** (the architecturally right one): the Sable
   plugin owns containers/storage/physics/tracking and exposes an assemble/lookup
   API; simulated/create/aeronautics call it through `IpcChannel` instead of
   calling `SubLevelContainer.of` in their own address space. This is a
   cross-plugin refactor of the assembly entry points (the flood fill and the
   block movement would have to run in the owner's component).
2. **Per-component Sable servers**: each component that needs sub-levels runs the
   same wire-up with its own storage root. That duplicates every sub-level, and
   two components pointed at one region-file folder would corrupt it, so the
   roots must differ — the user then has as many un-synced sub-level universes as
   plugins.

**Chosen: one plugin, `sable`, owns the containers and the solver.** The Jolt
pipeline now lives in this package (`lib/src/physics/jolt/`), the core module is
linked into this package's component by `pumpkin_tools build` (the
`pumpkin.core_modules` block of `pubspec.yaml`), and `SablePlugin` registers
`JoltPhysicsPipelineProvider` and installs the section packer itself. The
containers and the pipeline that steps them are therefore the same wasm
component **by construction**, and the plugin declares the mod and runs the levels
in one `onLoad`.

This replaces a two-plugin arrangement (`sable` declared the mod, a `sable_jolt`
plugin owned the levels and answered an ownership probe on `sable.ownership`,
after which `sable` stood down). That split was a cycle workaround — `sable_jolt`
depended on `sable` for its `PhysicsPipeline` contract, so `sable` could not
depend on it — and it produced four live bugs, all of them consequences of two
components owning one world:

* two sub-level containers for one world, because the stand-down decided on the
  first tick and load order is not fixed: `/sable assemble` wrote into one while
  the tracker and the sender read the other, and the ship vanished;
* the `/sable` command tree registered under a permission that did not match the
  registering component's manifest name, so the host rejected it and `/sable` did
  not exist in game;
* version skew between the two wasms (rebuilding one against newer source broke
  assembly).

Folding the solver into `sable` removes the whole class: there is one artifact
(`sable.wasm`), one component, and no ownership question to ask. The probe, the
stand-down branch and the `ownershipProbeWindow` deadline are deleted. The model
stays VM-loadable: only `lib/sable_native.dart` (and the `src/physics/jolt/native.dart`
it re-exports) imports `dart:_wasm`; `lib/sable.dart` and
`lib/src/physics/jolt.dart` do not, which is what keeps `puro dart test` able to
run the pipeline against the module through a Node host.

**One door.** Callers in other components never touch a container directly; they
send operations on `sable.sublevels`, addressed to the constant plugin name
`sable` (`SableBridge.ownerPlugin`, `SablePhysicsPush.ownerPlugin`). There is no
discovery step left: one plugin, one channel, one set of containers.

Verified live with the merged plugin (one `sable.wasm`, no `sable_jolt.wasm` in
`plugins/`; `create` + `simulated` + `sable` only):
```
Jolt module: ABI 1, version id 329217.
Sable declared 17 payload channels.                     (exactly once)
Sable: sub-level container of minecraft:overworld ready (… pipeline JoltPhysicsPipeline).
Assembled 18 blocks.
/sablejolt → voxel colliders: 12                        (the bakery is live)
plugins/data/sable/sublevels/minecraft_overworld/r.-720037.-720037.0.slvls   (8192 bytes)
```
No ownership/stand-down line and no `must use the plugin's namespace` warning
appear in that log. A sub-level integrated by Jolt moves — which is what "the
physics assembler does nothing" was about.

Still not converted (each reads its own component's empty map, or needs the
mirror): `PumpkinSimulatedHost.containingSubLevel` / `subLevelById`.

### The other trap: a component that hosts Create's content must run its world tick

Found while wiring Create's kinetic network across components (see
`example/create/docs/kinetics-across-plugins.md`), and it is the same class of
mistake as the two above — a per-component piece of state that only one plugin
knows how to drive:

`CreatePlugin.onLoad` registers the **one** `worldTick` listener that runs
`BlockEntityStore.tickWorld` (the flush of `markChanged`/`sendData`), the kept
saved data, and every `CreateContext.onWorldTick` handler. The addon plugins
(`aeronautics`, `simulated`, `offroad`) install the store's *event* listeners —
which is why their block entities tick — but they did not install that listener,
so **every client-visible field of an addon block entity was frozen at its
creation values**: measured, `data get block` on `aeronautics:propeller_bearing`
answered `Speed: 0f, NeedsSpeedUpdate: 1b` while the same block entity was turning
at 16 RPM inside its own component. Fixed by `installHostedWorldTick`
(`example/create/lib/src/plugin/host_module_state.dart`), which the addons now
call from `onLoad`.

Two things to carry to the next hosted component: pass the plugin's **own**
`BlockEntityStore` — `CreateCore.blockEntities` is a second store that was never
installed, and its `tickWorld` flushes nothing, so passing the wrong one looks
like it works — and remember that `onWorldTick` handlers registered by a hosted
module never run until this is wired.

### Cross-plugin reach map (the refactor's work list)

Decision taken: **Sable stays the owner; other plugins reach it through
operations**, not through `SubLevelContainer.of` in their own address space. This
is every reach found, per plugin component, with the operation it needs. Nothing
here is converted yet.

| component | call site | reach | needs |
|---|---|---|---|
| simulated | `src/util/sim_assembly_helper.dart:138` | `SubLevelAssemblyHelper.assembleBlocks(level, anchor, blocks, bounds)` | `assemble` |
| simulated | `src/util/sim_assembly_helper.dart:150-200` | `SubLevelAssemblyHelper.moveBlocks` + `plot.getLoadedChunks()` | `disassemble` |
| simulated | `src/host/pumpkin_host.dart:298` | `SubLevelContainer.of(level)` → `getPlot(...)?.getSubLevel()` | `containing` |
| simulated | `src/host/pumpkin_host.dart:307` | `SubLevelContainer.of(level)?.getSubLevelById(id)` | `get` |
| simulated | `src/util/physics_constraints.dart:169` | `SubLevelContainer.of(level)` + `is! ServerSubLevelContainer` | `get` / `joints` |
| simulated | `src/util/sim_level_util.dart:19,25` | `SubLevelHelper.getContaining` + `...?.chunkHost` | `containing` + `areaLoaded` |
| simulated | `src/plugin/sim_payload_handlers.dart:173` | `SubLevelHelper.distanceSquaredWithSubLevels` | `distance` |
| simulated | `src/util/hold_interaction.dart:32` | `SubLevelHelper.projectOutOfSubLevel` | `projectOut` |
| simulated | `src/content/blocks/swivel_bearing/swivel_bearing_block_entity.dart:136` | `assembleFromSingleBlock` from a block-entity path | `assemble` (queued: see below) |
| aeronautics | `src/aeronautics_hooks.dart:80-95` | `SubLevelContainer.of(...)` → `physics.prePhysicsTickListeners.add(...)` — **silently inert today** | `physicsListener` |
| aeronautics | `src/aeronautics_hooks.dart:116`, `src/content/blocks/propeller/gyroscopic_propeller_bearing_block.dart:53`, `propeller_bearing_block.dart:114`, `propeller_block_entity_mixin.dart:19,30,33`, `small_propeller_blocks.dart:127,244`, `src/host/host_propeller_push_world.dart:43` | `SubLevelHelper.getContaining` / `getVelocityOfSubLevel` / `projectOutOfSubLevel` | `containing` / `velocity` / `projectOut` |
| offroad | `src/host/offroad_hooks.dart:240`, `src/content/blocks/wheel_mount/wheel_mount_block.dart:225`, `src/content/blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart:134` | `SubLevelHelper.getContaining` / `getVelocityOfSubLevel` / `projectOutOfSubLevel` | `containing` / `velocity` / `projectOut` |
| create | — | none: `create` never imports `package:sable`; the contraption compatibility layer is `example/sable/lib/src/compat/create/**`, compiled into sable's component | — |

Two shapes are needed, and the split is the important part:

* **operations that answer** (`assemble`, `disassemble`, `get`, `containing`,
  `areaLoaded`, `distance`, `velocity`, `projectOut`): an `IpcChannel` request to
  the `sable` plugin. The host routes it, so no plugin needs to know another's
  address beyond the agreed name; Sable does the work in its own component and
  answers with data (ids, poses), never with objects.
* **a push + mirror for the synchronous readers**: `containing`/`velocity` are
  called from block-entity ticks and block callbacks, which are synchronous, and
  an IPC round trip is a `Future`. So Sable pushes a small change feed
  (added/removed/moved ids with pose and bounds) and the other components answer
  sync queries from their mirror, explicitly one push behind. Only the
  interactive entry points (`simulated:assemble`, a block *use*) may await.

`simulated:assemble` is dispatched from `SimPayloadHandlers.dispatch`, which is
already `Future<void>` and called by Create's payload dispatch, so `_assemble`
can await the `assemble` operation. The block-entity-driven callers (swivel
bearing, physics staff) cannot, so they enqueue the request and apply the reply
when it lands.

### What is converted (and what is not)

Implemented:

* `example/sable/lib/src/plugin/sable_sub_level_api.dart`: the operation channel
  (`IpcChannel` named `sable.sublevels`, addressed to the plugin `sable`), the
  ops `list`, `get`, `containing`, `areaLoaded`, `assemble`, and a
  `subscribe`/`changed` push. The handler is synchronous by construction, so an
  operation runs to completion inside Sable's component; replies carry ids,
  poses, bounds, mass and the plot's centre block, never objects. A temp command
  in the Aeronautics plugin proved the round trip live (`list` answered `ok=true`
  from the sable component).
* `example/simulated/lib/src/host/sable_bridge.dart`: the caller half — the
  operations above, plus a **mirror** (`subLevelAt`, `subLevelById`,
  `subLevelsOf`) refreshed by the `changed` pushes, one push behind, for callers
  that cannot await.
* `SimAssemblyHelper.assembleFromSingleBlock` now searches the structure locally
  and calls the installed `SimAssemblyHelper.assembleBlocks` hook for the block
  move; the plugin installs it over the bridge. `SimAssemblyResult.subLevel` is a
  `SimAssembledSubLevel` snapshot (id + plot centre block) instead of a `SubLevel`.
* Callers converted: `PhysicsAssembler.assembleOrDisassemble` is `async`
  (`simulated:assemble` awaits it; the synchronous `onUseWithoutItem` starts it);
  `SwivelBearingBlockEntity.assemble` is queued from its tick with an
  `_assembling` guard; `Aeronautics`' `SimulatedBridge.balloonsAssembled` uses the
  snapshot's `centerBlock`.

Not converted yet (each still reads this component's empty map, or needs the
mirror): `PumpkinSimulatedHost.containingSubLevel` / `subLevelById`,
`SimLevelUtil.isAreaActuallyLoaded`, `physics_constraints.dart`,
`SubLevelHelper.distanceSquaredWithSubLevels` / `projectOutOfSubLevel` /
`getVelocityOfSubLevel`, `SimAssemblyHelper.disassembleSubLevel` + `moveBlocks`
(the disassembly path), Aeronautics' `physics.prePhysicsTickListeners` hook, and
Offroad's three `SubLevelHelper` calls.

Still missing on the plugin side (each a `HOST GAP`): the payload sink, the chunk
view and the UDP sender are uninstalled, so even a tracked sub-level is not sent
to a client; `AssemblyEntityHost` is not implemented, so entities on the assembled
blocks stay where they are; world-chunk block entities are not moved (the host
exposes only raw NBT bytes).

`SubLevelHost` **is** implemented now (`plugin/pumpkin_sub_level_host.dart`,
installed as `container.hostOrNull`): it answers the saved data through
`SavedDataFiles`, the players through `Server.getAllPlayers` filtered by
dimension, the sub-level lookup through the container, and the pose/mass/velocity
from the loaded `ServerSubLevel` (Java reads them from the physics pipeline). The
chunk-unload half of `updateChunkStatus` stays unwired: the host's
`ChunkUnloadEvent` carries no world, and `World::unload_chunk` never fires it, so
only `Events.chunkLoad` is subscribed; the unload half is driven by
`PhysicsChunkTicketManager`.

## Deliberately left

* **Client half** — `ClientSubLevel`, `ClientLevelPlot`, `render/**`,
  `debug/Gizmo*`, `config/SubLevelSettingsScreen`. The plugin is server-only.
* **`sable/neoforge`** — mixins, loader entry points, the rapier native
  packaging. Its Create compatibility half is the Create plugin's business.
* **The physics solver** — `physics/impl/rapier/**` and `sable_rapier`. The
  Dart port defines the pipeline contract (`api/physics_pipeline.dart`), the
  provider registry and the `impl/none` fallback; the solver itself is
  `lib/src/physics/jolt/` in this package, with the core module linked by
  `pumpkin_tools build` (the `pumpkin.core_modules` block of `pubspec.yaml`).
  A feature an engine cannot implement is declared
  through `api/physics_capabilities.dart` (`FeatureAwarePhysicsPipeline`) so
  Sable never calls it — `JoltPhysicsPipeline` declares contraptions and ropes
  unsupported, because the checked-in native module has no kinematic body
  factory and no rope chain.
* **The UDP server** — `SableUDPServer`, `SableUDPAuthenticationState`,
  `SableUDPChannelHandlerServer`, `SableUDPEchoPacket`, the encoder/decoder and
  `AddressedSableUDPPacket`. The six datagram kinds and their codecs are ported
  (`network/udp/**`), but the socket/auth/keep-alive state machine needs a host
  UDP surface that does not exist (`host_gap.dart`'s `udp-channel`: `bind-udp`,
  `send-datagram`, `on-datagram`). **TCP is therefore the supported transport,
  not a fallback of last resort**: `PumpkinTrackingSender`
  (`plugin/pumpkin_tracking_sender.dart`) sends the whole sync — 
  `start_tracking_sub_level`, the plot's chunks, `finalize_sub_level`,
  `change_bounds_sublevel`, the snapshots, `stop_moving_sublevel`,
  `stop_tracking_sublevel` — over the payload channel, which is the identical
  payload set Java sends when UDP is not up (`SubLevelTrackingSystem.java:383-404`).
  `sable:udp_activation` is deliberately never sent: activating a channel whose
  server socket does not exist would make the client `AUTH` into the void.
* **`SubLevelPlayerChunkSender`** — chunk packets and POI data are host sends
  (`chunk-streaming.send-chunk-at`). Java's per-chunk POI send has no host
  equivalent; see the `HOST GAP` note in `system/tracking_system.dart`.
  `send-chunk-at` serialises the chunk **loaded in the world**, and a plot chunk
  is plugin-side memory, so the port asks the **server** to keep the yard chunk
  loaded (`forceload`, which marks it and returns at once) and the sender queues
  that chunk's send until the world has it, then writes the plot's blocks
  (0 ms) and sends the chunk packet. The plugin's own `force-load-chunk` is
  unusable here: it waits for generation and answers at its 60 s timeout, and
  that wait blocks the tick loop *even when the call is not awaited* — measured
  as a 60 s server freeze that killed a watching client's keep-alive. With the
  forceload path the whole sequence (ask → loaded → sent) took **3 s** live. A
  host `create-empty-chunk` (`host_gap.dart`'s `chunk-source`) would remove the
  wait and the worldgen chunk altogether.
* **`LevelAccelerator`, `SchematicLoader`, `SableDistUtil*`** — host-side
  accelerators and client helpers; the Dart model has no chunk cache to
  accelerate.
* **`water_occlusion/**` beyond the container type** — the container, regions
  and their pose transform are ported and tested; `WaterOcclusionRenderer` and
  `WaterOcclusionRenderRegion` are client rendering, and the server-side
  `ServerWaterOcclusionContainer` still needs a per-plot block query the host
  does not expose yet.
* **`SubLevelCollisionConstants` and the Java collision sweep helpers**
  (`SubLevelEntityCollisionContext`, `SubLevelInclusiveLevelEntityGetter`,
  `VoxelNeighborhoodState`). The port flips entity collision around: it hands
  the host world-space boxes (`SubLevelEntityCollision.boxesOf`) and the host
  clips its own entities, so the 40° vertical/walkable-slope thresholds and the
  context objects the sweep used are not needed. `getHitBoxYaw`,
  `transformEntityBoundsCenter` and `transformEntityBoundingBox` are ported.
* **`SableCodecUtil`** — the Mojang `Codec` helpers for datapack JSON. The port
  reads datapack values through `PhysicsBlockPropertiesTable` and NBT; there is
  no `Codec` layer to validate.
* **`PacketReceiveMode`** — the Java enum records whether a payload arrived over
  TCP or UDP. The Dart packet model has no per-packet receive mode; the UDP
  codecs are separate types, which is stronger.

## Not testable headlessly

* Anything that needs a live connection: the packet sink
  (`ServerSubLevel.packetSink`), UDP activation, chunk sends. The tests install
  recording sinks and assert the payload sequence and bytes instead.
* The light engine (`ServerLevelPlot.initializeLight` / `correctLight` /
  `lightChunk`): Pumpkin exposes no per-plot light engine, so these throw a
  named `HOST GAP` rather than silently no-op.
* Real chunk storage: `PlotChunkHost` is faked in the unit tests; the
  region-file round trip is tested against an in-memory image. The production
  implementation is `plugin/pumpkin_level.dart`: world chunks go through the
  plugin API, plot chunks are `MemoryPlotChunk`s in the plugin's map (Pumpkin
  cannot create a `LevelChunk` at the plot yard, see the `chunk-source` gap).
* The physics solver itself: `PhysicsPipeline` is a recording fake, so the
  tests assert call order and impulses, not simulation results.
* Tick timing (`msSinceLastSend` from the wall clock) is injected.
* The static pipeline is testable and tested; the Jolt pipeline is testable
  against the *real* module, which `test/jolt/` drives through a Node host
  (`test/jolt/support/node_jolt.dart`) — the module is the checked-in
  `native/jolt/jolt.wasm`.

## Known deviations, each marked `TODO(parity)` in the source

| Site | Java | Why |
|---|---|---|
| `model/sub_level.dart` | `SubLevel.java:123-131` | an empty plot's inverted box is collapsed onto the pose instead of being swapped into a full-range box |
| `model/sub_level_container.dart` | `SubLevelContainer.java:139-160` | the removal loop iterates a copy; Java would throw `ConcurrentModificationException` |
| `model/server_sub_level.dart` | `ServerSubLevel.java:339` | `prePhysicsTick` takes a `PartialPhysicsTickSource`, not the system; a non-source gets `1.0` |
| `model/server_sub_level.dart` | `ServerSubLevel.java:92` | the floating-block controller is created lazily, and is absent without a block-property table |
| `model/server_sub_level.dart` | `ServerSubLevel.java:93` | the reaction-wheel manager falls back to the all-defaults property table |
| `index/sable_index.dart` | `SableAttributes.java:21-25` | the attribute registry ids are assigned by loader code and are not in the common tree |
| `model/server_sub_level.dart` | `ServerSubLevel.java:392` | `KinematicContraption` has no `sable$getFloatingClusterContainer()`, so a contraption's floating blocks are not merged into the sub-level's clusters |
| `physics/impl/none/static_physics_pipeline.dart` | `StaticPhysicsPipeline.java:92-103` | Java returns `null` from `addBox`/`addRope`; this returns a handle that remembers the object, because the Dart contract's handles are non-nullable |
| `physics/impl/none/static_physics_pipeline.dart` | `StaticPhysicsPipeline.java:163-165` | `getNextRuntimeId()` returns the constant `0`, so two bodies share an id — harmless without simulation, kept for parity |
| `system/tickets.dart` | `PhysicsChunkTicket.java:57-63` | `hashCode` includes `lastInhabitedTick` while `equals` compares only `pos`; the Java inconsistency is kept |
| `api/sub_level_ticket_loading_system.dart` | `SubLevelTicketLoadingSystem.java` | a `REMOVED` sub-level keeps its force-load ticket (and pointer) unless `/sable remove` cleared it, so a transient restore failure cannot delete the only pointer to the sub-level |
| `storage/holding/sub_level_holding_chunk_map.dart` | `SubLevelHoldingChunkMap.java` | `pack` is an in-process key with the halves swapped relative to `ChunkPos.pack`; `unpack` matches, and nothing crosses a boundary with it |

## Fixes landed after the first live validation

Each of these came from a live run or a static audit; the Java site is named in
the code at every one.

* **The mass delta validated the wrong tracker** (`system/physics_system.dart`):
  `_updateMassDataFromBlockChange` checked the **merged** tracker where Java
  checks the **self** tracker (`SubLevelPhysicsSystem.java:524-535`). The merged
  properties are recomputed only at the *end* of that method, so on the first
  block of an assembly the merged tracker was still the empty one (`mass == 0`) →
  "invalid" → the port destroyed the plot it had just written to and removed the
  sub-level. That one ordering bug produced both the disappearing sub-level and
  the `mass=12, pose=(NaN,NaN,NaN)` state. Regression tests in
  `test/physics_boundary_test.dart` ("the first block of an assembly is kept and
  counted" — verified to fail against the old check — and "removing the last
  block still removes the sub-level").
* **The same merged/self confusion in two more places**, fixed as a class: the
  saved pose recentres on the **self** tracker
  (`SubLevelSerializer.java:50-53`) and the heat map's zero-mass guard reads the
  self tracker through `isInvalid()` instead of a getter that *throws*
  (`SubLevelHeatMapManager.java:243-247`).
* **NaN recovery threw instead of removing** (`SubLevelPhysicsSystem.java:376-381`):
  it read `getCenterOfMass().x.isNaN`, which throws for an empty tracker where
  Java's `getCenterOfMass() == null` decides. `isInvalid()` now decides.
* **The block-change hook** is wired (`SableCommonEvents.handleBlockChange`): plot
  writes run holder bounds, plot bounds/expand, actors, the heat/floating queues
  and the mass delta; world writes run the pipeline notify + wake half.
* **Assembly commands report the truth** (`command/sable_assemble_commands.dart`):
  `_hasAssembledMass` runs **before** the assembly
  (`SableAssembleCommands.java:302-310`) so an empty selection moves nothing and
  leaves no mass-less sub-level; the success count is `_countAssembledBlocks`
  (solid blocks, not the selection volume) **taken before the move** — Java
  evaluates it inside a `sendSuccess` supplier, i.e. after `assembleBlocks` has
  destroyed the originals, which prints `Assembled 0 blocks.` for a real
  assembly; and `assembleBlocks` no longer throws when the tracker has no mass —
  Java's getter returns `null` there and takes the fallback branch.
* **`shatter` destroyed builds**: `shatterBlocks` had Java's condition inverted —
  it deleted every non-air block *before* assembling, so
  `shatter cube|sphere|area` removed the structure and created no sub-levels.
  Java destroys only the **non-solid** blocks and then assembles each remaining
  block on its own.
* **Selector arguments**: Brigadier's `word()` stops at `@`, so every
  `sub_level`/`target` argument now uses the host's `token` type (one
  whitespace-delimited token, unchanged) — `@e[limit=1]` now works in front of
  further arguments, which is what `/sable physics …` and `/sable teleport …`
  needed.
* **Dimension drag** comes from `dimensionDrag(level)` instead of a 0.09
  constant (`SubLevelPhysicsSystem.java:168-170`), and the solver settings reach
  the pipeline through the opt-in `ConfigurablePhysicsPipeline`
  (`SubLevelPhysicsSystem.java:171-172`).
* **Chunk tickets are real**: `addChunkTicket`/`removeChunkTicket` use the host's
  `ChunkTickets.forceLoadChunk`/`releaseChunkTicket` for **world** chunks. Yard
  positions deliberately take no ticket: the plot blocks live in
  `MemoryPlotChunk`, and a host ticket there would make worldgen write terrain
  into the yard (the `chunk-source` gap).
* **The structure search batches its reads** (`BulkBlockHost` + the `BatchingBlockHost`
  read cache; both implemented by the chunk host). Every visited block reads its ~18
  neighbours, and the read cache already served all but ~1.4 of them, but each of those
  was a host call at ~4 µs: `/sable assemble connected` over solid terrain refused at
  **65 536 examined positions** (3.90 s, 78 ticks behind on the tick loop) where Java
  assembles 256 000, because the walk cost ~60 µs per position. `World.get-block-states`
  (host WIT `world.wit`, one call for a list of positions) is what the walk uses now: the
  frontier is read in waves of 128 positions in one call, so the cap is Java's 256 000.
  Measured on the same host binary and scenario:
  - 256 001 examined positions, refused at the cap: **17.90 s / 357 ticks behind** for the
    clean build, **13.96 s / 277 ticks behind** for the instrumented one;
  - the host reads of that walk are **0.3 s** — 2003 `get-block-states` calls for 361 367
    positions (~1.4 reads per position, 3 µs each), against one call per read before;
  - what remains is guest bookkeeping, not the host: ~5.8 s in the wave scan, ~6.6 s in
    the walk's own neighbour loop and ~1.3 s decoding state ids. Those numbers come from
    the walk on record-keyed sets; packing a position into one int (`_pack`, relative to
    the gather origin, 21 bits per axis) cut the walk from 90.4 s to 14.0 s by itself.
  `BulkBlockHost` is the plug-in-side seam (a host that cannot batch keeps the per-query
  reads, exactly as before); `BatchingBlockHost` still serves a host whose reads cross a
  boundary but which has no bulk read.

### Force-load across a restart

**One deliberate divergence:** Java drops a sub-level's force-load ticket when the
sub-level is removed (`SubLevelTicketLoadingSystem.onSubLevelRemoved`). The port
keeps it, unless the removal came from an explicit delete (`/sable remove`, which
calls `ServerSubLevelContainer.forgetTickets`). A ticket is the only pointer that
can load the sub-level back, so Java's rule turns a transient failure — a tracker
that reads empty for one tick, a plot whose chunks have not been restored yet —
into permanent loss of the ship and of the file entry that named it, with nothing
in the log. A kept ticket re-arms the force-load on the next start. See
`docs/sable-core-port.md`'s deviations table for the same note in one line.



`/sable forceload add` → save → restart was reproduced end to end, and the ticket
half is now proven working:

```
session 1: Force-loaded 1 sub-level.
           saving 1 force-load ticket(s) in minecraft:overworld, 1 with a save pointer.
session 2: loaded 1 force-load ticket(s) for minecraft:overworld, 1 with a save pointer.
           DEBUG snatch <uuid> at [chunkPos=(0,0), storageIndex=0, subLevelIndex=0]
           DEBUG holding chunk (0,0) pointers=[...] loaded=[<uuid>]
           DEBUG observer: removed <uuid> reason=SubLevelRemovalReason.removed
```

So the ticket persists, the pointer resolves, the holding chunk holds the
sub-level — and the sub-level is then **removed during the load with no failure
message**. Two causes are ruled in, and both are in the load path rather than the
ticket path:

* `fullyLoad` removes the sub-level (`SubLevelRemovalReason.removed`) when
  `plot.getBoundingBox()` is empty, which is what happens if `plot.load` restored
  a chunk that decodes to no blocks; the matching `onFailure` message is not
  printed, so the failure sink is not reaching the caller on that path.
* independent of that, the mass tracker is built by `onSubLevelAdded` while the
  plot is still **empty**, so a restored sub-level starts invalid and the next
  tick's removal pass destroys it. `SubLevelSerializer.fullyLoad` now rebuilds the
  tracker once the plot is loaded (`subLevel.buildMassTracker()`), which is the
  same thing `SubLevelPhysicsSystem.recoverSubLevel` does on the paths that
  matter.

Fixed, and verified across a real restart:

* `SubLevelSerializer.fullyLoad` rebuilds the tracker after the plot is loaded
  **and primes the merged one** (`updateMergedMassData(0.0)`). Both halves are
  needed: `allocateSubLevel` builds the tracker while the plot is still empty, and
  a freshly wrapped `MergedMassTracker` keeps its own empty `mass`/`centerOfMass`
  until `update` runs — and `SubLevelContainer.tick` runs
  `processSubLevelRemovals()` **before** the observers (the physics system), so an
  un-primed tracker reads as invalid and the restore is removed on its first tick.
* Live, two sessions, same world:
  ```
  session 1: Assembled 18 blocks. … mass 36.00
             Force-loaded 1 sub-level.
             saving 1 force-load ticket(s) in minecraft:overworld, 1 with a save pointer.
  session 2: loaded 1 force-load ticket(s) for minecraft:overworld, 1 with a save pointer.
             1 loaded sub-level(s) of minecraft:overworld are force-loading back …
             1 ticket on 1 sub-level in minecraft:overworld.
             1 sub-level: <uuid> position 20481034.00, 67.00, 20481034.00
               [global->[chunkPos=(0, 0), storageIndex=0, subLevelIndex=0]] … mass 36.00
  ```
  and the tickets file is still 173 bytes with its entry after the second session
  (previously it was rewritten empty, which also destroyed the only pointer that
  could load the ship next time).

`SablePlugin` also logs the ticket count and how many carry a pointer on both
save and load: losing a force-loaded sub-level across a restart used to be
completely silent, and this is the line that showed the ticket itself was fine.

Open, each needs a decision rather than another edit:

* **The solver used to be unattachable to a container, and is not any more.**
  `PhysicsPipelineProviders` resolves inside one wasm component, and the Jolt
  pipeline once existed only in another plugin's component, so the container
  owner got the static fallback (`pipeline StaticPhysicsPipeline` in every run)
  and nothing could move. Moving `JoltPhysicsPipeline` into this package looked
  impossible for two reasons: the package cycle (`sable_jolt` depended on `sable`
  for the `PhysicsPipeline` contract) and the drag of `dart:_wasm` into a package
  whose model half must load on the plain Dart VM in tests. Both are resolved by
  the fold: the contract belongs to this package, so there is nothing to import
  back, and the `dart:_wasm` half is confined to `lib/sable_native.dart` and
  `lib/src/physics/jolt/native.dart` (not exported by `lib/sable.dart`), so
  `sable.dart` and `src/physics/jolt.dart` stay VM-loadable. A level's pipeline
  now comes from `PhysicsPipelineProviders.createPipeline(level)`, which resolves
  to `JoltPhysicsPipelineProvider` (priority 1000) registered by `SablePlugin
  .startServer`.
* **Per-block mass now comes from Sable's datapack**, loaded by `SablePlugin`
  (`_installBlockProperties`) from the embedded copy of the pack
  (`sableDatapackBlobs`): 19 `physics_block_properties` entries, applied in
  priority order, with the table's block hooks (`MassTracker.blockMass`,
  `blockInertia`, `isSolid`) pointed at it. **Verified live**: 19 stone blocks
  now weigh `38.00` (2.0 each, matching Java) instead of `19.00`, and each
  shattered block is `2.00` instead of `1.00`.
  Tag membership is resolved from the pack's own `tags/block/**` (nested `#tag`
  entries followed), because the host only sees a pack under
  `<world>/datapacks/<name>` and that link is a manual operator step — the host
  is consulted only for a tag the pack does not define (`#c:stones` and other
  conventional tags).

## Collision data: why a sub-level clipped through the world

**Root cause (two independent gaps, both in the live path only).** The Jolt
pipeline's own collision contract was always sound — `pipeline_test.dart` drives
the real module with packed sections and a body comes to rest on a voxel floor,
and a live run already measured the assembled structure falling (`-44.23 →
-93.23 m/s`) under gravity. What the plugin component never did was *feed* it:

* **No `PlotSectionPacker` was ever installed.** `PhysicsChunkTicketManager
  .packer` stayed `null`, and `_uploadSection` returns before calling the
  pipeline, so `handleChunkSectionAddition` was never reached in a live server:
  neither the sub-level's own plot sections (its collision shape) nor the static
  level's terrain (the ground) existed in the Jolt world. The body fell with
  Jolt's `EmptyShape` through empty space. `git log -S"implements
  PlotSectionPacker"` finds only a test double; the interface was introduced
  with the seam and never implemented.
* **No block colliders were ever registered.** `registerVoxelCollider` used to be
  called from the `/sablejolt drop` diagnostic and from tests only —
  `voxel colliders: 0` in every live run — so even a packed section would have
  carried collider index 0 ("no collider") and every block would have been
  `isSolid == false` in the module. The bakery now registers one collider per
  block state as the packer walks the sections, so a live run reports
  `voxel colliders: 12` after the world around the plot has been packed.

**Fix** (in `sable` itself: the solver is folded into this package, and the
packer is installed by `SablePlugin._openLevel` through
`lib/src/plugin/jolt_collision.dart`, matching Java, where the bakery lives in
`sable_rapier`):

* `lib/src/physics/section_packer.dart` (pure): `BlockColliderBakery`
  (`RapierVoxelColliderBakery` — one collider per block state, datapack
  friction/volume/restitution, liquid → unit box + fluid flag, boxes clamped to
  the unit cube) and `JoltCollisionPacker` (the packing loop of
  `RapierPhysicsPipeline.handleChunkSectionAddition`, including
  `VoxelNeighborhoodState`, the air-only short circuit and the 18³ neighbourhood
  read through sable's `BulkBlockHost`, so a world section costs one host call).
  The state-of-a-block-state inputs (`getCollisionShape`, `liquid()`) are the
  `BlockShapeSource` seam.
* `lib/src/plugin/host_block_shapes.dart`: that seam over the host registry
  (`BlockStates.stateOfId` + the state's collision boxes; `is_liquid` plus the
  `waterlogged` property, which is what Java's `state.liquid()` covers).
* `SablePlugin.installCollision`: the hook the solver component installs the
  packer through (`PhysicsChunkTicketManager.packer` is per level, the pipeline
  per level, so the packer is too). `bin/main.dart` wires it; a component with no
  solver passes nothing and the static fallback is unchanged.

The sub-level's own sections reach its body through the path that already
existed: a plot block change calls `ticketManager.addSectionIfNotTracked`, whose
upload resolves the yard position through `getPlot` to that sub-level's body.
The static terrain under the ship reaches the static world through the ticket
manager's normal pass over the sub-level's *global* bounds (world coordinates,
`globalBounds` is the plot box transformed by the pose).
