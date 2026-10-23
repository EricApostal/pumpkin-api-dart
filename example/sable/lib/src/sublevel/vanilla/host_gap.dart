// The host features Sable's vanilla patches need and Pumpkin does not have.
//
// Each entry is a *requirement*, not an existing hook: [HostGap.exposure] says
// what the host would have to add (a WIT function, an event, or a behaviour
// change), and [HostGap.workaround] says what the port does until then. Nothing
// here is invented as available; the ids are the ones `mixin_inventory.dart`
// refers to.
//
// Pure: no host imports.

/// How bad it is to be missing.
enum HostGapPriority {
  /// The airship is not playable (invisible or non-solid to players).
  critical,

  /// A vanilla behaviour is visibly wrong on a ship.
  major,

  /// Cosmetic, an edge case, or already worked around.
  minor,
}

/// One host feature the port needs.
final class HostGap {
  /// Stable id, used by [MixinInventory] entries.
  final String id;

  /// The behaviour that is missing, in one line.
  final String need;

  /// What the host would have to expose. Written as a requirement: the Pumpkin
  /// API has no such call today unless the text says otherwise.
  final String exposure;

  final HostGapPriority priority;

  /// What the port does in the meantime, or `null` when nothing can be done.
  final String? workaround;

  const HostGap({
    required this.id,
    required this.need,
    required this.exposure,
    required this.priority,
    this.workaround,
  });

  @override
  String toString() => 'HostGap($id, ${priority.name})';
}

/// The gap list.
abstract final class HostGaps {
  static const HostGap entityMovementSweep = HostGap(
    id: 'entity-movement-sweep',
    need:
        'Host entities (players, mobs, items, arrows) must move against sub-level geometry, '
        'not only against world blocks.',
    exposure:
        'A movement resolver next to `entity-collision.wit`: '
        '`resolve-movement(entity-id, motion) -> {motion, horizontal-collision, vertical-collision, '
        'on-ground, minor-horizontal-collision, tracking-sub-level}`, where the boxes come from '
        '`set-entity-collision-boxes`. It must support step-up (`maxUpStep`), the per-axis slide '
        'vanilla does, and the restitution/bounce flags Sable computes per block.',
    priority: HostGapPriority.critical,
    workaround:
        '`entity-collision` boxes already stop an entity and push players out, so a ship is '
        'solid; sliding along a tilted deck, step-up and the collision flags are missing. '
        '`SubLevelStanding` ports the edge/stand-up queries for the plugin side.',
  );

  static const HostGap entityBlockPos = HostGap(
    id: 'entity-block-pos',
    need: 'Vanilla code that asks "which block is this entity in/on" must resolve ship blocks.',
    exposure:
        'An entity query `block-below(entity-id, max-distance) -> block-pos` and '
        '`block-at-entity(entity-id) -> block-pos` that returns the *plot* position when the entity '
        'stands on a sub-level, plus `block-state-at(pos)` that reads plot chunks. Today '
        '`get-block` only reads the world.',
    priority: HostGapPriority.major,
    workaround:
        '`SubLevelEntityRules.localBlockPos` computes the plot position; the host still '
        'reads the wrong block, so ladders, falling blocks, mob eating and pet teleports are inert.',
  );

  static const HostGap entityWirePosition = HostGap(
    id: 'entity-wire-position',
    need:
        'Entities on a ship must be sent to clients relative to the ship, and the Sable client '
        'expects that.',
    exposure:
        'Either (a) `entity.wit`: `set-tracking-position-mode(entity-id, mode)` with a '
        '`sub-level-relative` mode, or (b) a raw-packet hook that lets the plugin rewrite the '
        'position triple of `ClientboundMoveEntityPacket`/`TeleportEntityPacket` before it is sent.',
    priority: HostGapPriority.critical,
    workaround:
        'The plugin sends the ship pose over its own channel (W4), so the Sable client '
        'derives local positions; vanilla clients see world positions only.',
  );

  static const HostGap playerMovePacket = HostGap(
    id: 'player-move-packet',
    need:
        'A player standing on a ship sends ship-relative movement; the server must accept it and '
        'not reject it as "moved too quickly".',
    exposure:
        '`packet-received-event` is cancellable but cannot modify the packet. The host would '
        'have to expose the decoded `ServerboundMovePlayerPacket` fields as mutable data, plus a '
        'flag to disable the moved-too-quickly / moved-wrongly checks per player.',
    priority: HostGapPriority.critical,
    workaround:
        '`player-move-event` exists and is cancellable, but a cancelled move leaves the '
        'player where they were. No workaround: a ship that moves under a player desynchronises.',
  );

  static const HostGap entityTrackingFollow = HostGap(
    id: 'entity-tracking-follow',
    need: 'An entity standing on a ship must be carried by it between physics substeps.',
    exposure:
        'A per-tick entity position hook: `set-entity-anchor(entity-id, sub-level-id, local-pos)` '
        'that the host re-applies after physics, or a `post-physics` callback where the plugin may '
        'teleport entities without tripping the moved-too-quickly check.',
    priority: HostGapPriority.critical,
    workaround:
        'The plugin can teleport each tracked entity after `pipeline.postPhysicsTicks()`; '
        'the host then also runs its own movement check on the resulting delta.',
  );

  static const HostGap entityRiding = HostGap(
    id: 'entity-riding',
    need:
        'Riding a vehicle that is inside a sub-level: the rider, the dismount position, the jump '
        'and the vehicle position all live in the ship frame.',
    exposure:
        '`entity.wit`: `get-vehicle(entity-id)`, `dismount(entity-id, world-pos)` and a '
        'passenger position mode (`set-passenger-seat` exists for plugin entities only). The host '
        'must also apply the ship transform to a *host* vehicle\'s passengers.',
    priority: HostGapPriority.major,
    workaround:
        '`SubLevelEntityRules.kickRidingEntity` computes the position; the plugin can '
        'teleport the rider, but the host re-seats it on its own schedule.',
  );

  static const HostGap entityTickRate = HostGap(
    id: 'entity-tick-rate',
    need: 'Entities in plot chunks must tick when a player is near the *ship*, not near the plot.',
    exposure:
        '`entity-ticking.wit` exists for plugin entity types only. The host would have to '
        'expose the entity-ticking-range decision for vanilla entities, or let a plugin pin an '
        'entity id to a chunk position.',
    priority: HostGapPriority.major,
    workaround:
        'The plugin can call `tickEntities` for plugin entity types; vanilla entities in a '
        'plot are frozen when the plot chunk leaves the ticking range.',
  );

  static const HostGap entityUnloading = HostGap(
    id: 'entity-unloading',
    need: 'Entities inside plot chunks must not be unloaded when the plot chunk unloads.',
    exposure:
        'A `chunk-unload-event` that can be cancelled for a specific chunk, or '
        '`chunk-tickets.wit` gaining "keep entities" semantics (it currently keeps chunks, not '
        'entity sections).',
    priority: HostGapPriority.major,
    workaround: 'The plugin re-spawns entities from the tracking points on load (W2 storage).',
  );

  static const HostGap entityQuery = HostGap(
    id: 'entity-query',
    need:
        '`getEntities(level, box)` must also return entities that are inside a sub-level '
        'overlapping the box.',
    exposure:
        '`world.wit`: `get-entities-in-box(box, include-sub-levels: bool)` or an equivalent '
        'query that projects the box into every overlapping plot.',
    priority: HostGapPriority.major,
    workaround:
        '`entitiesNear`/`entitiesIn` only see world positions; the plugin maintains its '
        'own per-sub-level entity list from tracking.',
  );

  static const HostGap explosionRay = HostGap(
    id: 'explosion-ray',
    need: 'An explosion must destroy blocks inside a sub-level and push its body.',
    exposure:
        'A pre-explosion hook giving the plugin the blast (centre, power, source) and a way '
        'to add blocks to the destroyed set, or a `create-explosion` that walks plugin-supplied '
        'geometry. `create-explosion` exists but only affects world blocks.',
    priority: HostGapPriority.major,
    workaround:
        '`SubLevelExplosions.walk` is the ported algorithm; the plugin can call it from '
        '`entity-explode-event` with a ray it casts itself, but vanilla\'s own ray is not visible.',
  );

  static const HostGap fluidOcclusion = HostGap(
    id: 'fluid-occlusion',
    need: 'Water carried by a ship must make entities swim, and the eye-in-fluid checks must see it.',
    exposure:
        '`world.wit`: `get-fluid-state(pos)` that reads plot chunks, and a per-entity '
        '"touching fluid" result the host recomputes with sub-levels included.',
    priority: HostGapPriority.major,
    workaround:
        'The W2 `WaterOcclusionContainer` holds the data; `entity-toggle-swim-event` lets '
        'the plugin force the swim pose, but not the fluid drag.',
  );

  static const HostGap blockPlacementFrame = HostGap(
    id: 'block-placement-frame',
    need:
        'Placing a block against a rotated ship needs the clicked face and the player\'s facing '
        'resolved in the ship frame.',
    exposure:
        '`block-placement.wit` (placement rules) would have to take the sub-level pose, or '
        '`player-interact-event` would have to carry the local clicked position and the local '
        'facing/rotation.',
    priority: HostGapPriority.major,
    workaround:
        'The plugin can compute the local position from the ship pose and place the block '
        'itself in `player-interact-event`; the face choice stays wrong on tilted ships.',
  );

  static const HostGap clipRaycast = HostGap(
    id: 'clip-raycast',
    need: 'Block and entity raycasts (mining, targeting, projectiles) must continue into sub-levels.',
    exposure:
        '`world.wit`: `ray-trace(start, end, include-sub-levels: bool)` returning the hit '
        'position *and* the sub-level id and local position, plus an entity raycast with the same '
        'option.',
    priority: HostGapPriority.critical,
    workaround:
        '`ray-trace` exists for world blocks; the plugin can ray-trace the plot chunks '
        'itself and pick the nearer hit, but the host\'s own targeting stays world-only.',
  );

  static const HostGap interactionRange = HostGap(
    id: 'interaction-range',
    need:
        'Every "is X near Y" check (interaction range, particles, packet broadcast, conduits, '
        'break decals) must compare world positions after projecting out of sub-levels.',
    exposure:
        'A single host primitive `project-position(world, pos) -> pos` plus the host using it '
        'in its distance checks; alternatively expose the checks (particle send, packet broadcast) '
        'as cancellable events with the distance.',
    priority: HostGapPriority.major,
    workaround:
        '`SubLevelEntityRules.distanceSquaredWithSubLevels` is ported, so the plugin can '
        'decide for its own sends; the host\'s internal checks are unaffected.',
  );

  static const HostGap pathfinding = HostGap(
    id: 'pathfinding',
    need: 'Mobs must pathfind on a ship, in the ship frame.',
    exposure:
        '`ai.wit`: pathfinding queries that accept a sub-level id, or a way to run the vanilla '
        'navigator in a local coordinate space.',
    priority: HostGapPriority.minor,
    workaround:
        'Mobs on a ship stand still (the goal positions are world positions).',
  );

  static const HostGap canSeeSky = HostGap(
    id: 'can-see-sky',
    need: 'Mobs on a ship are not in daylight just because the plot is open to the sky.',
    exposure: '`world.wit`: `can-see-sky(pos, include-sub-levels: bool)`.',
    priority: HostGapPriority.minor,
    workaround: 'None; mobs burn on a deck at night in the plot.',
  );

  static const HostGap biomeTemperature = HostGap(
    id: 'biome-temperature',
    need: 'Water on a ship does not freeze because the plot biome is cold.',
    exposure:
        '`world.wit`: `biome-at(pos)` (already a W2 host gap) plus a hook to veto '
        '`shouldFreeze`.',
    priority: HostGapPriority.minor,
    workaround:
        'The plugin can watch `block-from-to-event` (water → ice) and undo it.',
  );

  static const HostGap insideBlockEffects = HostGap(
    id: 'inside-block-effects',
    need:
        'Standing inside a ship block (fire, lava, portal, cactus, powder snow) must apply its '
        'effects.',
    exposure:
        '`entity-enter-block-event` exists but fires for world blocks. The host would have to '
        'run the inside-block pass over plot blocks, or let the plugin report the blocks an entity '
        'overlaps.',
    priority: HostGapPriority.major,
    workaround:
        'The plugin can apply damage/effects itself from `entity-enter-block-event` when it '
        'computes the plot block; the host will not.',
  );

  static const HostGap sculkVibration = HostGap(
    id: 'sculk-vibration',
    need: 'Game events on a ship (steps, block breaks) must reach sculk sensors on the ship.',
    exposure:
        '`generic-game-event` exists; the host would have to project the event position into '
        'the plot and dispatch it there too.',
    priority: HostGapPriority.minor,
    workaround: 'Sensors on a ship do not hear anything.',
  );

  static const HostGap signBlockEntity = HostGap(
    id: 'sign-block-entity',
    need:
        'Clicking a sign on a ship must use the ship-relative click position.',
    exposure:
        '`block-entity.wit`: sign edit/click data with a local position, or a '
        '`player-open-sign-event` that carries the plot position.',
    priority: HostGapPriority.minor,
    workaround: 'The plugin can open the sign through its own menu (W4 menus).',
  );

  static const HostGap entityNbt = HostGap(
    id: 'entity-nbt',
    need: 'Sable stores a tracking point id on entities so a ship can find its passengers on load.',
    exposure:
        '`entity.wit`: `get-entity-nbt`/`set-entity-nbt` for a vanilla entity, or a '
        'per-entity persistent data map.',
    priority: HostGapPriority.major,
    workaround: 'The plugin keeps the mapping in its own saved data, keyed by entity UUID.',
  );

  static const HostGap udpChannel = HostGap(
    id: 'udp-channel',
    need: 'The snapshot protocol uses UDP for low latency.',
    exposure:
        '`server.wit`: a raw UDP socket bound next to the TCP listener '
        '(`bind-udp(port)`, `send-datagram(player, bytes)`, `on-datagram`).',
    priority: HostGapPriority.minor,
    workaround:
        'TCP is the supported path: `PumpkinTrackingSender` sends every payload of the sync '
        '(`start_tracking_sub_level`, the plot chunks, `finalize_sub_level`, the snapshots) over '
        'the payload channel, which is Java\'s own fallback (`SubLevelTrackingSystem.java:383-404` '
        'sends the identical payloads when UDP is not up). `sable:udp_activation` is never sent — '
        'activating a channel whose server socket does not exist would make the client `AUTH` into '
        'the void. Only the latency of movement suffers; the bytes do not.',
  );

  static const HostGap packetExtension = HostGap(
    id: 'packet-extension',
    need: 'Sable appends one boolean to three vanilla entity packets ("actually in a sub-level").',
    exposure:
        'A raw clientbound packet hook that can append bytes to a vanilla packet, or the '
        'host implementing the flag itself.',
    priority: HostGapPriority.major,
    workaround:
        'The Sable client can infer it from the ship pose it already receives; a vanilla '
        'client is unaffected either way.',
  );

  static const HostGap leashPhysics = HostGap(
    id: 'leash-physics',
    need: 'A leashed entity on a ship is pulled in the ship frame.',
    exposure:
        'Leash integration is host-internal; the host would need to accept a per-entity '
        'position mode (same as `entity-tracking-follow`).',
    priority: HostGapPriority.minor,
    workaround: 'Leashed mobs lag behind a moving ship.',
  );

  static const HostGap projectileState = HostGap(
    id: 'projectile-state',
    need: 'A trident that starts returning must be kicked out of the ship.',
    exposure:
        '`projectile-launch-event`/`projectile-hit-event` exist; a `projectile-return-event` '
        'or a "no physics" flag change event is missing.',
    priority: HostGapPriority.minor,
    workaround: 'The plugin kicks any projectile that is inside a plot and no longer moving.',
  );

  static const HostGap commandFork = HostGap(
    id: 'command-fork',
    need:
        '`execute in_sub_level <ship> run ...` / `out_sub_level` fork the command source into the '
        'ship frame.',
    exposure:
        'The command API cannot extend vanilla `execute`. The host would have to expose a '
        'source-fork hook (`execute` subcommand registration with a position transform).',
    priority: HostGapPriority.minor,
    workaround:
        '`/sable` provides equivalent subcommands (W3 `SubLevelSelector`).',
  );

  static const HostGap commandDataSource = HostGap(
    id: 'command-data-source',
    need: '`execute store ...` and `/data` on a sub-level.',
    exposure:
        'The command API would have to expose a data-source registry (Java `ArgProvider`), '
        'which no host hook covers.',
    priority: HostGapPriority.minor,
    workaround: '`/sable` reads the same data through its own subcommands.',
  );

  static const HostGap blockEntityApi = HostGap(
    id: 'block-entity-api',
    need: 'Assembly has to clear a vanilla block entity (a furnace\'s contents and recipe tally).',
    exposure:
        '`block-entity.wit`: `clear-contents(pos)` and `get-block-entity-nbt`/'
        '`set-block-entity-nbt` already exist for some types; the clear is missing.',
    priority: HostGapPriority.minor,
    workaround:
        'The plugin empties the inventory through `container-block-entity.get-inventory`; '
        'the recipe tally stays.',
  );

  static const HostGap chunkSource = HostGap(
    id: 'chunk-source',
    need:
        'Plot chunks are real chunks at the plot yard and must be served from the sub-level '
        'container, not generated or saved as world terrain.',
    exposure:
        '`chunk-tickets.wit` keeps them loaded and `chunk-streaming.wit` sends them, which '
        'covers the two hard parts. Still missing: creating a chunk at an arbitrary position '
        '(`create-empty-chunk`), suppressing mob spawning in plot chunks, and telling the chunk '
        'source that a plot chunk must not be saved as world data.',
    priority: HostGapPriority.critical,
    workaround:
        'W2 `PlotChunkHost` treats unloaded plot chunks as empty and rebuilds them from the '
        'sub-level storage. For a client to see a sub-level at all, the port asks the *server* to '
        'keep the yard chunk loaded (`PumpkinSubLevelHost.requestYardChunkKeep` -> '
        '`execute in <dim> run forceload add <block>`, which marks the chunk and returns at once) '
        'and the sender queues the chunk send until the world has it, then `mirrorPlotChunk` '
        'writes the plot\'s blocks (measured 0 ms) and `chunk-streaming.send-chunk-at` ships them. '
        'The plugin\'s own `force-load-chunk` cannot be used for this: it waits for generation and '
        'answers at its 60 s `LOAD_TIMEOUT`, and that wait blocks the server\'s tick loop even '
        'when the call is not awaited (the guest tick cannot return while the host subtask is '
        'pending) — measured as a 60 s freeze and a client timing out. Live with the forceload '
        'path: ask -> chunk loaded -> chunk sent in ~3 s, client intact. The terrain the host '
        'generated in that chunk stays there (it is not rendered: the client meshes only the '
        'plot\'s bounding box) and the yard chunk is saved with the world — both disappear with a '
        'plugin-owned empty chunk.',
  );

  static const HostGap plotLighting = HostGap(
    id: 'plot-lighting',
    need: 'Plot chunks need their own light data for rendering and for mob spawn rules.',
    exposure:
        '`world.wit`: `get-block-light`/`set-block-light` exist but read the world light '
        'engine. The host would have to let a plugin own the light of a chunk range.',
    priority: HostGapPriority.major,
    workaround:
        'Sable computes its own light for the ship on the client; server-side light stays '
        'whatever the plot yard has.',
  );

  static const HostGap chunkSerialization = HostGap(
    id: 'chunk-serialization',
    need: 'A plot chunk must be serialized into the sub-level file and restored from it.',
    exposure:
        '`world.wit`: `serialize-chunk(x, z) -> bytes` and `deserialize-chunk(x, z, bytes)` '
        'for a chunk the plugin owns, including block entities, ticks and light.',
    priority: HostGapPriority.critical,
    workaround:
        'W2 stores sub-levels block-by-block through its own region format; block entities '
        'and scheduled ticks are lost on save.',
  );

  static const HostGap portalFrame = HostGap(
    id: 'portal-frame',
    need: 'Entering a portal from inside a ship (and the destination position) must be projected.',
    exposure:
        '`entity-portal-event`/`entity-portal-enter-event` are cancellable but carry only the '
        'portal block. The host would have to expose the computed destination position.',
    priority: HostGapPriority.minor,
    workaround:
        'The plugin can cancel the portal event inside a ship and teleport the player '
        'itself with `player.teleport`.',
  );

  static const HostGap sleepPosition = HostGap(
    id: 'sleep-position',
    need: 'Waking up on a ship puts the player on the deck.',
    exposure:
        '`player-bed-leave-event` carries the bed position; the host would have to let the '
        'plugin set the wake-up position.',
    priority: HostGapPriority.minor,
    workaround:
        '`PlayerProjection.standUpPosition` computes it; the plugin can teleport the player '
        'on bed leave.',
  );

  static const HostGap worldBorder = HostGap(
    id: 'world-border',
    need:
        'The world border must not treat a ship inside its bounds as outside, nor the plot yard '
        'as outside the world.',
    exposure:
        '`world.wit` has border get/set but no per-entity "inside the border" query with '
        'sub-level projection.',
    priority: HostGapPriority.minor,
    workaround: 'The plot yard is placed inside the border by configuration.',
  );

  /// Every gap, in priority order.
  static const List<HostGap> all = [
    entityMovementSweep,
    entityWirePosition,
    playerMovePacket,
    entityTrackingFollow,
    clipRaycast,
    chunkSource,
    chunkSerialization,
    entityBlockPos,
    entityRiding,
    entityTickRate,
    entityUnloading,
    entityQuery,
    explosionRay,
    fluidOcclusion,
    blockPlacementFrame,
    interactionRange,
    insideBlockEffects,
    entityNbt,
    packetExtension,
    plotLighting,
    pathfinding,
    canSeeSky,
    biomeTemperature,
    sculkVibration,
    signBlockEntity,
    udpChannel,
    leashPhysics,
    projectileState,
    commandFork,
    commandDataSource,
    blockEntityApi,
    portalFrame,
    sleepPosition,
    worldBorder,
  ];

  /// The gap with [id], or `null`.
  static HostGap? byId(String id) {
    for (final gap in all) {
      if (gap.id == id) return gap;
    }
    return null;
  }

  /// The gaps at [priority].
  static List<HostGap> atPriority(HostGapPriority priority) =>
      all.where((gap) => gap.priority == priority).toList();
}
