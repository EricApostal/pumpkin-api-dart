# Porting inventory — Sable, Simulated, Aeronautics, Offroad

What has to exist, in what order, to port these four mods onto Pumpkin as plugins.
This is an **inventory and a slice plan**, not a port. Nothing here is implemented.

**Provenance.** Read from the trees at:

| tree | revision |
|---|---|
| `~/Documents/development/languages/java/sable` | `227077f`, branch `port/26.3` |
| `~/Documents/development/languages/java/Simulated-Project` | `2aa5963`, branch `port/26.3` |
| `~/Documents/development/languages/java/Create` | `b59ea26d0`, branch `port/26.3` (only for `DyedBlockList`) |
| `~/Documents/development/languages/java/Veil` | in-tree copy used by both |

No code was built or run for this document; every claim is a static reading of the
listed file. Counts are derived, not estimated — §0 says how each one was obtained.

The machine-readable companion is [aero-port-manifest.json](aero-port-manifest.json):
all 56 channels with `id, version, phase, flow, optional, codec, source`, and every
registry id per mod.

---

## 0. How the numbers were derived

| claim | derivation |
|---|---|
| Java files per module | `find <module>/src/main/java -name '*.java' \| wc -l` (build output excluded) |
| block ids | one blockstate JSON per block in `<module>/common/src/generated/resources/assets/<mod>/blockstates/`; cross-checked against the `REGISTRATE.block(...)` sites in `index/*Blocks.java` |
| block entity, entity type, menu, data component ids | `grep -oE 'blockEntity\("…"\|entity\("…"\|menu\("…"\|create\("…"'` on the `index/` classes, then read for loops |
| item count | block items = every block builder that calls `.item()` (read per chain, including the dyed loops) + standalone `REGISTRATE.item(...)` entries + the one fluid bucket |
| channels | every `new Type<>(Mod.path("…"))` in the four `network/` trees, joined against the `registerClientbound/registerServerbound(<Class>.TYPE, …)` lines in that mod's packet manager |
| version / phase / optional | the `VeilPacketManager.create(modId, version)` argument and the `PayloadRegistrar` call it produces (§2.1) |
| dependency edges | the `api(project(...))` lines in the Gradle files, plus import counts (`grep -h '^import dev.…' \| cut`) |
| registration order | source order of the field initialisers in `index/*Blocks.java` etc., and `DyeColor.values()` order inside `DyedBlockList` (`Create/src/main/java/com/simibubi/create/foundation/block/DyedBlockList.java:20`) |

Totals: **1,718 Java files** across the ten modules (plus 4 in the two `buildSrc`
trees and 1 in `tools/`, which are build/tooling and not part of the port).
The ticket said ~1,470. **1,003** files sit outside every directory named
`client`, `render`, `ponder`, `mixin`, `mixinterface`, `mixinhelpers` or
`gametest`; the rest are client code or mixins, and only some mixins carry server
behaviour (§1.3). Treat 1,718 as the tree size and 1,003 + the server-relevant
mixins as the port surface.

---

## 1. Module map

### 1.1 Modules

| module | Java files | build role | responsibility |
|---|---:|---|---|
| `sable/common` | 540 | published (`dev.ryanhcode.sable:*:2.0.6`) | sub-level data model, plot/chunk storage, physics pipeline abstraction, assembly API, TCP/UDP protocol, commands, config. **No blocks, items, block entities, entities or menus of its own** — it is a library. |
| `sable/neoforge` | 209 | loader half | platform services, NeoForge events, mixins into vanilla and into Create (contraption/nozzle/camera integration), `sable_rapier` native packaging |
| `sable/fabric` | 27 | **not in the build** (`settings.gradle` includes only `common`, `neoforge`, `sable_rapier`) | dead for this port |
| `sable/sable_rapier` | 14 | `jarJar`ed runtime native | JNI bindings (`physics/impl/rapier/*`) over a Rust crate: `src/main/rust/**` is 5,854 lines of Rust (rapier + marten) that the plugin has to replace or bind to |
| `simulated/common` | 606 | published | the base content mod: physics assembler, honey glue, ropes, springs, bearings, sensors, redstone blocks, typewriter, nav table, sails, End Sea, world presets, 37 of the 56 channels |
| `simulated/neoforge` | 48 | loader half | recipe types, particle/stat registration, events, datagen, gametests |
| `aeronautics/common` | 182 | published | hot-air balloons/envelopes/burner, propellers and bearings, levitite, mounted potato cannon |
| `aeronautics/neoforge` | 22 | loader half | levitite-blend fluid + bucket, particle types, JEI (excluded), services |
| `offroad/common` | 61 | published | borehead bearing (multi-block mining contraption), wheel mount, rock-cutting wheel, tires |
| `offroad/neoforge` | 9 | loader half | sound events, services, data |
| `all-neoforge` | 0 | dev run harness | loads all six modules in one game |
| `aeronautics-bundled` | 0 | published jar | `jarJar`s the three mods; `neoforge.mods.toml` requires Create, Sable and Flywheel (`build.gradle:115,124`) |

`sable/buildSrc` and `Simulated-Project/buildSrc` hold 2 Java files each; both are
Gradle plugins, not mod code.

### 1.2 What each module is responsible for, by package

`sable/common` (540):

| package | files | responsibility |
|---|---:|---|
| `sublevel/` | 62 | `SubLevel`/`ServerSubLevel`/`ClientSubLevel`, plot levels (`plot/`), chunk storage and serialisation (`storage/`), physics and tracking systems (`system/`), entity collision, water occlusion |
| `physics/` | 25 | config (`block_properties/`, `dimension_physics/`), floating-block controller, callbacks, `impl/none` fallback |
| `api/` | 62 | the public surface: `SubLevelHelper`, `api/sublevel` (containers, observers, tickets), `api/physics` (pipeline, bodies, colliders, constraints, forces, mass), `api/block` (lift providers, propeller actors, collision callbacks), `api/schematic`, `api/entity`, `api/event`, `api/math` |
| `network/` | 44 | 17 TCP payloads, 6 UDP packet kinds, UDP server/auth |
| `mixin/` | 228 | client rendering, camera, contraption integration, chunk/level hooks — the single largest directory and the least portable part |
| `mixinhelpers/`, `mixinterface/` | 15 + 33 | helper classes and accessor interfaces for those mixins |
| `command/` | 23 | `/sable` subcommands (sub-level spawn/list/remove/physics debug) |
| `config/`, `platform/`, `util/`, `index/`, `sound/`, `debug/` | 1+9+13+3+2+3 | config specs, loader abstraction, maths/buffer helpers, two attributes, sounds, debug renderers |

`simulated/common` (606): `content/` 253 (blocks 182, entities 19, items 8,
physics_staff 7, display sources 10, particle 8, navigation targets 7, end_sea 5,
worldgen 3), `mixin/` 83, `ponder/` 48, `network/` 46, `index/` 38, `util/` 30,
`compat/` 25, `service/` 14, `multiloader/` 12, `config/` 10, `api/` 10, `data/` 7,
`client/` 5, `registrate/` 4, `events/` 2, `command/` 2.

`aeronautics/common` (182): `content/` 99 (blocks 70 — `hot_air` 32,
`propeller` 30, `mounted_potato_cannon` 5, `levitite` 3 — plus `particle` 11,
`ponder` 14), `index/` 26, `mixin/` 22, `api/` 8, `config/` 7, `data/` 6,
`network/` 2, `util/` 4, `events/` 2, `mixinterface/` 2.

`offroad/common` (61): `content/` 24 (`borehead_bearing` 5, `rock_cutting_wheel` 6,
`wheel_mount` 4, `contraptions` 2, `ponder` 5, `items/tire` 1, `components` 1,
`entities` 1), `index/` 12, `config/` 6, `handlers/` 5, `mixin/` 4, `network/` 2,
`data/` 3, `events/` 1, `service/` 1.

### 1.3 Not on the server path

These directories are client rendering, screens, particles, ponder scenes, or
mixins. A server port does not translate them; it only has to know which mixins
carry **server behaviour** (the slice owner decides per file).

| module | `client/` | `render/` | `ponder/` | `mixin/` | `mixinterface/` | `mixinhelpers/` |
|---|---:|---:|---:|---:|---:|---:|
| `sable/common` | 4 | 30 | – | 228 | 33 | 15 |
| `simulated/common` | 14 | 3 | 56 | 83 | – | – |
| `aeronautics/common` | 6 | – | 18 | 22 | 2 | – |
| `offroad/common` | 4 | – | 5 | 4 | 1 | – |

Counted with `find … -type d -name <dir> -exec find {} -name '*.java' \;`.
They overlap (e.g. `sublevel/render/` is inside `render/` counting), so do not sum
them against 1,718.

---

## 2. Network surface

### 2.1 How a channel exists at all

All four mods go through Veil, not through NeoForge directly:

- `SimPacketManager.java:26` — `VeilPacketManager.create(Simulated.MOD_ID, "0.1")`
- `SableTCPPackets.java:11` — `VeilPacketManager.create(Sable.MOD_ID, "1")`
- `AeroPacketManager.java:8` — `VeilPacketManager.create(Aeronautics.MOD_ID, "0.1")`
- `OffroadPacketManager.java:8` — `VeilPacketManager.create(Offroad.MOD_ID, "0.1")`

`NeoForgeVeilPacketManager` turns each manager into **one `PayloadRegistrar` with
that version** and registers every payload through it:

```java
PayloadRegistrar registrar = event.registrar(this.version);      // :42
PayloadRegistrar optionalRegistrar = registrar.optional();       // :43
(packet.optional ? optionalRegistrar : registrar)
    .playToClient(...)                                           // :47
(packet.optional ? optionalRegistrar : registrar)
    .playToServer(...)                                           // :54
```

`VeilPacketManager`'s convenience overloads pass `optional = false`
(`VeilPacketManager.java:60-62, 84-86`), and none of the four managers uses the
4-argument form, so **every channel below is `phase = play`, `optional = false`,
and the version is the mod's single string** — not a per-channel version. That is
the single most important fact for the handshake: `sable` = `"1"`,
`simulated`/`aeronautics`/`offroad` = `"0.1"`.

Missing or mis-versioned channels are exactly what the client refuses on
(`docs/neoforge-protocol.md`, "channel announcement and classification"); a
declaration that lists these 56 with the right versions removes that refusal.

### 2.2 Channels, grouped by feature

`codec` is the field shape of the payload's `StreamCodec`; `composite(n)` means
`n` fields in declaration order (the field codecs are in the JSON manifest).

**Sable — sub-level lifecycle and physics (17: 15 clientbound, 2 serverbound)**

| id | flow | codec | source |
|---|---|---|---|
| `sable:start_tracking_sub_level` | clientbound | of(read/write) | `network/packets/tcp/ClientboundStartTrackingSubLevelPacket.java` |
| `sable:finalize_sub_level` | clientbound | of(read/write) | `…/ClientboundFinalizeSubLevelPacket.java` |
| `sable:stop_tracking_sub_level` | clientbound | of(read/write) | `…/ClientboundStopTrackingSubLevelPacket.java` |
| `sable:change_bounds_sublevel` | clientbound | of(read/write) | `…/ClientboundChangeBoundsSubLevelPacket.java` |
| `sable:change_sub_level_name` | clientbound | composite(2) | `…/ClientboundChangeSubLevelNamePacket.java` |
| `sable:stop_moving_sub_level` | clientbound | of(read/write) | `…/ClientboundStopMovingSubLevelPacket.java` |
| `sable:recently_split_sub_level` | clientbound | composite(3) | `…/ClientboundRecentlySplitSubLevelPacket.java` |
| `sable:dimension_physics` | clientbound | composite(1) | `…/ClientboundDimensionPhysicsPacket.java` |
| `sable:physics_property` | clientbound | composite(1) | `…/ClientboundPhysicsPropertyPacket.java` |
| `sable:floating_material` | clientbound | composite(2) | `…/ClientboundFloatingBlockMaterialPacket.java` |
| `sable:freeze_player` | clientbound | of(read/write) | `…/ClientboundFreezePlayerPacket.java` |
| `sable:enter_gizmo_mode` | clientbound | of(read/write) | `…/ClientboundEnterGizmoPacket.java` |
| `sable:punch_sub_level` | serverbound | of(read/write) | `…/ServerboundPunchSubLevelPacket.java` |
| `sable:gizmo_move_sub_level` | serverbound | of(read/write) | `…/ServerboundGizmoMoveSubLevelPacket.java` |
| `sable:udp_activation` | clientbound | of(read/write) | `…/ClientboundSableUDPActivationPacket.java` |
| `sable:snapshot_packet` | clientbound | of(read/write) | `network/packets/ClientboundSableSnapshotDualPacket.java` |
| `sable:snapshot_info_packet` | clientbound | of(read/write) | `…/ClientboundSableSnapshotInfoDualPacket.java` |

The last two are normally carried **over UDP** (`SableUDPPacketType.SNAPSHOT`,
`SNAPSHOT_INFO`), but they are also registered as TCP payloads, so they are part of
the negotiated set.

**Simulated — assembly, glue, ropes, staff (37: 14 clientbound, 23 serverbound)**

| id | flow | codec | source |
|---|---|---|---|
| `simulated:assemble` | serverbound | composite(1) | `packets/AssemblePacket.java` |
| `simulated:assembler_failed` | clientbound | composite(1) | `packets/physics_assembler/PhysicsAssemblerFailedPacket.java` |
| `simulated:flick_assembler_lever` | clientbound | composite(2) | `packets/physics_assembler/PhysicsAssemblerFlickAndHoldLeverPacket.java` |
| `simulated:be_observed` | serverbound | map | `packets/BlockEntityObservedPacket.java` |
| `simulated:honey_glue_spawn` | serverbound | of(read/write) | `packets/honey_glue/HoneyGlueSpawnPacket.java` |
| `simulated:honey_glue_change_bounds` | serverbound | of(read/write) | `packets/honey_glue/HoneyGlueChangeBoundsPacket.java` |
| `simulated:honey_glue_sync` | clientbound | of(read/write) | `packets/honey_glue/HoneyGlueSyncBoundsPacket.java` |
| `simulated:place_merging_glue` | serverbound | composite(5) | `packets/PlaceMergingGluePacket.java` |
| `simulated:place_spring` | serverbound | composite(5) | `packets/PlaceSpringPacket.java` |
| `simulated:break_rope` | serverbound | composite(1) | `packets/RopeBreakPacket.java` |
| `simulated:ride_rope` | serverbound | composite(2) | `packets/RopeRidingPacket.java` |
| `simulated:rope_data` | clientbound | of(read/write) | `packets/rope/ClientboundRopeDataPacket.java` |
| `simulated:rope_stopped` | clientbound | map | `packets/rope/ClientboundRopeStoppedPacket.java` |
| `simulated:physics_staff_action` | serverbound | composite(3) | `packets/physics_staff/PhysicsStaffActionPacket.java` |
| `simulated:physics_staff_drag` | serverbound | of(read/write) | `packets/physics_staff/PhysicsStaffDragPacket.java` |
| `simulated:physics_staff_beam` | clientbound | composite(3) | `packets/physics_staff/PhysicsStaffBeamPacket.java` |
| `simulated:physics_staff_locks` | clientbound | composite(2) | `packets/physics_staff/PhysicsStaffLocksPacket.java` |
| `simulated:physics_staff_drag_sessions` | clientbound | composite(2) | `packets/physics_staff/PhysicsStaffDragSessionsPacket.java` |
| `simulated:plunger_launcher_shoot` | clientbound | composite(1) | `packets/PlungerLauncherShootPacket.java` |
| `simulated:update_player_handle` | serverbound | composite(3) | `packets/UpdatePlayerUsingHandlePacket.java` |
| `simulated:players_holding_handles` | clientbound | composite(1) | `packets/handle/ClientboundPlayersHoldingHandlePacket.java` |
| `simulated:steering_wheel_update` | serverbound | composite(3) | `packets/SteeringWheelPacket.java` |
| `simulated:throttle_lever_signal` | serverbound | composite(2) | `packets/ThrottleLeverSignalPacket.java` |
| `simulated:configure_altitude_sensor` | serverbound | composite(3) | `packets/ConfigureAltitudeSensorPacket.java` |
| `simulated:configure_modulating_linked_reciever` | serverbound | composite(3) | `packets/ConfigureModulatingLinkedRecieverPacket.java` |
| `simulated:nameplate_change_name` | serverbound | composite(2) | `packets/name_plate/NameplateChangeNamePacket.java` |
| `simulated:key_interaction` | serverbound | composite(4) | `packets/linked_typewriter/TypewriterKeyInteractionPacket.java` |
| `simulated:linked_typewriter_save` | serverbound | composite(3) | `packets/linked_typewriter/TypewriterKeySavePacket.java` |
| `simulated:entry_modify` | serverbound | composite(2) | `packets/linked_typewriter/TypewriterMenuModifySlots.java` |
| `simulated:linked_typewriter_bind_item` | serverbound | composite(2) | `packets/linked_typewriter/TypewriterSaveKeyToItemPacket.java` |
| `simulated:typewriter_disconnect_user` | serverbound | composite(1) | `packets/linked_typewriter/TypewriterDisconnectUser.java` |
| `simulated:request_diagram_data` | serverbound | composite(1) | `packets/contraption_diagram/RequestDiagramDataPacket.java` |
| `simulated:diagram_data` | clientbound | composite(2) | `packets/contraption_diagram/DiagramDataPacket.java` |
| `simulated:save_diagram` | serverbound | composite(2) | `packets/contraption_diagram/DiagramSaveConfigPacket.java` |
| `simulated:open_diagram` | clientbound | composite(2) | `packets/contraption_diagram/DiagramOpenPacket.java` |
| `simulated:update_client_lodestone` | clientbound | composite(2) | `packets/lodestone_compass/UpdateClientLodestonePositionPacket.java` |
| `simulated:end_sea` | clientbound | of(read/write) | `packets/end_sea/ClientboundEndSeaPacket.java` |

**Aeronautics (1, serverbound)** `aeronautics:levitite_blend_crystallize` —
`composite(2)` — `network/packets/LevititeCatalystCrystallizationPacket.java`.

**Offroad (1, clientbound)** `offroad:borehead_sync_blocks` — `of(read/write)` —
`network/borehead_bearing/ClientboundMultiMiningSync.java`.

**Summary:** 56 channels, 35 composite codecs, 19 hand-written `StreamCodec.of`,
2 `map`; 30 clientbound and 26 serverbound.

### 2.3 The UDP side-channel (Sable only)

Not part of NeoForge negotiation, but required for sub-level motion at play time:

- the server binds a **datagram socket on the same address and port as the TCP
  listener** (`mixin/udp/ServerConnectionListenerMixin.java:81` `.localAddress(inetAddress, port)`),
  plus a local channel for single-player (`:101`);
- `SableUDPPacketType` has 6 kinds: `PING`, `SNAPSHOT`, `SNAPSHOT_INFO`, `AUTH`,
  `KEEP_ALIVE_CLIENTBOUND`, `ALIVE_SERVERBOUND`;
- `sable:udp_activation` (TCP) tells the client the UDP port is ready; then
  `AUTH` authenticates and the snapshots move to UDP;
- it is optional in behaviour: `SableConfig.ATTEMPT_UDP_NETWORKING` (default
  `true`) and `DISABLE_UDP_PIPELINE` (default `false`) let the client fall back to
  TCP. A server that never answers `udp_activation` still connects; motion is
  then carried by the TCP snapshot payloads.

### 2.4 What the declaration has to say

With the host handshake (`docs/neoforge-host.md`), each mod's own plugin declares
its channels. The four addons do it through Create's generic hook (`CreateAddon`,
`example/create/lib/src/core/addon.dart`) and own their tables
(`example/sable/lib/sable_channels.dart`, `example/simulated/lib/src/index/sim_channels.dart`,
`example/aeronautics/lib/aeronautics_channels.dart`,
`example/offroad/lib/src/network/offroad_channels.dart`):

```dart
DeclaredPayload('sable:change_bounds_sublevel', '1',
                serverbound: false, optional: false)
```

and the same for the other 55, with `version: '0.1'` for `simulated:*`,
`aeronautics:*`, `offroad:*`. `optional: false` is the default and is correct here.

Veil's own three channels (`veil:add_post_processing`,
`veil:clear_post_processing`, `veil:remove_post_processing`) are registered
**optional** (`Veil/.../impl/network/VeilPacketSender.java:16-18`), so they do not
need declaring and cannot cause a refusal.

### 2.5 Codec porting note

The codecs are the contract for the bytes, not just the ids. Two shapes matter:

- `StreamCodec.of(read/write)` payloads have hand-written bodies (e.g.
  `ClientboundRopeDataPacket.read` writes an `int` count then N `Vector3d`s,
  `network/packets/rope/ClientboundRopeDataPacket.java:33-60`) — these are the
  packets where a byte-for-byte port is unavoidable.
- `composite(...)` payloads use vanilla/Veil codecs (`BlockPos.STREAM_CODEC`,
  `UUIDUtil.STREAM_CODEC`, `ByteBufCodecs.*`, `CatnipStreamCodecs.HAND`), which
  map onto the host's existing codec set.

---

## 3. Registry surface

### 3.1 Ordering

NeoForge registry sync is **ordered**, and block-state ids are derived from
registry order (block registry insertion order, then each block's state list), so
a plugin that declares the same names in a different order produces different
state ids and the client misreads every block. Two ordering rules follow from the
tree:

1. **Class order** is `Simulated.init` / `Aeronautics.init` / `Offroad.init` /
   `Sable.init` — `Simulated.java:37-57`, `Aeronautics.java:37-48`,
   `Offroad.java:37-45`, `Sable.java:39-42`. Blocks are registered before items,
   block entities after items, and data components last.
2. **Within a class**, field initialiser order. Every `REGISTRATE.block(...)`
   registers when its initialiser runs. Dyed families expand in
   `DyeColor.values()` order — `white, orange, magenta, light_blue, yellow, lime,
   pink, gray, light_gray, cyan, purple, blue, brown, green, red, black`
   (`Create/src/main/java/com/simibubi/create/foundation/block/DyedBlockList.java:20`).

The ordered registration sites are listed in Appendix B.

One id is registered from a **loader module**, not from `AeroBlocks`:
`aeronautics:levitite_blend` comes from `AeroFluidsNeoForge.LEVITITE_BLEND`
(`aeronautics/neoforge/.../index/AeroFluidsNeoForge.java:24`), whose class is first
touched through `NeoForgeAeroLevititeService`. Its position among the other
`aeronautics` blocks therefore depends on when that service is loaded, and the
plugin must pin it explicitly rather than derive it.

### 3.2 Sable

No blocks, items, block entities, entities or menus.

| registry | entries | source |
|---|---|---|
| `sable:force_groups` | 7: `gravity, drag, levitation, balloon_lift, propulsion, lift, magnetic_force` | `api/physics/force/ForceGroups.java:14-25` |
| `sable:physics_block_properties` | 8: `mass, inertia, volume, restitution, friction, fragile, floating_material, floating_scale` | `physics/config/block_properties/PhysicsBlockPropertyTypes.java:17-…` |
| attributes | 2: `player.sub_level_punch_strength`, `player.sub_level_punch_cooldown` (both `syncable`) | `index/SableAttributes.java:15-19` |

### 3.3 Simulated — 95 blocks, 30 block entities, 3 entity types, 1 menu, 6 components

Blocks (95), from `assets/simulated/blockstates/`:

- 18 handles: `iron_handle`, `copper_handle`, `<16 dyes>_handle`
- 16 portable engines: `<16 dyes>_portable_engine`
- 16 nameplates: `<16 dyes>_nameplate`
- 16 sails: `white_symmetric_sail`, `<15 non-white dyes>_symmetric_sail`
- 29 singles: `physics_assembler, swivel_bearing, swivel_bearing_link_block,
  merging_glue, rope_winch, rope_connector, directional_gearshift, torsion_spring,
  auger_shaft, auger_cog, laser_pointer, laser_sensor, velocity_sensor,
  altitude_sensor, gimbal_sensor, navigation_table, optical_sensor,
  docking_connector, paired_docking_connector, analog_transmission, steering_wheel,
  throttle_lever, linked_typewriter, directional_linked_receiver,
  modulating_linked_receiver, redstone_accumulator, redstone_inductor,
  redstone_magnet, spring`

  `absorber` is **not** in that list: both its block and block-entity
  registrations are commented out (`SimBlocks.java:713-731`,
  `SimBlockEntityTypes.java:236-242`). The classes exist; the entries do not, so
  they are out of scope for the port.

Block entities (30) — `index/SimBlockEntityTypes.java:54-278`:
`simple, torsion_spring, physics_assembler, rope_winch, rope_connector,
docking_connector, altitude_sensor, gimbal_sensor, handle, portable_engine,
swivel_bearing, steering_wheel, spring, swivel_bearing_link_block,
linked_typewriter, optical_sensor, laser_pointer, ir_sensor, velocity_sensor,
directional_linked_receiver, nameplate, modulating_linked_receiver,
redstone_accumulator, navigation_table, redstone_inductor, redstone_magnet,
throttle_lever, auger_shaft, merging_glue, directional_gearshift`

Entity types (3) — `index/SimEntityTypes.java:18,25,32`: `honey_glue,
launched_plunger, contraption_diagram`.

Menus (1) — `index/SimMenuTypes.java:16`: `linked_typewriter`.

Data components (6) — `index/SimDataComponents.java`: `rope_first_connection,
lodestone_compass_tracker, compass_placer, last_player_death_location, target,
bounciness`.

Recipe type (1) — `index/neoforge/SimNeoForgeRecipeTypes.java:24`:
`simulated:portable_engine_dyeing`, **serializer only**; the recipe type is
vanilla `RecipeType.CRAFTING` (`registerType = false`).

Custom registries: `simulated:navigation_target` (4: `compass, recovery_compass,
map, magnet` — `index/SimNavigationTargets.java:15-18`) and
`simulated:property_tooltip` (6: `mass, friction, restitution, fragile, airtight,
floating` — `client/BlockPropertiesTooltip.java:63-68`).

Items (86, derived): 76 block items (18 handles + 16 engines + 16 nameplates + 1
white sail + 25 other single blocks that call `.item()`, one of them with a
custom item class — `linked_typewriter`, `SimBlocks.java:631`) + 10 standalone
(`contraption_diagram, spring, rope_coupling, gyroscopic_mechanism,
incomplete_gyroscopic_mechanism, engine_assembly, incomplete_engine_assembly,
honey_glue, creative_physics_staff, plunger_launcher` —
`index/SimItems.java:32-117`; the full id list is `registries.simulated.items`
in the manifest). Blocks without an item: `swivel_bearing_link_block,
merging_glue, paired_docking_connector, spring` and the 15 dyed sails (they drop
the white sail item).

### 3.4 Aeronautics — 43 blocks, 9 block entities, 2 entity types, 2 components, 1 fluid

Blocks (43) — `index/AeroBlocks.java` plus the fluid block:
`white_envelope`, `<15 dyes>_envelope`; `<16 dyes>_envelope_encased_shaft`;
`adjustable_burner, steam_vent, propeller_bearing, gyroscopic_propeller_bearing,
smart_propeller, andesite_propeller, wooden_propeller, mounted_potato_cannon,
levitite, pearlescent_levitite`; `levitite_blend` (fluid block).

Block entities (9) — `index/AeroBlockEntityTypes.java:…`: `steam_vent,
adjustable_burner, propeller_bearing, gyroscopic_propeller_bearing,
envelope_encased_shaft, andesite_propeller, wooden_propeller, smart_propeller,
mounted_potato_cannon`.

Entity types (2) — `index/AeroEntityTypes.java`: `propeller_bearing_contraption,
gust`.

Data components (2) — `index/AeroDataComponents.java`: `levitating, converter`.

Custom registries: `aeronautics:lifting_gas_type` (2: `default, steam` —
`index/AeroLiftingGasTypes.java:16-17`) and
`aeronautics:levitite_crystal_propagation_context` (2: `standard, soul` —
`index/AeroLevititeBlendPropagationContexts.java:15-16`).

Fluid (1): `aeronautics:levitite_blend` with a bucket item —
`neoforge/.../index/AeroFluidsNeoForge.java:24-52`.

Items (46, derived): 42 block items (every block except the fluid block
`levitite_blend`; `levitite` and `pearlescent_levitite` take
`.item(BlockItem::new)` — `AeroBlocks.java:395,416`) + `aviators_goggles,
music_disc_cloud_skipper, end_stone_powder` + the `levitite_blend_bucket`
(full list: `registries.aeronautics.items`).

### 3.5 Offroad — 3 blocks, 3 block entities, 1 entity type, 1 component

Blocks: `borehead_bearing, rockcutting_wheel, wheel_mount` —
`index/OffroadBlocks.java:36,63,89`.

Block entities: `wheel_mount, borehead_bearing, rockcutting_wheel` —
`index/OffroadBlockEntityTypes.java`.

Entity type: `borehead_contraption_entity` — `index/OffroadEntityTypes.java:21`.
Also a **Create** registry entry: `create:contraption_type` →
`offroad:borehead_contraption` (`index/OffroadContraptionTypes.java:17`).

Data component: `tire` — `index/OffroadDataComponents.java:14`.
Items (7): `small_tire, tire, large_tire, monstrous_tire` (4) + 3 block items
(`wheel_mount` uses `RollerBlockItem` — `OffroadBlocks.java:98`; full list:
`registries.offroad.items`).

### 3.6 Totals

| | sable | simulated | aeronautics | offroad |
|---|---:|---:|---:|---:|
| blocks | 0 | 95 | 43 | 3 |
| items (derived) | 0 | 86 | 46 | 7 |
| block entities | 0 | 31 | 9 | 3 |
| entity types | 0 | 3 | 2 | 1 |
| menus | 0 | 1 | 0 | 0 |
| data components | 0 | 6 | 2 | 1 |
| recipe types | 0 | 1 | 0 | 0 |
| fluids | 0 | 0 | 1 | 0 |
| custom registries | 2 (15 entries) | 2 (10) | 2 (4) | 0 (+1 Create registry) |

**What the host numbers vs what must be declared.** The host numbers everything
registered through its own registry interfaces (items, blocks, block entities,
menus, components, fluids, entity types — `docs/neoforge-host.md`). The
declaration only carries what the host does not know: the two Sable registries,
the two Simulated ones, the two Aeronautics ones, the Create `contraption_type`
addition, the attributes, and the datapack entries. But the *order* of the
host-numbered entries must still mirror §3.1, because the client's ids are
positional.

---

## 4. Dependency order

### 4.1 Edges, with evidence

```
Create (6.0.11) ──► Sable ──► Simulated ──► Aeronautics
                                └──────────► Offroad
Veil ──► Sable, Simulated, Aeronautics, Offroad   (packet manager, registries, render bridge)
```

| edge | evidence |
|---|---|
| Sable → Create | `sable/neoforge/build.gradle:108` `implementation("com.simibubi.create:create-…")`. The coupling is **loader-side only**: `sable/common` has 0 files importing `com.simibubi.*`, `sable/neoforge` has 133 (contraption, nozzle, camera and redstone-contact integration under `neoforge/mixin/compatibility/create/**`). Those become plugin hooks against the existing Create port, not a Java port. |
| Simulated → Sable | `simulated/common` imports `dev.ryanhcode.sable.*` **456** times; top packages: `companion.math` 69, `api.physics` 66, `sublevel.SubLevel` 52, `api.sublevel` 37, `api.SubLevelHelper` 24, `sublevel.ServerSubLevel` 22, `sublevel.system` 19, `api.block` 19. Runtime: `aeronautics-bundled/build.gradle:115,124` requires `sable` |
| Aeronautics → Simulated | `aeronautics/common/build.gradle:28` `api(project(":simulated:common"))`; 63 imports of `dev.simulated_team.simulated.*` |
| Offroad → Simulated | `offroad/common/build.gradle:25` `api(project(":simulated:common"))`; 36 imports |
| Aeronautics/Offroad → Sable | 118 / 23 imports of `dev.ryanhcode.sable.*` |
| Aeronautics → Sable force groups | `ServerBalloon` uses `ForceGroups.BALLOON_LIFT` (`content/blocks/hot_air/balloon/ServerBalloon.java`), a group **Sable registers** — the balloon cannot lift until Sable's force-group registry and `ServerSubLevel` queued-force API exist |
| Simulated → Sable magnetic force | `content/blocks/redstone_magnet/MagnetPair.java` uses `ForceGroups.MAGNETIC_FORCE` |
| Sable → rapier native | `physics/impl/rapier/*` loads the `sable_rapier` native; `sable/neoforge/build.gradle:132` `jarJar(runtimeOnly(project(":sable_rapier")))` |

### 4.2 Order this forces

1. **Sable sub-level core** — `SubLevel`/`ServerSubLevel`, plot levels, storage,
   `SubLevelHelper`, `SubLevelContainer`. Nothing else can hold a moving
   structure without it.
2. **Sable physics** — `PhysicsPipeline` + the rapier implementation (or a
   replacement engine). Sub-levels are inert until the pipeline ticks them;
   `ServerSubLevel.tick` → `SubLevelPhysicsSystem` → `PhysicsPipeline`.
3. **Sable assembly/block API** — `api/block` (`BlockSubLevelLiftProvider`,
   propeller actors, collision callbacks), `api/physics/force` (queued forces),
   `api/schematic`. This is the surface Simulated and Aeronautics implement
   against.
4. **Simulated registry + core content** — assembler, glue, ropes, springs,
   bearings, sensors. Its blocks call the Sable API from step 3.
5. **Simulated world layer** — End Sea physics, world presets, navigation
   targets; depends on step 2 for force groups (`EndSeaPhysics` uses `DRAG` and
   `LEVITATION`).
6. **Aeronautics** — balloons (`ForceGroups.BALLOON_LIFT`), propellers
   (`BlockSubLevelLiftProvider` mixin on `PropellerBearingContraptionEntity`),
   levitite. Depends on steps 3–5.
7. **Offroad** — borehead bearing is a Create contraption that mines through
   Simulated/Sable sub-levels; depends on step 4.

Sable's **client** half (`mixin/`, `render/`, `sublevel/render/`) and all four
mods' client/ponder trees are not on this path; they only need to be read where a
mixin carries server behaviour.

**Cross-cutting cost that no slice owns by path — the Sable↔Create mixins.**
`sable/neoforge` mixes into Create's contraption, nozzle, camera, redstone-contact
and blaze-burner code (133 files import `com.simibubi.*`). Those sit in
`sable/neoforge/mixin/compatibility/create/**` and
`neoforge/mixinhelper/compatibility/create/**`, so they belong to **S3** and
**S7**'s owners by behaviour even though they live under a different module and
are not in either slice's path list above. Each of them is either (a) server
behaviour that becomes a hook into the existing Create port — contraption
assembly, nozzle thrust, redstone contact pairing — or (b) client-only rendering
that is dropped. Whoever owns S3 should classify them first, because S7's
acceptance (assemble a structure into a sub-level) is impossible without the
contraption half.

---

## 5. Slice plan

Fourteen slices. "Owns" is the set of files an agent may edit; everything else is
read-only reference. Java paths are given because that is where the behaviour is;
the plugin-side output paths are a proposal — adjust to the port crate once it
exists.

Shared rules for every slice:

- The channel manifest and §3 are the contract; no slice may add, rename or
  reorder a registry entry or a channel without changing the manifest first.
- Client/render/ponder code is out of scope unless the slice says otherwise.
- Acceptance is "the slice's behaviour is exercised", not "the file compiles":
  each slice names the test it must leave behind.

### 5.1 Ownership of the shared trees

Three trees do not belong to a single feature, so they are split by package
instead of by path. Anything not listed is owned by the slice named in the last
column of its group.

**`simulated/common/network/packets/**`** (46 files) follows the feature:

| packets | slice |
|---|---|
| `AssemblePacket`, `BlockEntityObservedPacket`, `physics_assembler/*`, `SteeringWheelPacket`, `ThrottleLeverSignalPacket`, `UpdatePlayerUsingHandlePacket`, `handle/*` | S7 |
| `PlaceMergingGluePacket`, `PlaceSpringPacket`, `RopeBreakPacket`, `RopeRidingPacket`, `rope/*`, `honey_glue/*` | S8 |
| `ConfigureAltitudeSensorPacket`, `ConfigureModulatingLinkedRecieverPacket`, `NameplateChangeNamePacket`, `linked_typewriter/*`, `lodestone_compass/*` | S9 |
| `physics_staff/*`, `PlungerLauncherShootPacket`, `contraption_diagram/*` | S10 |
| `end_sea/*` | S11 |
| `SimPacketManager.java` (the channel table itself) | S6 |

**Mixin packages.** Mixins carry behaviour, so they follow the feature, not the
`mixin/` directory:

| mixin package (under `sable/common/…/mixin/` unless stated) | slice |
|---|---|
| `entity/` (70), `punching/`, `block_placement/`, `assembly/`, `physics/`, `impact/`, `explosion/`, `voxel_shape_iteration/`, `plot/` (15), `block_properties/`, `fluids_on_sub_levels/`, `climbing_sub_levels/`, `interaction_distance/`, `sign_interaction/` | S1/S2/S3 |
| `udp/` (4) | S4 |
| `command/` (4), `tracking_points/`, `world_border/`, `respawn_point/`, `prevent_freezing/`, `player_freezing/` | S5 |
| `sublevel_render/` (9), `camera/`, `block_decal_render/`, `sky_light_shadow/`, `particle/`, `debug_render/`, `dynamic_directional_shading/`, `water_occlusion/`, `sublevel_sounds/`, `toast/`, `options/`, `stop_rain/`, `stop_lightning/`, `conduit/`, `sculk_vibrations/`, `enchanting_table/`, `loaded_chunk_debug/`, `chunk_container_replacement/`, `extension/`, `player_standup/` | client or niche — S5 classifies each file and drops the client ones |
| `sable/neoforge/…/mixin/compatibility/create/**` (151 files including the excluded compat mods) | S3 classifies; S7 implements the contraption/nozzle half |

| simulated mixin package (under `simulated/common/…/mixin/`) | slice |
|---|---|
| `create_assembly/`, `assembly_preventer/`, `auger_shaft/`, `extra_kinetics/` (9), `handle/`, `throttle_lever/`, `torsion_spring/`, `dynamic_stress/`, `hold_interaction/` | S7 |
| `rope/`, `honey_glue/`, `spring_item_bounce/` | S8 |
| `linked_typewriter/`, `nav_table_compat/`, `lodestone_compat/`, `conditional_display_target/`, `linked_controller_binding/`, `tooltip_flag/`, `search_alias/` | S9 |
| `physics_staff/`, `diving_boots/`, `extendo_grip/` | S10 |
| `world_presets/`, `sable_hooks/` | S11 |
| everything else (`accessor/` 13, `ponder/`, `new_ponder/`, `creative_tab_sections/`, `sounds/`, `quiet_use/`, `aabb/`, `flicker_tally_removal/`, `schematicannon_fix/`, `player/`) | S6 classifies: registration accessors and datagen belong to it, the rest is client or Create-side |

**`index/**`** is owned by S6 only. The content slices implement the classes the
index names; they never edit the index. This keeps the id order single-sourced.

### Wave 0 — foundations (can start immediately, in parallel)

**S1 · `sable-sublevel-core`** — 90 files
Owns: `sable/common/…/sublevel/{SubLevel,ServerSubLevel,ClientSubLevel}.java`,
`sublevel/plot/**`, `sublevel/storage/**`, `api/sublevel/**`, `api/math/**`,
`util/**`, `sable/…/index/**` (two attributes, tags, toasts).
Exposes: `SubLevel` (uuid, pose, bounds, plot), `ServerSubLevel` (tracking set,
queued force groups, mass tracker, heat map, floating-block controller),
`SubLevelContainer`/`SubLevelHelper` (create/remove/lookup, entity local-space
push/pop), storage save/load, plot chunk access.
Needs: nothing (it is the root).
Acceptance: create a sub-level in a test world, move its pose, save and reload it
with the same uuid and block contents; `SubLevelHelper.getContaining` returns it.

**S2 · `sable-physics`** — 69 Java files + 5,854 Rust lines
Owns: `sable/common/…/physics/**`, `api/physics/**`, `sable/sable_rapier/**`.
Exposes: `PhysicsPipeline` (`add/remove`, `physicsTick`, `applyImpulse`,
`teleport`, `addRope`, `addBox`, `addConstraint`, `handleBlockChange`),
`RigidBodyHandle`, `MassData`/`MassTracker`, `PhysicsBlockPropertyType` lookups,
`ForceGroup` queued-force application, collision callbacks.
Needs: S1's `SubLevel`/`ServerSubLevel` and `LevelChunkSection` access.
Acceptance: a box body falls under `ForceGroups.GRAVITY`, collides with a voxel
collider built from a chunk section, and a rope constraint holds two bodies
together; `physicsTick` advances deterministically for a fixed step.

**S3 · `sable-assembly-api`** — 64 files
Owns: `api/block/**`, `api/entity/**`, `api/schematic/**`, `api/event/**`,
`api/particle/**`, `mixinterface/**`, `mixinhelpers/**`.
Exposes: `BlockSubLevelLiftProvider`, `BlockEntitySubLevelPropellerActor`,
`BlockSubLevelCollisionShape`, `BlockEntitySubLevelActor`,
`BlockSubLevelAssemblyListener`, the ticket/observer interfaces, and the
`SableEventPlatform` events other mods subscribe to.
Needs: S1 + S2 types.
Acceptance: a test block implementing `BlockSubLevelLiftProvider` contributes a
lift vector that appears in the sub-level's queued force group; an assembly
listener fires on create/remove.

### Wave 1 — Sable surface

**S4 · `sable-network`** — 44 files
Owns: `sable/common/…/network/**`.
Exposes: the 17 TCP payloads (§2.2), the 6 UDP packet kinds, `SableUDPServer`
auth/keepalive, the tracking/snapshot send paths.
Needs: S1 (tracking), S2 (physics snapshots), S3 (gizmo/punch hooks).
Acceptance: two clients tracking one sub-level receive `start_tracking_sub_level`
→ `snapshot_packet` → `stop_tracking_sub_level`; a punch applies an impulse; a
client that never authenticates UDP keeps working over TCP.

**S5 · `sable-runtime`** — 38 files
Owns: `command/**`, `config/**`, `platform/**`, `sound/**`, `debug/**`,
`SableCommonEvents.java`, `Sable.java`, `SableServerConfig.java`.
Exposes: config specs (`sub_level_substeps_per_tick`,
`sub_level_velocity_retained_on_load`, …), the `/sable` commands, server tick
wiring, attribute registration.
Needs: S1–S4.
Acceptance: `/sable` subcommands act on real sub-levels; changing
`sub_level_substeps_per_tick` changes the number of pipeline steps per tick.

### Wave 1 — Simulated

**S6 · `simulated-registry`** — 127 files
Owns: `simulated/common/…/{index,registrate,data,service,api,events,config,multiloader,util}/**`,
`Simulated.java`, `SimulatedCommonEvents.java`.
Exposes: every id in §3.3 in registration order, the service interfaces
(`SimInventoryService`, `SimMenuService`, `SimEntityService`, …), config specs,
tags, the creative tab.
Needs: the ids from the manifest; nothing from content slices at compile time if
the index is written as data.
Acceptance: a registry dump from the plugin matches the manifest byte-for-byte
(names and order) for blocks, block entities, items, entity types, menus and
components.

**S7 · `simulated-kinetics`** — 68 files
Owns: `content/blocks/{physics_assembler,analog_transmission,auger_shaft,
directional_gearshift,torsion_spring,swivel_bearing,portable_engine,
steering_wheel,throttle_lever,handle,docking_connector}/**`.
Exposes: assembly/disassembly (`assemble`), the mechanical transmission blocks,
handle/steering/throttle control surfaces, docking pairing.
Needs: S1–S3 (sub-level create/remove, physics constraints), S6 (ids).
Acceptance: place an assembler, assemble a 3×3×3 structure into a sub-level, see
it move as one body, disassemble and get the blocks back in place.

**S8 · `simulated-ropes-glue-springs`** — 30 files
Owns: `content/blocks/{rope,spring,merging_glue}/**`,
`content/entities/honey_glue/**`, and the payload handlers for
`simulated:{place_spring,place_merging_glue,break_rope,ride_rope,rope_data,
rope_stopped,honey_glue_spawn,honey_glue_change_bounds,honey_glue_sync}`.
Exposes: rope strands as physics ropes (`addRope`), spring constraints, honey-glue
welding of blocks into one body.
Needs: S2 (rope/constraint handles), S7 (assembly of glued blocks).
Acceptance: a rope between two sub-levels holds under gravity; a spring pushes
them apart; honey glue merges two touching structures into one body.

**S9 · `simulated-redstone-sensors`** — 104 files
Owns: `content/blocks/{redstone,lasers,altitude_sensor,gimbal_sensor,
velocity_sensor,nav_table,nameplate,redstone_magnet,symmetric_sail,
void_anchor}/**`, `content/display_sources/**`, `content/navigation_targets/**`.
Exposes: the redstone link network (typewriter, receivers, accumulator, inductor),
optical/laser/altitude/gimbal/velocity sensors, nameplates,
redstone magnet (uses `ForceGroups.MAGNETIC_FORCE`), symmetric sail, nav table
targets.
Needs: S6 (components `target`, `bounciness`, `rope_first_connection`), S7.
Acceptance: a nameplate shows text; a linked receiver fires from a typewriter; the
magnet pulls a sub-level toward its pair.

**S10 · `simulated-items-entities-menus`** — 38 files
Owns: `content/{entities,items,physics_staff,item_attributes,components}/**`.
Exposes: the three entity types (spawn payloads, synced data), all items and their
behaviour, the physics staff (beam/locks/drag sessions), item attribute types, the
`target`/`bounciness` component codecs.
Needs: S6 (ids), S1–S3 (staff acts on sub-levels), S7.
Acceptance: spawn a honey-glue entity and a launched plunger; the staff grabs,
drags and locks a sub-level with the five staff payloads round-tripping.

**S11 · `simulated-world`** — 8 files
Owns: `content/{end_sea,worldgen}/**`, `SimulatedWorldPreset` subclasses and the
preset ids.
Exposes: End Sea physics (`ForceGroups.DRAG`/`LEVITATION`), the Airship-Ready and
End Sea world presets and their game rules, the ore/worldgen feature.
Needs: S2 (force groups), S5 (config/gamerules).
Acceptance: a world created with the End Sea preset loads with the expected game
rules and the sea's force field affects a sub-level.

### Wave 2 — Aeronautics and Offroad

**S12 · `aeronautics-hot-air`** — 33 files
Owns: `aeronautics/common/…/content/blocks/hot_air/**`, `content/items/**`,
`index/AeroLiftingGasTypes.java`, `index/AeroItems.java` (the non-levitite half).
Exposes: envelopes (16), burner, steam vent, lifting-gas types (`default`,
`steam`), the `levitating`/`converter` components, goggles/disc/powder items.
Needs: S3 (`BlockSubLevelLiftProvider`), S2 (`ForceGroups.BALLOON_LIFT`), S6.
Acceptance: a balloon with a burner rises; a steam vent fills it; the balloon's
lift appears under the `balloon_lift` force group.

**S13 · `aeronautics-propellers-levitite`** — 38 common + 22 neoforge files
Owns: `aeronautics/common/…/content/blocks/{propeller,levitite,
mounted_potato_cannon}/**`, `index/{AeroBlocks(levitite half),AeroBlockEntityTypes}`,
`aeronautics/neoforge/**` (fluid, bucket, services, particles).
Exposes: propeller bearing and gyroscopic bearing contraptions, andesite/wooden/
smart propellers, levitite and pearlescent levitite, the levitite-blend fluid,
`aeronautics:levitite_blend_crystallize`.
Needs: S3 (propeller actor), S7 (bearing as a contraption), S12 (gas).
Acceptance: a propeller bearing spins a contraption and produces thrust; levitite
blend crystallises via the serverbound payload.

**S14 · `offroad`** — 61 common + 9 neoforge files
Owns: `offroad/**`.
Exposes: borehead bearing contraption (multi-block mining), wheel mount,
rock-cutting wheel, tires and the `tire` component, `offroad:borehead_sync_blocks`.
Needs: S7 (contraption assembly), S3 (contraption actors), Create's contraption
type registry.
Acceptance: a borehead bearing mines the blocks in front of its contraption and
syncs the broken set to clients.

### Wave summary

| wave | slices | why |
|---|---|---|
| 0 | S1, S2, S3 | sub-level data model → physics → the API other mods implement |
| 1 | S4, S5, S6, S7, S8, S9, S10, S11 | Sable surface; Simulated registry then content (S6 first, then S7; S8–S10 parallel after S7; S11 anywhere after S2) |
| 2 | S12, S13, S14 | Aeronautics and Offroad need S3 + Simulated's assembly (S7) |

Each slice's agent reads only: this document's section for its slice, the Java
files it owns, and the contract classes named under "Needs". The manifest supplies
every id, version and channel; nothing else needs the 1,400 files.

---

## 6. What is not implemented, and what this document does not claim

- **Declaring the 56 channels only removes the handshake refusal.** It does not
  make the mods work: no sub-level exists, no physics runs, no block behaves.
  Connecting is the start of the work, not a result.
- **Registry declarations are names and order, not behaviour.** A client that
  connects will then request block states the server does not tick, menus it does
  not open, and entities it does not spawn.
- **The physics engine is the hard dependency.** `sable_rapier` is 5,854 lines of
  Rust plus 14 JNI binding classes; the plugin needs an equivalent (rapier via
  `rapier3d`/`mrapier`, or a different solver) with voxel colliders, ropes and the
  four constraint kinds. Nothing in the plugin API supplies one.
- **This inventory is static.** No client was run, no server was started, and no
  claim here is a measurement of behaviour. The counts are reproducible with
  Appendix A.

---

## Appendix A — reproducing the numbers

```sh
J=~/Documents/development/languages/java
# module sizes
for d in sable/common sable/neoforge sable/fabric sable/sable_rapier \
         Simulated-Project/{simulated,aeronautics,offroad}/{common,neoforge}; do
  printf '%-40s %s\n' "$d" "$(find "$J/$d/src/main/java" -name '*.java' | wc -l)"
done
# channels
grep -rhoE 'new (CustomPacketPayload\.)?Type<>\((Sable|Simulated|Aeronautics|Offroad)\.[a-zA-Z]+\("[^"]+"\)' \
  "$J/sable" "$J/Simulated-Project" --include=*.java | wc -l      # 56
# block ids
ls "$J"/Simulated-Project/*/common/src/generated/resources/assets/*/blockstates/*.json
# block entities / entities / menus / components
grep -rhoE '(blockEntity|entity|menu)\("[a-z_0-9]+"' \
  "$J"/Simulated-Project/*/common/src/main/java --include=*.java | sort | uniq -c
# dependency imports
grep -rhoE '^import (static )?dev\.ryanhcode\.sable\.[A-Za-z0-9_.]+' \
  "$J"/Simulated-Project/simulated/common/src/main/java | wc -l   # 456
```

## Appendix B — registration order sites

`SimBlocks.java` (in file order; `<dyes>` = `DyeColor.values()` order):

```
100 physics_assembler      119 swivel_bearing       142 swivel_bearing_link_block
154 merging_glue           165 rope_winch            187 rope_connector
204 iron_handle            221 copper_handle         231 <16>_handle
243 directional_gearshift  264 torsion_spring        284 auger_shaft
309 auger_cog              327 <16>_portable_engine  378 laser_pointer
397 laser_sensor           418 velocity_sensor       438 altitude_sensor
462 gimbal_sensor          486 navigation_table      506 optical_sensor
527 docking_connector      545 paired_docking_connector
559 analog_transmission    582 steering_wheel        606 throttle_lever
623 linked_typewriter      636 directional_linked_receiver
655 modulating_linked_receiver  674 redstone_accumulator
694 redstone_inductor      733 redstone_magnet
751 white_symmetric_sail   779 <15>_symmetric_sail   801 <16>_nameplate
844 spring
```

`AeroBlocks.java`: 74 `white_envelope`; 112 `<15>_envelope`; 148
`<16>_envelope_encased_shaft`; 186 `adjustable_burner`; 218 `steam_vent`;
243 `propeller_bearing`; 268 `gyroscopic_propeller_bearing`; 294
`smart_propeller`; 322 `andesite_propeller`; 350 `wooden_propeller`; 368
`mounted_potato_cannon`; 382 `levitite`; 403 `pearlescent_levitite`.
`levitite_blend` is registered by `AeroFluidsNeoForge` (see §3.1).

`OffroadBlocks.java`: 36 `borehead_bearing`; 63 `rockcutting_wheel`; 89
`wheel_mount`.

`SimBlockEntityTypes.java` order: `simple, torsion_spring, physics_assembler,
rope_winch, rope_connector, docking_connector, altitude_sensor, gimbal_sensor,
handle, portable_engine, swivel_bearing, steering_wheel, spring,
swivel_bearing_link_block, linked_typewriter, optical_sensor, laser_pointer,
ir_sensor, velocity_sensor, directional_linked_receiver, nameplate,
modulating_linked_receiver, redstone_accumulator, navigation_table,
redstone_inductor, redstone_magnet, throttle_lever, auger_shaft,
merging_glue, directional_gearshift`.

## Appendix C — files that answer "what does X do"

| question | file |
|---|---|
| how a channel is registered and versioned | `Veil/…/NeoForgeVeilPacketManager.java:42-56` |
| the mod init order | `Simulated.java:37-57`, `Aeronautics.java:37-48`, `Offroad.java:37-45`, `Sable.java:39-42` |
| sub-level lifecycle | `sable/…/sublevel/SubLevel.java:83-229`, `ServerSubLevel.java:139-562` |
| physics contract | `sable/…/api/physics/PhysicsPipeline.java:37-251` |
| lift/propeller API | `sable/…/api/block/BlockSubLevelLiftProvider.java`, `api/block/propeller/` |
| balloon lift | `aeronautics/…/content/blocks/hot_air/balloon/ServerBalloon.java` |
| rope/spring/glue physics | `simulated/…/content/blocks/rope/**`, `spring/**`, `merging_glue/**` |
| 26.3 port hazards already solved | `sable/PORTING-26.3.md`, `Simulated-Project/PORTING-26.3.md` |
| host declaration API | `docs/neoforge-host.md`, `docs/neoforge-protocol.md` |
