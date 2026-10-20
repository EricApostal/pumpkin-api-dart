# W5 — vanilla-integration parity

Sable's vanilla integration is 227 common mixin files (145 server-side, 82
client-only), 33 mix-interfaces, 15 mixin helpers, and 207 NeoForge files — of
which 156 are the Create compatibility layer (W6) and 19 are Flywheel rendering.
The plugin is server-only, so the client half is not ported.

This document is the classification of the server-side half. The same table is
data in `lib/src/sublevel/vanilla/mixin_inventory.dart` (checked against the Java
tree by `test/w5_vanilla_parity_test.dart`), and the host gaps are data in
`lib/src/sublevel/vanilla/host_gap.dart`.

## Counts

| Source | Files | (a) plugin hook | (b) host gap | (c) not applicable |
|---|---:|---:|---:|---:|
| `common/.../mixin/**` server-side | 145 | 30 | 81 | 34 |
| `common/.../mixinterface/**` | 33 | 3 | 12 | 18 |
| `common/.../mixinhelpers/**` | 15 | 0 | 3 | 12 |
| `neoforge/.../mixin/**` non-Create | 23 | 0 | 2 | 21 |
| `neoforge` support (platform, events, physics, gametest, entry) | 19 | 5 | 1 | 13 |
| **Total classified** | **235** | **38** | **99** | **98** |

Not classified here, because they belong to other workstreams:

| Source | Files | Owner |
|---|---:|---|
| `neoforge/.../mixin/compatibility/create/**` + helpers + interfaces | 156 | W6 (Create compatibility) |
| `neoforge/.../mixin/compatibility/flywheel/**` | 19 | client rendering |
| `common/.../mixin/**` client-side | 82 | client mod, not the plugin |

The ticket's "183 server-side common mixins" is the mixin + mix-interface +
mixin-helper total; on the current `port/26.3` tree that total is 193
(145 + 33 + 15), because the tree has grown since the survey. The client/server
split of `common/.../mixin/**` is 82 / 145 by the classes each file patches (one
file, `plot/container/ServerLevelMixin`, imports client types for its
client-level branch but patches `ServerLevel`, so it is counted server-side).

Bucket meanings:

* **(a) plugin hook** — an existing host event or capability plus plugin-side
  logic reproduces the patch. The code is in `lib/src/sublevel/vanilla/`.
* **(b) host gap** — the host has no hook. `host_gap.dart` says what it would
  have to expose; nothing is invented as available.
* **(c) not applicable** — client-only, an accessor/debug/perf helper, a
  third-party mod, a loader abstraction, or a Java-only mechanism (Dart has the
  source, so it does not patch bytecode).

## (a) Expresssible with an existing hook — 38 patches

| Hook | Patches | Files |
|---|---:|---|
| `server-tick-start-event` | 7 | `mixin/death_message/EntityMixin`, `mixin/entity/entity_sublevel_collision/AbstractMinecartMixin`, `mixin/player_freezing/PlayerMixin`, `mixin/player_freezing/ServerPlayerMixin`, `mixinterface/player_freezing/PlayerFreezeExtension`, `neoforge/event/ForgeSablePrePhysicsTickEvent`, `neoforge/event/ForgeSablePostPhysicsTickEvent` |
| `entity-spawn-event` | 3 | `mixin/entity/entity_kicking/BlockMixin`, `mixin/entity/entity_kicking/ServerLevelMixin`, `mixin/entity/tnt_jumps/PrimedTntMixin` |
| `block-collision-callback` (W3 block API) | 5 | `mixin/impact/BeehiveBlockMixin`, `mixin/impact/BellBlockMixin`, `mixin/impact/TntBlockMixin`, `neoforge/physics/callback/AbstractBellBlockCallback`, `neoforge/physics/callback/BeltBlockCallback` |
| `world-load-event` | 3 | `mixin/plot/container/ServerLevelMixin`, `mixinterface/plot/SubLevelContainerHolder`, `neoforge/event/ForgeSableSubLevelContainerReadyEvent` |
| `entity-mount-event` | 2 | `mixin/entity/entity_rotations_and_riding/EntityTypeMixin`, `mixin/entity/entity_rotations_and_riding/ServerPlayerMixin` |
| `spawn-change-event` | 2 | `mixin/respawn_point/ServerPlayerMixin`, `mixinterface/respawn_point/ServerPlayerRespawnExtension` |
| `player-teleport-event` | 1 | `mixin/entity/teleport_players/ServerPlayerMixin` |
| `player-respawn-event` | 1 | `mixin/respawn_point/sleeping/ServerPlayerMixin` |
| `player-death-event` | 1 | `mixin/death_message/CombatTrackerMixin` |
| `player-join-event` | 1 | `mixin/player_freezing/PlayerListMixin` |
| `projectile-launch-event` | 1 | `mixin/entity/projectile/ProjectileMixin` |
| `projectile-hit-event` | 1 | `mixin/entity/arrows_hit_blocks/AbstractArrowMixin` |
| `entity-damage-event` | 1 | `mixin/entity/entity_sublevel_collision/LivingEntityMixin` (bounce/damage half) |
| `entity-explode-event` | 1 | `mixin/explosion/ServerLevelMixin` |
| `fluid-level-change-event` | 1 | `mixin/fluids_on_sub_levels/FlowingFluidMixin` |
| `block-spread-event` | 1 | `mixin/prevent_overgrowth/VineBlockMixin` |
| `block-place-event` | 1 | `mixin/plot/LevelChunkMixin` (plot block-change notification) |
| `block-dispense-event` | 1 | `mixin/recoil/ProjectileDispenseBehaviorMixin` |
| `lightning-strike-event` | 1 | `mixin/stop_lightning/ServerLevelMixin` |
| `command-argument` (command API) | 1 | `mixin/command/ArgumentTypeInfosMixin` |
| `persistent-data` (player data) | 1 | `mixin/tracking_points/ServerPlayerMixin` |
| `world-save-event` | 1 | `mixin/plot/ServerLevelMixin` |

## (b) Host gaps — 99 patches over 34 gaps

| Gap | Priority | Patches | Files |
|---|---|---:|---|
| `entity-movement-sweep` | critical | 7 | `mixin/entity/entity_sublevel_collision/EntityMixin`, `mixin/entity/entity_sublevel_collision/PlayerMixin`, `mixin/entity/entity_rotations_and_riding/BlockMixin`, `mixin/player_standup/PlayerMixin`, `mixinterface/entity/entity_sublevel_collision/EntityMovementExtension`, `mixinterface/entity/entity_sublevel_collision/LivingEntityMovementExtension`, `mixinhelpers/CanFallAtleastHelper` |
| `entity-wire-position` | critical | 6 | `mixin/entity/entities_stick_sublevels/EntityMixin`, `mixin/entity/entities_stick_sublevels/ServerEntityMixin`, `mixin/entity/entity_rotations_and_riding/ServerEntityMixin`, `mixin/entity/entity_tracking/TrackedEntityMixin`, `mixinterface/entity/entities_stick_sublevels/EntityStickExtension`, `mixinterface/entity/entities_stick_sublevels/LivingEntityStickExtension` |
| `player-move-packet` | critical | 4 | `mixin/entity/entities_stick_sublevels/player/ServerboundMovePlayerPacketMixin`, `mixin/entity/entities_stick_sublevels/player/ServerGamePacketListenerImplMixin`, `mixin/entity/entity_sublevel_collision/ServerGamePacketListenerImplMixin`, `mixinterface/entity/entities_stick_sublevels/player/ServerboundMovePlayerPacketExtension` |
| `entity-tracking-follow` | critical | 1 | `mixin/entity/entities_stick_sublevels/player/ServerPlayerMixin` |
| `clip-raycast` | critical | 4 | `mixin/clip_overwrite/BlockGetterMixin`, `mixin/clip_overwrite/EntityMixin`, `mixin/clip_overwrite/HitResultMixin`, `mixin/entity/entity_interaction/ProjectileUtilMixin` |
| `chunk-source` | critical | 2 | `mixin/plot/ChunkMapMixin`, `mixin/plot/ServerChunkCacheMixin` |
| `chunk-serialization` | critical | 4 | `mixin/plot/serialization/ChunkMapMixin`, `mixin/plot/serialization/LevelChunkTicksMixin`, `mixinterface/plot/serialization/ChunkAccessExtension`, `mixinterface/plot/serialization/LevelChunkTicksExtension` |
| `entity-block-pos` | major | 7 | `mixin/climbing_sub_levels/LivingEntityMixin`, `mixin/entity/entities_stick_sublevels/effects/EntityMixin`, `mixin/entity/entities_stick_sublevels/effects/LivingEntityMixin`, `mixin/entity/entity_ai/EatBlockGoalMixin`, `mixin/entity/falling_block/FallingBlockEntityMixin`, `mixin/entity/tamed_teleport/TamableAnimalMixin`, `neoforge/mixin/entities_stick_sublevels/effects/LivingEntityMixin` |
| `entity-riding` | major | 4 | `mixin/entity/entity_rotations_and_riding/EntityMixin`, `mixin/entity/entity_rotations_and_riding/LivingEntityMixin`, `mixin/entity/entity_rotations_and_riding/PlayerMixin`, `mixinhelpers/entity/entity_riding_sub_level_vehicle/EntityRidingSubLevelVehicleHelper` |
| `entity-tick-rate` | major | 3 | `mixin/entity/entity_sublevel_collision/ItemEntityMixin`, `mixin/entity/server_entities_tick/ChunkMapMixin`, `mixin/entity/server_entities_tick/ServerLevelMixin` |
| `entity-unloading` | major | 1 | `mixin/entity/entity_unloading/PersistentEntitySectionManagerMixin` |
| `entity-query` | major | 2 | `mixin/block_placement/EntityGetterMixin`, `mixin/entity/entity_aabb_lookup/ServerLevelMixin` |
| `explosion-ray` | major | 1 | `mixin/explosion/ExplosionMixin` |
| `fluid-occlusion` | major | 3 | `mixin/water_occlusion/EntityMixin`, `neoforge/mixin/entity/entity_swimming/EntityMixin`, `neoforge/mixinhelper/entity/SableInterimCalculation` |
| `block-placement-frame` | major | 2 | `mixin/block_placement/BlockPlaceContextMixin`, `mixin/block_placement/UseOnContextMixin` |
| `interaction-range` | major | 8 | `mixin/block_decal_render/ServerLevelMixin`, `mixin/conduit/ConduitBlockEntityMixin`, `mixin/compatibility/computercraft/WirelessNetworkMixin`, `mixin/entity/parrot/ParrotMixin`, `mixin/interaction_distance/EntityMixin`, `mixin/interaction_distance/PlayerMixin`, `mixin/particle/ServerLevelMixin`, `mixin/plot/PlayerListMixin` |
| `inside-block-effects` | major | 1 | `mixin/entity/entities_in_blocks/EntityMixin` |
| `entity-nbt` | major | 1 | `mixin/tracking_points/EntityMixin` |
| `packet-extension` | major | 4 | `mixin/entity/entities_stick_sublevels/packet_mixin/ClientboundMoveEntityPacketPosMixin`, `...PosRotMixin`, `...ClientboundTeleportEntityPacketMixin`, `mixinterface/entity/entities_stick_sublevels/packet_mixin/PacketActuallyInSubLevelExtension` |
| `plot-lighting` | major | 2 | `mixin/plot/lighting/BlockAndTintGetterMixin`, `mixin/plot/lighting/LevelChunkMixin` |
| `pathfinding` | minor | 8 | `mixin/entity/entity_pathfinding/{FlyNodeEvaluator,GroundPathNavigation,PathfindingContext,Path,PathNavigation,RandomPos,WalkNodeEvaluator}Mixin`, `mixinterface/entity/pathfinding/PathExtension` |
| `can-see-sky` | minor | 2 | `mixin/entity/sublevels_block_sky/SubLevelsBlockSkyMixin`, `mixinhelpers/entity/sublevels_block_sky/SubLevelsBlockSkyMixinHelper` |
| `biome-temperature` | minor | 1 | `mixin/prevent_freezing/BiomeMixin` |
| `sculk-vibration` | minor | 4 | `mixin/sculk_vibrations/{EuclideanGameEventListenerRegistry,GameEventDispatcher,VibrationSystemListener,VibrationSystemTicker}Mixin` |
| `sign-block-entity` | minor | 1 | `mixin/sign_interaction/SignBlockEntityMixin` |
| `udp-channel` | minor | 6 | `mixin/udp/{Connection,MinecraftServer,PlayerList,ServerConnectionListener}Mixin`, `mixinterface/udp/ConnectionExtension`, `mixinterface/udp/ServerConnectionListenerExtension` |
| `leash-physics` | minor | 1 | `mixin/entity/entity_leashing/LeashableMixin` |
| `projectile-state` | minor | 1 | `mixin/entity/trident/ThrownTridentMixin` |
| `command-fork` | minor | 1 | `mixin/command/ExecuteCommandMixin` |
| `command-data-source` | minor | 1 | `mixin/command/DataCommandsMixin` |
| `block-entity-api` | minor | 1 | `mixin/assembly/AbstractFurnaceBlockEntityMixin` |
| `portal-frame` | minor | 2 | `mixin/portal/EntityMixin`, `mixin/portal/NetherPortalBlockMixin` |
| `sleep-position` | minor | 1 | `mixin/respawn_point/sleeping/LivingEntityMixin` |
| `world-border` | minor | 2 | `mixin/world_border/WorldBorderMixin`, `mixinterface/world_border/WorldBorderExtension` |

## (c) Not applicable — 98 patches

| Reason | Count | Files |
|---|---:|---|
| Client-only (render, camera, particles, sound, client chunk cache, debug overlay) | 28 | `mixin/camera/camera_rotation/EntityMixin`, `mixin/debug_render/DebugRendererMixin`, `mixin/enchanting_table/EnchantingTableBlockEntityMixin`, `mixin/entity/entities_stick_sublevels/LivingEntityMixin`, `mixin/water_occlusion/WaterFluidMixin`, `mixinhelpers/{block_outline_render/SubLevelCamera, camera/camera_rotation/EntitySubLevelRotationHelper, camera/new_camera_types/SableCameraTypes, compatibility/shouldersurfing/SablePerspectives, entity/entity_rendering/EntityRenderRotationState, entity/entity_rendering/SubLevelPoseHelper, entity/entity_rendering/shadows/SubLevelEntityShadowRenderer, loaded_chunk_debug/SableChunkDebugRenderer, sublevel_render/vanilla/VanillaSubLevelBlockEntityRenderer}`, `mixinterface/{BlockEntityRenderDispatcherExtension, camera/camera_zoom/CameraZoomExtension, compatibility/iris/ExtendedShaderExtension, dynamic_directional_shading/ModelBlockRendererCacheExtension, clip_overwrite/LevelPoseProviderExtension, particle/ParticleExtension, toast/SableToastableServer, water_occlusion/CameraWaterOcclusionExtension}`, `neoforge/mixin/{block_entity_visible/BlockEntityRenderDispatcherMixin, block_outline_render/LevelRendererMixin, camera_rotation/CameraMixin, dynamic_directional_shading/SectionCompilerMixin, sound/MovingSoundInstanceDelegateMixin}`, `neoforge/platform/SableSubLevelRenderPlatformImpl` |
| Accessor, debug, allocation/perf trick, or state holder that only exists because Java patches bytecode | 30 | `mixin/{AbstractSableMixinPlugin, block_properties/BlockStateMixin, chunk_container_replacement/LevelChunkSectionMixin, clip_overwrite/ClipContextMixin, entity/entity_collision/CollisionContextMixin, entity/entity_collision/EntityMixin, entity/entity_sublevel_collision/LevelMixin, extension/EntityMixin, level_accelerator/ServerChunkCacheAccessor, loaded_chunk_debug/LevelChunkMixin, physics/ServerLevelMixin, punching/ItemInvoker, voxel_shape_iteration/BitSetDiscreteVoxelShapeAccessor, voxel_shape_iteration/DiscreteVoxelShapeAccessor, voxel_shape_iteration/VoxelShapeMixin, water_occlusion/ServerLevelMixin, world_border/LevelMixin}`, `mixinhelpers/{entity/entity_collision/TheFasterEntityCollisionContext, voxel_shape_iteration/FastVoxelShapeIterator, voxel_shape_iteration/LongArrayDiscreteVoxelShape}`, `mixinterface/{EntityExtension, block_properties/BlockStateExtension, clip_overwrite/ClipContextExtension, entity/entity_collision/EntityExtension, entity/entity_sublevel_collision/LevelExtension, loaded_chunk_debug/DebugChunkProviderAttachments, loaded_chunk_debug/DebugLevelChunkExtension, physics/ServerLevelSceneExtension, voxel_shape_iteration/FastVoxelShapeIterable, water_occlusion/WaterOcclusionContainerHolder}` |
| Third-party mod compatibility (Etched, Exposure, Jade, Jade Addons, Shoulder Surfing, Vista, Backpacks, PMWeather, Sodium Extras, Flywheel) | 25 | `mixin/compatibility/{etched/StopListeningSoundMixin, exposure/CameraPosesMixin, exposure/CameraStandEntityMixin, jade/BlockAccessorImplMixin, jade/RayTracingMixin, jadeaddons/CreatePluginMixin, shouldersurfing/ObjectPickerMixin, shouldersurfing/ShoulderSurfingCameraMixin, vista/ViewFinderAccessMixin}`, `neoforge/mixin/compatibility/{backpacks/BackpackPickupEventsMixin, flywheel/* (10), pmweather/* (4), sodiumextras/EmbyToolsMixin}` |
| Game tests and the test harness | 7 | `mixin/game_test/{GameTestInfoMixin,StructureUtilsMixin,TestCommandMixin}`, `neoforge/gametest/{AssemblyTest,PhysicsTest,SableTestHelper,TestProgressBar}` |
| Loader abstraction and mod entry point | 8 | `neoforge/platform/{SableAssemblyPlatformImpl,SableChunkEventPlatformImpl,SableEventPlatformImpl,SableEventPublishPlatformImpl,SableLoaderPlatformImpl,SablePlatformImpl,SablePlotPlatformImpl}`, `neoforge/SableNeoForge` |

## Host gap list

Each entry says what the host would have to expose. None of these exist today
unless the text says so; `workaround` is what the port does meanwhile.

### critical

**`entity-movement-sweep`** — host entities (players, mobs, items, arrows) must
move against sub-level geometry.
*Expose:* a movement resolver next to `entity-collision.wit`,
`resolve-movement(entity-id, motion) -> {motion, horizontal-collision,
vertical-collision, on-ground, minor-horizontal-collision, tracking-sub-level}`,
with the boxes from `set-entity-collision-boxes`, supporting step-up and the
per-axis slide vanilla does.
*Today:* the collision boxes make a ship solid and push players out; sliding,
step-up and the collision flags are missing. `SubLevelStanding` ports the edge
and stand-up queries.

**`entity-wire-position`** — entities on a ship must be sent relative to the ship.
*Expose:* `entity.wit` `set-tracking-position-mode(entity-id, mode)` with a
`sub-level-relative` mode, or a raw-packet hook that rewrites the position triple
of the move/teleport packets.
*Today:* the plugin sends the ship pose on its own channel, so the Sable client
derives local positions.

**`player-move-packet`** — a player on a ship sends ship-relative movement and
must not be rejected as "moved too quickly".
*Expose:* decoded `ServerboundMovePlayerPacket` fields as mutable data plus a
per-player flag to disable the moved-too-quickly / moved-wrongly checks.
*Today:* `player-move-event` is cancellable but cannot rewrite the packet; a
cancelled move leaves the player behind.

**`entity-tracking-follow`** — an entity standing on a ship must be carried by it.
*Expose:* `set-entity-anchor(entity-id, sub-level-id, local-pos)`, re-applied by
the host after physics, or a post-physics teleport hook that bypasses the
movement check.
*Today:* the plugin teleports tracked entities after `pipeline.postPhysicsTicks()`.

**`clip-raycast`** — block and entity raycasts must continue into sub-levels.
*Expose:* `world.wit` `ray-trace(start, end, include-sub-levels: bool)` returning
the sub-level id and local position, and the same option on the entity raycast.
*Today:* the plugin ray-traces the plot chunks itself and picks the nearer hit;
the host's targeting stays world-only.

**`chunk-source`** — plot chunks are real chunks at the plot yard and must be
served from the container, not generated or saved as terrain.
*Expose:* creating a chunk at an arbitrary position (`create-empty-chunk`),
suppressing mob spawning in plot chunks, and marking a chunk range as
plugin-owned for saving. `chunk-tickets.wit` and `chunk-streaming.wit` already
cover force-loading and sending.
*Today:* W2 treats unloaded plot chunks as empty and rebuilds them from storage.

**`chunk-serialization`** — a plot chunk must be serialized into the sub-level
file and restored.
*Expose:* `serialize-chunk(x, z) -> bytes` / `deserialize-chunk(x, z, bytes)`
including block entities, ticks and light.
*Today:* W2 stores blocks block-by-block in its own region format; block
entities and scheduled ticks are lost.

### major

**`entity-block-pos`** — "which block is this entity in/on" must resolve ship
blocks. *Expose:* `block-below(entity-id, max-distance)` and
`block-at-entity(entity-id)` returning plot positions, plus
`block-state-at(pos)` reading plot chunks.

**`entity-riding`** — riding a vehicle inside a sub-level. *Expose:*
`get-vehicle(entity-id)`, `dismount(entity-id, world-pos)`, and a passenger
position mode for host vehicles.

**`entity-tick-rate`** — entities in plot chunks must tick when a player is near
the ship. *Expose:* the entity-ticking-range decision for vanilla entities, or
pinning an entity to a chunk position.

**`entity-unloading`** — entities in plot chunks must not unload with the chunk.
*Expose:* a cancellable `chunk-unload-event`, or "keep entities" semantics on
`chunk-tickets.wit`.

**`entity-query`** — `getEntities(box)` must include entities inside sub-levels.
*Expose:* `get-entities-in-box(box, include-sub-levels: bool)`.

**`explosion-ray`** — an explosion must destroy ship blocks and push the body.
*Expose:* a pre-explosion hook with the blast parameters and a way to add blocks
to the destroyed set. `create-explosion` exists but only affects world blocks.
*Today:* `SubLevelExplosions.walk` is the ported algorithm.

**`fluid-occlusion`** — water carried by a ship must make entities swim.
*Expose:* `get-fluid-state(pos)` reading plot chunks, and a per-entity
"touching fluid" result computed with sub-levels.

**`block-placement-frame`** — placing against a rotated ship. *Expose:* placement
rules or `player-interact-event` carrying the local clicked position and local
facing.

**`interaction-range`** — every "is X near Y" check must project ship positions.
*Expose:* `project-position(world, pos)` used by the host's own distance checks,
or the checks as cancellable events with the distance.

**`inside-block-effects`** — standing inside a ship block (fire, lava, portal,
cactus) must apply its effects. *Expose:* run the inside-block pass over plot
blocks, or let the plugin report the overlapped blocks.

**`entity-nbt`** — per-entity persistent data. *Expose:*
`get-entity-nbt`/`set-entity-nbt` for vanilla entities.

**`packet-extension`** — Sable appends one boolean to three vanilla entity
packets. *Expose:* a clientbound packet hook that can append bytes.

**`plot-lighting`** — plot chunks need their own light. *Expose:* let a plugin
own the light of a chunk range.

### minor

`pathfinding`, `can-see-sky`, `biome-temperature`, `sculk-vibration`,
`sign-block-entity`, `udp-channel` (TCP fallback exists), `leash-physics`,
`projectile-state`, `command-fork` (`/sable` substitutes), `command-data-source`,
`block-entity-api`, `portal-frame`, `sleep-position`, `world-border` — see
`host_gap.dart` for each one's exposure and workaround.

## What was ported

`lib/src/sublevel/vanilla/`:

| File | Java origin | What it does |
|---|---|---|
| `mixin_inventory.dart` | the mixin tree | the table above as data |
| `host_gap.dart` | — | the gap list as data |
| `entity_tracking_rules.dart` | `entity_sublevel_collision/EntityMixin`, `AbstractMinecartMixin`, `ItemEntityMixin`, `entities_stick_sublevels/effects/EntityMixin`, `EntityRidingSubLevelVehicleHelper`, `ActiveSableCompanion` | which sub-level an entity is on, plot-bounds leash, local/global block positions, distance with sub-levels, riding kick |
| `entity_collision_effects.dart` | `CanFallAtleastHelper`, `entity_sublevel_collision/{PlayerMixin,LivingEntityMixin}`, `player_standup/PlayerMixin` | `canFallAtLeast`, edge back-off, inherited-velocity drag, bounce / `flyIntoWall` damage |
| `projectile_handlers.dart` | `entity/projectile/ProjectileMixin`, `arrows_hit_blocks/AbstractArrowMixin`, `recoil/ProjectileDispenseBehaviorMixin` | shot direction and inherited velocity, arrow stick + impulse, dispenser recoil |
| `explosion_handlers.dart` | `explosion/ExplosionMixin`, `explosion/ServerLevelMixin` | blast-centre projection, the block/impulse ray walk |
| `block_event_handlers.dart` | `entity_kicking/*`, `fluids_on_sub_levels/FlowingFluidMixin`, `prevent_overgrowth/VineBlockMixin`, `stop_lightning/ServerLevelMixin`, `AbstractMinecartMixin` | drop/spawn kicking, plot leash, fluid spread guard, overgrowth guard, lightning guard |
| `player_handlers.dart` | `teleport_players/ServerPlayerMixin`, `death_message/*`, `respawn_point/*`, `player_freezing/*` | teleport/respawn/sleep projection, fall message, respawn anchor, freeze state machine |
| `impact_callbacks.dart` | `physics/callback/*`, `mixin/impact/*` | fragile/beehive/bell/TNT collision callbacks, registered by block key |

Verification: `puro dart test test/w5_vanilla_parity_test.dart` (90 tests) —
inventory totals, gap/hook integrity, and the behaviour of every ported handler.
