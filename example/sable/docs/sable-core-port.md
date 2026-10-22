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
| `api/physics/**` | `api/physics.dart`, `api/physics_pipeline.dart`, `api/physics_pipeline_provider.dart`, `api/physics_constraint.dart`, `api/physics_rope.dart` | force groups, handles, mass, constraints, the provider registry |
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
* **Storage.** `SubLevelStorage` is rooted at `<plugin data>/<world id>/sublevels`
  (`PumpkinFileStore` over `DataFolder`, hence `fs.write.data`), and the
  container is initialized with it (`initializeWithStorage`), which installs the
  ticket loading system and the holding chunk map.
* **Registration and announcement**: `SubLevelContainer.register(container)`,
  then `fireSubLevelContainerReady(level, container)`
  (`api/event/sable_sub_level_container_ready_event.dart`, which also calls
  `SablePlatform.onSubLevelContainerReady`).
* **Ticking**: one `worldTick` handler ticks the container of the world that
  ticked; a container whose tick throws is left un-ticked with one error log
  instead of failing on every tick.
* **Unload**: `worldUnload` (and plugin unload) closes the container, unregisters
  it, closes the storage and releases the kept world handle.
* `/sable` is registered over a `SableCommandState` whose `levelOf` resolves a
  command's `World` to the container's level view.

`plugin/pumpkin_level.dart` holds the host seams: `PumpkinSableLevel`,
`MemoryPlotChunk` + `PumpkinPlotChunkHost` (world chunks through the plugin API,
plot chunks in memory) and `PumpkinFileStore`.

Still missing on the plugin side (each a `HOST GAP`, not a container bug): the
physics system and tracking system are never attached to the container, so a
sub-level has no mass tracker and `/sable assemble` reports "No blocks to
assemble." after a successful assembly; `AssemblyEntityHost` is not implemented,
so entities on the assembled blocks stay where they are; world-chunk block
entities are not moved (the host exposes only raw NBT bytes).

## Deliberately left

* **Client half** — `ClientSubLevel`, `ClientLevelPlot`, `render/**`,
  `debug/Gizmo*`, `config/SubLevelSettingsScreen`. The plugin is server-only.
* **`sable/neoforge`** — mixins, loader entry points, the rapier native
  packaging. Its Create compatibility half is the Create plugin's business.
* **The physics solver** — `physics/impl/rapier/**` and `sable_rapier`. The
  Dart port defines the pipeline contract (`api/physics_pipeline.dart`), the
  provider registry and the `impl/none` fallback; the solver itself is another
  slice (`example/sable_jolt`).
* **The UDP server** — `SableUDPServer`, `SableUDPAuthenticationState`,
  `SableUDPChannelHandlerServer`, `SableUDPEchoPacket`, the encoder/decoder and
  `AddressedSableUDPPacket`. The six datagram kinds and their codecs are ported
  (`network/udp/**`), and the tracking system sends through a `sendDatagram`
  sink, but the socket/auth/keep-alive state machine is S4's. Until it exists a
  client keeps working over TCP, which is the Java fallback
  (`SableConfig.ATTEMPT_UDP_NETWORKING`).
* **`SubLevelPlayerChunkSender`** — chunk packets and POI data are host sends
  (`chunk-streaming.send-chunk-at`). Java's per-chunk POI send has no host
  equivalent; see the `HOST GAP` note in `system/tracking_system.dart`.
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
* The static pipeline is testable and tested; what is *not* testable headlessly
  is a real solver's simulation result (`example/sable_jolt` needs the native
  library).

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
| `storage/holding/sub_level_holding_chunk_map.dart` | `SubLevelHoldingChunkMap.java` | `pack` is an in-process key with the halves swapped relative to `ChunkPos.pack`; `unpack` matches, and nothing crosses a boundary with it |
