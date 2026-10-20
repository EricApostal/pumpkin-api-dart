// The inventory of Sable's vanilla patches, and what each one became in the
// port.
//
// Java expresses these as 227 common mixin files (145 server-side, 82 client),
// 33 mix-interfaces and 16 mixin helpers, plus 207 NeoForge files of which 156
// are the Create compatibility layer (workstream W6) and 19 are Flywheel
// rendering. This file records the server-side ones; the client ones are listed
// by path only, because the plugin is server-only.
//
// Every server-side patch is in exactly one bucket:
//
// * [MixinBucket.pluginHook]  -- an existing host hook (an event or a
//   capability) plus plugin-side logic is enough. [MixinEntry.hook] names it and
//   the ported code lives under `lib/src/sublevel/vanilla/`.
// * [MixinBucket.hostFeature] -- the host has no hook for it. [MixinEntry.gap]
//   names the entry in `host_gap.dart` that says what the host would have to
//   expose.
// * [MixinBucket.notApplicable] -- client-only, a debug/accessor helper, a pure
//   performance trick, or a mechanism that only exists because Java has to patch
//   bytecode (Dart has the source).
//
// Pure: no host imports.

/// Which bucket a Java patch falls into.
enum MixinBucket {
  /// Reproducible with an existing host hook.
  pluginHook,

  /// Needs a host feature that does not exist yet.
  hostFeature,

  /// Not applicable to the Dart port.
  notApplicable,
}

/// One Java patch and its port decision.
final class MixinEntry {
  /// Path under `common/src/main/java/dev/ryanhcode/sable/` (or the NeoForge
  /// source root), so the table can be checked against the Java tree.
  final String path;

  /// The patched class.
  final String target;

  final MixinBucket bucket;

  /// The host hook, for [MixinBucket.pluginHook].
  final String? hook;

  /// The host gap id, for [MixinBucket.hostFeature].
  final String? gap;

  /// What the port does, in one line.
  final String note;

  const MixinEntry(
    this.path,
    this.target,
    this.bucket, {
    this.hook,
    this.gap,
    this.note = '',
  });

  @override
  String toString() =>
      '$path -> $target [${bucket.name}${hook != null ? ' $hook' : ''}'
      '${gap != null ? ' gap:$gap' : ''}]';
}

/// The inventory itself.
abstract final class MixinInventory {
  /// `common/.../mixin/**`, server-side (145 files).
  static const List<MixinEntry> commonServerMixins = [
    // -- mixin plugin ------------------------------------------------------
    MixinEntry(
      'mixin/AbstractSableMixinPlugin.java',
      '(mixin config)',
      MixinBucket.notApplicable,
      note: 'Gates the Create/Flywheel compat patches on mod presence; W6 decides that at build time.',
    ),

    // -- assembly ----------------------------------------------------------
    MixinEntry(
      'mixin/assembly/AbstractFurnaceBlockEntityMixin.java',
      'AbstractFurnaceBlockEntity',
      MixinBucket.hostFeature,
      gap: 'block-entity-api',
      note: 'Clears the recipe tally when a furnace is assembled; the host has no block-entity internals.',
    ),

    // -- block decal render ------------------------------------------------
    MixinEntry(
      'mixin/block_decal_render/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Break decals are sent within 1024 blocks; plot coordinates defeat the distance check.',
    ),

    // -- block placement ---------------------------------------------------
    MixinEntry(
      'mixin/block_placement/BlockPlaceContextMixin.java',
      'BlockPlaceContext',
      MixinBucket.hostFeature,
      gap: 'block-placement-frame',
      note: 'Placing against a rotated ship needs the placement direction in the ship frame.',
    ),
    MixinEntry(
      'mixin/block_placement/EntityGetterMixin.java',
      'EntityGetter',
      MixinBucket.hostFeature,
      gap: 'entity-query',
      note:
          'Entity queries by box must also return entities inside a sub-level.',
    ),
    MixinEntry(
      'mixin/block_placement/UseOnContextMixin.java',
      'UseOnContext',
      MixinBucket.hostFeature,
      gap: 'block-placement-frame',
      note: 'Horizontal direction and rotation of a use action on a ship.',
    ),

    // -- block properties --------------------------------------------------
    MixinEntry(
      'mixin/block_properties/BlockStateMixin.java',
      'BlockState',
      MixinBucket.notApplicable,
      note: 'Replaced by the plugin physics-property map (`PhysicsBlockProperties`); no host state needed.',
    ),

    // -- camera / clipping -------------------------------------------------
    MixinEntry(
      'mixin/camera/camera_rotation/EntityMixin.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Shadow-only accessor used by the client camera helper.',
    ),
    MixinEntry(
      'mixin/chunk_container_replacement/LevelChunkSectionMixin.java',
      'LevelChunkSection',
      MixinBucket.notApplicable,
      note: 'Empty placeholder for swapping the section container.',
    ),
    MixinEntry(
      'mixin/climbing_sub_levels/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'Ladders on a ship: `onClimbable` must see the ship block at the entity.',
    ),
    MixinEntry(
      'mixin/clip_overwrite/BlockGetterMixin.java',
      'BlockGetter',
      MixinBucket.hostFeature,
      gap: 'clip-raycast',
      note: 'Raycasts must continue into sub-levels.',
    ),
    MixinEntry(
      'mixin/clip_overwrite/ClipContextMixin.java',
      'ClipContext',
      MixinBucket.notApplicable,
      note: 'Duck state on the clip context; the port passes the ignored sub-level explicitly.',
    ),
    MixinEntry(
      'mixin/clip_overwrite/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'clip-raycast',
      note:
          '`Entity#pick` uses the interpolated eye position on a moving ship.',
    ),
    MixinEntry(
      'mixin/clip_overwrite/HitResultMixin.java',
      'HitResult',
      MixinBucket.hostFeature,
      gap: 'clip-raycast',
      note: 'A hit on a ship has to be reported back in the ship frame.',
    ),

    // -- commands ----------------------------------------------------------
    MixinEntry(
      'mixin/command/ArgumentTypeInfosMixin.java',
      'ArgumentTypeInfos',
      MixinBucket.pluginHook,
      hook: 'command-argument',
      note: '`sable:sub_level` and `sable:vec3_absolute` are plugin argument types (W3).',
    ),
    MixinEntry(
      'mixin/command/DataCommandsMixin.java',
      'DataCommands',
      MixinBucket.hostFeature,
      gap: 'command-data-source',
      note: '`execute store ...` needs a data source for a sub-level.',
    ),
    MixinEntry(
      'mixin/command/ExecuteCommandMixin.java',
      'ExecuteCommand',
      MixinBucket.hostFeature,
      gap: 'command-fork',
      note: '`execute in_sub_level` / `out_sub_level` forks; `/sable` offers a substitute.',
    ),

    // -- conduits ----------------------------------------------------------
    MixinEntry(
      'mixin/conduit/ConduitBlockEntityMixin.java',
      'ConduitBlockEntity',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Conduit effect range on a ship.',
    ),

    // -- third-party compatibility (server-side half) ----------------------
    MixinEntry(
      'mixin/compatibility/computercraft/WirelessNetworkMixin.java',
      'WirelessNetwork',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'ComputerCraft peripheral range must project ship positions.',
    ),
    MixinEntry(
      'mixin/compatibility/etched/StopListeningSoundMixin.java',
      'StopListeningSound',
      MixinBucket.notApplicable,
      note: 'Etched compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/exposure/CameraPosesMixin.java',
      'CameraPoses',
      MixinBucket.notApplicable,
      note: 'Exposure compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/exposure/CameraStandEntityMixin.java',
      'CameraStandEntity',
      MixinBucket.notApplicable,
      note: 'Exposure compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/jade/BlockAccessorImplMixin.java',
      'Jade',
      MixinBucket.notApplicable,
      note: 'Jade compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/jade/RayTracingMixin.java',
      'RayTracing',
      MixinBucket.notApplicable,
      note: 'Jade compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/jadeaddons/CreatePluginMixin.java',
      'CreatePlugin',
      MixinBucket.notApplicable,
      note: 'Jade addons compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'mixin/compatibility/shouldersurfing/ObjectPickerMixin.java',
      'ObjectPicker',
      MixinBucket.notApplicable,
      note: 'Shoulder Surfing compat; client camera mod.',
    ),
    MixinEntry(
      'mixin/compatibility/shouldersurfing/ShoulderSurfingCameraMixin.java',
      'ShoulderSurfingCamera',
      MixinBucket.notApplicable,
      note: 'Shoulder Surfing compat; client camera mod.',
    ),
    MixinEntry(
      'mixin/compatibility/vista/ViewFinderAccessMixin.java',
      'ViewFinderAccess.Block',
      MixinBucket.notApplicable,
      note: 'Vista compat; client camera mod.',
    ),

    // -- death messages ----------------------------------------------------
    MixinEntry(
      'mixin/death_message/CombatTrackerMixin.java',
      'CombatTracker',
      MixinBucket.pluginHook,
      hook: 'player-death-event',
      note: 'Names the ship in the fall message (`FallDeathMessage`).',
    ),
    MixinEntry(
      'mixin/death_message/EntityMixin.java',
      'Entity',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Clears the remembered ship once the entity is on the ground.',
    ),

    // -- debug -------------------------------------------------------------
    MixinEntry(
      'mixin/debug_render/DebugRendererMixin.java',
      'Gizmos',
      MixinBucket.notApplicable,
      note: 'Debug gizmos for tracking anchors; client-side diagnostics.',
    ),
    MixinEntry(
      'mixin/enchanting_table/EnchantingTableBlockEntityMixin.java',
      'EnchantingTableBlockEntity',
      MixinBucket.notApplicable,
      note: 'Book animation aims at the player; cosmetic and computed client-side.',
    ),

    // -- entities: arrows --------------------------------------------------
    MixinEntry(
      'mixin/entity/arrows_hit_blocks/AbstractArrowMixin.java',
      'AbstractArrow',
      MixinBucket.pluginHook,
      hook: 'projectile-hit-event',
      note: 'Arrow sticks in the ship frame and pushes the body (`SubLevelProjectiles.arrowImpact`).',
    ),
    MixinEntry(
      'mixin/entity/entities_in_blocks/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'inside-block-effects',
      note: 'Inside-block effects (fire, portals, cactus) for ship blocks.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Plot-relative position bookkeeping for tracked entities.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/effects/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note:
          'Sprint particles and `getOnPos` at the ship block under the entity.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/effects/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'Fall-damage particles at the ship block.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.notApplicable,
      note: 'Walk-animation distance on a ship; client-side animation state.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/ServerEntityMixin.java',
      'ServerEntity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Sends an entity position relative to the ship.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/packet_mixin/ClientboundMoveEntityPacketPosMixin.java',
      'ClientboundMoveEntityPacket.Pos',
      MixinBucket.hostFeature,
      gap: 'packet-extension',
      note: 'Adds the "actually in a sub-level" boolean to the packet.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/packet_mixin/ClientboundMoveEntityPacketPosRotMixin.java',
      'ClientboundMoveEntityPacket.PosRot',
      MixinBucket.hostFeature,
      gap: 'packet-extension',
      note: 'Same boolean on the pos-rot packet.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/packet_mixin/ClientboundTeleportEntityPacketMixin.java',
      'ClientboundTeleportEntityPacket',
      MixinBucket.hostFeature,
      gap: 'packet-extension',
      note: 'Same boolean on the teleport packet.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/player/ServerboundMovePlayerPacketMixin.java',
      'ServerboundMovePlayerPacket',
      MixinBucket.hostFeature,
      gap: 'player-move-packet',
      note: 'Marks the player tracking a ship from their own move packet.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/player/ServerGamePacketListenerImplMixin.java',
      'ServerGamePacketListenerImpl',
      MixinBucket.hostFeature,
      gap: 'player-move-packet',
      note: 'Disables the moved-too-quickly check while tracking a ship.',
    ),
    MixinEntry(
      'mixin/entity/entities_stick_sublevels/player/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.hostFeature,
      gap: 'entity-tracking-follow',
      note: 'Anchors the player to the tracked ship between poses.',
    ),
    MixinEntry(
      'mixin/entity/entity_aabb_lookup/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.hostFeature,
      gap: 'entity-query',
      note: 'Box entity lookup includes entities in sub-levels.',
    ),
    MixinEntry(
      'mixin/entity/entity_ai/EatBlockGoalMixin.java',
      'EatBlockGoal',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'Animals eat the ship block they stand on.',
    ),
    MixinEntry(
      'mixin/entity/entity_collision/CollisionContextMixin.java',
      'CollisionContext',
      MixinBucket.notApplicable,
      note: 'Caches a collision context per entity; pure allocation avoidance.',
    ),
    MixinEntry(
      'mixin/entity/entity_collision/EntityMixin.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Holds the cached collision context.',
    ),
    MixinEntry(
      'mixin/entity/entity_interaction/ProjectileUtilMixin.java',
      'ProjectileUtil',
      MixinBucket.hostFeature,
      gap: 'clip-raycast',
      note: 'Entity hit selection compares distances across sub-levels.',
    ),
    MixinEntry(
      'mixin/entity/entity_kicking/BlockMixin.java',
      'Block',
      MixinBucket.pluginHook,
      hook: 'entity-spawn-event',
      note:
          'A drop from a ship block is kicked into world space (`DropKicker`).',
    ),
    MixinEntry(
      'mixin/entity/entity_kicking/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.pluginHook,
      hook: 'entity-spawn-event',
      note: 'An entity added inside a plot is kicked out (`SpawnKicker`).',
    ),
    MixinEntry(
      'mixin/entity/entity_leashing/LeashableMixin.java',
      'Leashable',
      MixinBucket.hostFeature,
      gap: 'leash-physics',
      note: 'Leash elasticity against a moving ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/FlyNodeEvaluatorMixin.java',
      'FlyNodeEvaluator',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Flying mobs pathfind in the ship frame.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/GroundPathNavigationMixin.java',
      'GroundPathNavigation',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Ground navigation start node on a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/PathfindingContextMixin.java',
      'PathfindingContext',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Pathfinding context remembers the ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/PathMixin.java',
      'Path',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'A path computed in a ship is projected to world positions.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/PathNavigationMixin.java',
      'PathNavigation',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Path creation targets inside a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/RandomPosMixin.java',
      'RandomPos',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Random positions around a mob on a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_pathfinding/WalkNodeEvaluatorMixin.java',
      'WalkNodeEvaluator',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Walkable nodes on a ship.',
    ),

    // -- entities: rotations and riding ------------------------------------
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/BlockMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'Restitution after a collision on a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-riding',
      note: '`moveRelative`, `rideTick`, `positionRider` and saving a ridden vehicle position.',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/EntityTypeMixin.java',
      'EntityType',
      MixinBucket.pluginHook,
      hook: 'entity-mount-event',
      note: 'Passengers loaded inside a ship are kicked out (`EntitySubLevelUtil.kickEntity`).',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-riding',
      note: 'Jumping and dismounting from a vehicle on a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/PlayerMixin.java',
      'Player',
      MixinBucket.hostFeature,
      gap: 'entity-riding',
      note: 'Travel and step logic while riding a vehicle on a ship.',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/ServerEntityMixin.java',
      'ServerEntity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Rider positions sent in the ship frame.',
    ),
    MixinEntry(
      'mixin/entity/entity_rotations_and_riding/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'entity-mount-event',
      note: 'A player mounting on a ship is teleported with it.',
    ),

    // -- entities: sub-level collision -------------------------------------
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/AbstractMinecartMixin.java',
      'AbstractMinecart',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Minecarts are destroyed once they leave the plot (`PlotLeash`).',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'The core `Entity#move` patch: sweep, step-up, collision flags, tracking.',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/ItemEntityMixin.java',
      'ItemEntity',
      MixinBucket.hostFeature,
      gap: 'entity-tick-rate',
      note: 'An item on a ship must tick every tick.',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/LevelMixin.java',
      'Level',
      MixinBucket.notApplicable,
      note: 'Scratch vectors for the collision pass; the port keeps its own scratch.',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.pluginHook,
      hook: 'entity-damage-event',
      note: 'Bounce and `flyIntoWall` damage are ported (`CollisionEffects`); the inherited-velocity half is the sweep gap.',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/PlayerMixin.java',
      'Player',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'Edge back-off and `canFallAtLeast` against ship blocks (algorithm ported).',
    ),
    MixinEntry(
      'mixin/entity/entity_sublevel_collision/ServerGamePacketListenerImplMixin.java',
      'ServerGamePacketListenerImpl',
      MixinBucket.hostFeature,
      gap: 'player-move-packet',
      note: 'The moved-wrongly check is disabled on ships.',
    ),

    // -- entities: misc ----------------------------------------------------
    MixinEntry(
      'mixin/entity/entity_tracking/TrackedEntityMixin.java',
      'ChunkMap.TrackedEntity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Tracking range uses the projected position.',
    ),
    MixinEntry(
      'mixin/entity/entity_unloading/PersistentEntitySectionManagerMixin.java',
      'PersistentEntitySectionManager',
      MixinBucket.hostFeature,
      gap: 'entity-unloading',
      note: 'Entities in plot chunks are not unloaded with the world chunk.',
    ),
    MixinEntry(
      'mixin/entity/falling_block/FallingBlockEntityMixin.java',
      'FallingBlockEntity',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'A falling block checks the ship block under it for landing.',
    ),
    MixinEntry(
      'mixin/entity/parrot/ParrotMixin.java',
      'Parrot',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Shoulder-perch distance on a ship.',
    ),
    MixinEntry(
      'mixin/entity/projectile/ProjectileMixin.java',
      'Projectile',
      MixinBucket.pluginHook,
      hook: 'projectile-launch-event',
      note: 'Shot direction rotated and shooter velocity inherited (`SubLevelProjectiles.launch`).',
    ),
    MixinEntry(
      'mixin/entity/server_entities_tick/ChunkMapMixin.java',
      'ChunkMap',
      MixinBucket.hostFeature,
      gap: 'entity-tick-rate',
      note: 'Entities in plot chunks tick when a player is near the ship.',
    ),
    MixinEntry(
      'mixin/entity/server_entities_tick/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.hostFeature,
      gap: 'entity-tick-rate',
      note: 'Entity ticking range for plot chunks.',
    ),
    MixinEntry(
      'mixin/entity/sublevels_block_sky/SubLevelsBlockSkyMixin.java',
      'Mob / FleeSunGoal / GroundPathNavigation',
      MixinBucket.hostFeature,
      gap: 'can-see-sky',
      note: 'Mobs on a ship are not in daylight just because the plot is open to the sky.',
    ),
    MixinEntry(
      'mixin/entity/tamed_teleport/TamableAnimalMixin.java',
      'TamableAnimal',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'A pet may teleport to its owner on a ship.',
    ),
    MixinEntry(
      'mixin/entity/teleport_players/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'player-teleport-event',
      note: 'Teleport targets are projected out of the ship (`PlayerProjection`).',
    ),
    MixinEntry(
      'mixin/entity/tnt_jumps/PrimedTntMixin.java',
      'PrimedTnt',
      MixinBucket.pluginHook,
      hook: 'entity-spawn-event',
      note: 'TNT spawned on a ship gets its velocity rotated into world space.',
    ),
    MixinEntry(
      'mixin/entity/trident/ThrownTridentMixin.java',
      'ThrownTrident',
      MixinBucket.hostFeature,
      gap: 'projectile-state',
      note: 'A returning trident is kicked out of the ship when it becomes intangible.',
    ),

    // -- explosions --------------------------------------------------------
    MixinEntry(
      'mixin/explosion/ExplosionMixin.java',
      'ServerExplosion',
      MixinBucket.hostFeature,
      gap: 'explosion-ray',
      note: 'Blast rays destroy ship blocks and push the body (`SubLevelExplosions.walk`).',
    ),
    MixinEntry(
      'mixin/explosion/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.pluginHook,
      hook: 'entity-explode-event',
      note: 'The blast centre is projected out of the ship (`SubLevelExplosions.projectCentre`).',
    ),
    MixinEntry(
      'mixin/extension/EntityMixin.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Exposes vanilla `collide` to the collision code; a Dart helper, not a host hook.',
    ),

    // -- fluids ------------------------------------------------------------
    MixinEntry(
      'mixin/fluids_on_sub_levels/FlowingFluidMixin.java',
      'FlowingFluid',
      MixinBucket.pluginHook,
      hook: 'fluid-level-change-event',
      note: 'Fluids do not flow off the edge of a ship (`FluidSpreadGuard`).',
    ),

    // -- game test ---------------------------------------------------------
    MixinEntry(
      'mixin/game_test/GameTestInfoMixin.java',
      'GameTestInfo',
      MixinBucket.notApplicable,
      note: 'Game-test harness only.',
    ),
    MixinEntry(
      'mixin/game_test/StructureUtilsMixin.java',
      'StructureUtils',
      MixinBucket.notApplicable,
      note: 'Game-test harness only.',
    ),
    MixinEntry(
      'mixin/game_test/TestCommandMixin.java',
      'TestCommand',
      MixinBucket.notApplicable,
      note: 'Game-test harness only.',
    ),

    // -- impact callbacks --------------------------------------------------
    MixinEntry(
      'mixin/impact/BeehiveBlockMixin.java',
      'BeehiveBlock',
      MixinBucket.pluginHook,
      hook: 'block-collision-callback',
      note: '`BeehiveBlockCallback` (ported).',
    ),
    MixinEntry(
      'mixin/impact/BellBlockMixin.java',
      'BellBlock',
      MixinBucket.pluginHook,
      hook: 'block-collision-callback',
      note: '`BellBlockCallback` (ported).',
    ),
    MixinEntry(
      'mixin/impact/TntBlockMixin.java',
      'TntBlock',
      MixinBucket.pluginHook,
      hook: 'block-collision-callback',
      note: '`ExplosiveBlockCallback` (ported).',
    ),

    // -- interaction distance ---------------------------------------------
    MixinEntry(
      'mixin/interaction_distance/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: '`distanceTo` / `distanceToSqr` across sub-levels.',
    ),
    MixinEntry(
      'mixin/interaction_distance/PlayerMixin.java',
      'Player',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Block and entity interaction range on a ship.',
    ),
    MixinEntry(
      'mixin/level_accelerator/ServerChunkCacheAccessor.java',
      'ServerChunkCache',
      MixinBucket.notApplicable,
      note: 'Accessor for the chunk cache; no behaviour.',
    ),
    MixinEntry(
      'mixin/loaded_chunk_debug/LevelChunkMixin.java',
      'LevelChunk',
      MixinBucket.notApplicable,
      note: 'Debug timestamp on chunks.',
    ),
    MixinEntry(
      'mixin/particle/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Particles are sent to players near the ship, not near the plot.',
    ),

    // -- physics -----------------------------------------------------------
    MixinEntry(
      'mixin/physics/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.notApplicable,
      note: 'Holds the physics scene id; the port keeps it on the physics system.',
    ),

    // -- player freezing ---------------------------------------------------
    MixinEntry(
      'mixin/player_freezing/PlayerMixin.java',
      'Player',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Freeze state machine with a 160-tick timeout (`FrozenPlayer`).',
    ),
    MixinEntry(
      'mixin/player_freezing/PlayerListMixin.java',
      'PlayerList',
      MixinBucket.pluginHook,
      hook: 'player-join-event',
      note: 'Re-sends `sable:freeze_player` on join and respawn.',
    ),
    MixinEntry(
      'mixin/player_freezing/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Teleports a frozen player to the ship anchor every tick.',
    ),
    MixinEntry(
      'mixin/player_standup/PlayerMixin.java',
      'Player',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'A player may only stand up if the ship has room (ported `canFallAtLeast`).',
    ),

    // -- plot --------------------------------------------------------------
    MixinEntry(
      'mixin/plot/ChunkMapMixin.java',
      'ChunkMap',
      MixinBucket.hostFeature,
      gap: 'chunk-source',
      note: 'Plot chunks must not be saved/loaded/spawned in as world chunks.',
    ),
    MixinEntry(
      'mixin/plot/LevelChunkMixin.java',
      'LevelChunk',
      MixinBucket.pluginHook,
      hook: 'block-place-event',
      note: 'Block writes in a plot must reach `LevelPlot.onBlockChange` (also for plugin writes).',
    ),
    MixinEntry(
      'mixin/plot/lighting/BlockAndTintGetterMixin.java',
      'BlockAndLightGetter',
      MixinBucket.hostFeature,
      gap: 'plot-lighting',
      note: 'Light lookups for plot positions.',
    ),
    MixinEntry(
      'mixin/plot/lighting/LevelChunkMixin.java',
      'LevelChunk',
      MixinBucket.hostFeature,
      gap: 'plot-lighting',
      note: 'Light engine selection for plot chunks.',
    ),
    MixinEntry(
      'mixin/plot/PlayerListMixin.java',
      'PlayerList',
      MixinBucket.hostFeature,
      gap: 'interaction-range',
      note: 'Distance-based packet broadcast must project ship positions.',
    ),
    MixinEntry(
      'mixin/plot/container/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.pluginHook,
      hook: 'world-load-event',
      note: 'Creates and closes the per-level sub-level container.',
    ),
    MixinEntry(
      'mixin/plot/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.pluginHook,
      hook: 'world-save-event',
      note: 'Ticks, saves and closes the container with the level.',
    ),
    MixinEntry(
      'mixin/plot/serialization/ChunkMapMixin.java',
      'ChunkMap',
      MixinBucket.hostFeature,
      gap: 'chunk-serialization',
      note: 'Saving and loading plot chunks.',
    ),
    MixinEntry(
      'mixin/plot/serialization/LevelChunkTicksMixin.java',
      'LevelChunkTicks',
      MixinBucket.hostFeature,
      gap: 'chunk-serialization',
      note: 'Copies scheduled ticks when a plot chunk is serialized.',
    ),
    MixinEntry(
      'mixin/plot/ServerChunkCacheMixin.java',
      'ServerChunkCache',
      MixinBucket.hostFeature,
      gap: 'chunk-source',
      note: 'Serves plot chunks from the container instead of the world generator.',
    ),

    // -- portals -----------------------------------------------------------
    MixinEntry(
      'mixin/portal/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'portal-frame',
      note: 'Portal entry from inside a ship.',
    ),
    MixinEntry(
      'mixin/portal/NetherPortalBlockMixin.java',
      'NetherPortalBlock',
      MixinBucket.hostFeature,
      gap: 'portal-frame',
      note: 'Portal destination is projected out of the ship.',
    ),

    // -- world behaviour ---------------------------------------------------
    MixinEntry(
      'mixin/prevent_freezing/BiomeMixin.java',
      'Biome',
      MixinBucket.hostFeature,
      gap: 'biome-temperature',
      note: 'Water on a ship does not freeze because the plot biome is cold.',
    ),
    MixinEntry(
      'mixin/prevent_overgrowth/VineBlockMixin.java',
      'VineBlock',
      MixinBucket.pluginHook,
      hook: 'block-spread-event',
      note: 'Vines do not spread inside a plot (`OvergrowthGuard`).',
    ),
    MixinEntry(
      'mixin/punching/ItemInvoker.java',
      'Item',
      MixinBucket.notApplicable,
      note: 'Invoker used by the client punch path.',
    ),
    MixinEntry(
      'mixin/recoil/ProjectileDispenseBehaviorMixin.java',
      'ProjectileDispenseBehavior',
      MixinBucket.pluginHook,
      hook: 'block-dispense-event',
      note: 'A dispenser on a ship recoils (`SubLevelProjectiles.dispenserRecoil`).',
    ),

    // -- respawn -----------------------------------------------------------
    MixinEntry(
      'mixin/respawn_point/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'spawn-change-event',
      note: 'Respawn anchor on a ship (`RespawnAnchor`).',
    ),
    MixinEntry(
      'mixin/respawn_point/sleeping/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'sleep-position',
      note: 'Waking up on a ship; the projection is ported (`PlayerProjection.standUpPosition`).',
    ),
    MixinEntry(
      'mixin/respawn_point/sleeping/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'player-respawn-event',
      note: 'The respawn position is projected out of the ship.',
    ),

    // -- sculk -------------------------------------------------------------
    MixinEntry(
      'mixin/sculk_vibrations/EuclideanGameEventListenerRegistryMixin.java',
      'EuclideanGameEventListenerRegistry',
      MixinBucket.hostFeature,
      gap: 'sculk-vibration',
      note: 'Sculk sensors hear events on a ship.',
    ),
    MixinEntry(
      'mixin/sculk_vibrations/GameEventDispatcherMixin.java',
      'GameEventDispatcher',
      MixinBucket.hostFeature,
      gap: 'sculk-vibration',
      note: 'Game events are dispatched with the projected position.',
    ),
    MixinEntry(
      'mixin/sculk_vibrations/VibrationSystemListenerMixin.java',
      'VibrationSystem.Listener',
      MixinBucket.hostFeature,
      gap: 'sculk-vibration',
      note: 'Vibration listener positions.',
    ),
    MixinEntry(
      'mixin/sculk_vibrations/VibrationSystemTickerMixin.java',
      'VibrationSystem.Ticker',
      MixinBucket.hostFeature,
      gap: 'sculk-vibration',
      note: 'Vibration travel distance.',
    ),

    // -- signs, weather, tracking, udp ------------------------------------
    MixinEntry(
      'mixin/sign_interaction/SignBlockEntityMixin.java',
      'SignBlockEntity',
      MixinBucket.hostFeature,
      gap: 'sign-block-entity',
      note: 'Clicking a sign on a ship needs the click position in the ship frame.',
    ),
    MixinEntry(
      'mixin/stop_lightning/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.pluginHook,
      hook: 'lightning-strike-event',
      note: 'No lightning inside the plot yard (`LightningGuard`).',
    ),
    MixinEntry(
      'mixin/tracking_points/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-nbt',
      note: 'Tracking-point data saved on an entity.',
    ),
    MixinEntry(
      'mixin/tracking_points/ServerPlayerMixin.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'persistent-data',
      note: 'Tracking-point data saved on the player.',
    ),
    MixinEntry(
      'mixin/udp/ConnectionMixin.java',
      'Connection',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'Per-connection UDP channel; the port falls back to TCP.',
    ),
    MixinEntry(
      'mixin/udp/MinecraftServerMixin.java',
      'MinecraftServer',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'Ticks the UDP server channel.',
    ),
    MixinEntry(
      'mixin/udp/PlayerListMixin.java',
      'PlayerList',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'Starts UDP authentication for a joining player.',
    ),
    MixinEntry(
      'mixin/udp/ServerConnectionListenerMixin.java',
      'ServerConnectionListener',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'Binds the UDP socket next to the TCP listener.',
    ),

    // -- shapes, water, border --------------------------------------------
    MixinEntry(
      'mixin/voxel_shape_iteration/BitSetDiscreteVoxelShapeAccessor.java',
      'BitSetDiscreteVoxelShape',
      MixinBucket.notApplicable,
      note: 'Accessor for a faster shape iterator.',
    ),
    MixinEntry(
      'mixin/voxel_shape_iteration/DiscreteVoxelShapeAccessor.java',
      'DiscreteVoxelShape',
      MixinBucket.notApplicable,
      note: 'Accessor for a faster shape iterator.',
    ),
    MixinEntry(
      'mixin/voxel_shape_iteration/VoxelShapeMixin.java',
      'VoxelShape',
      MixinBucket.notApplicable,
      note:
          'Allocation-free shape iteration; Dart iterates its own shape data.',
    ),
    MixinEntry(
      'mixin/water_occlusion/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'fluid-occlusion',
      note: 'Touching and swimming in water carried by a ship.',
    ),
    MixinEntry(
      'mixin/water_occlusion/ServerLevelMixin.java',
      'ServerLevel',
      MixinBucket.notApplicable,
      note: 'Holds the water-occlusion container; W2 owns it.',
    ),
    MixinEntry(
      'mixin/water_occlusion/WaterFluidMixin.java',
      'WaterFluid',
      MixinBucket.notApplicable,
      note: 'Water particle position; cosmetic.',
    ),
    MixinEntry(
      'mixin/world_border/LevelMixin.java',
      'Level',
      MixinBucket.notApplicable,
      note: 'Attaches the level to its border object; no behaviour.',
    ),
    MixinEntry(
      'mixin/world_border/WorldBorderMixin.java',
      'WorldBorder',
      MixinBucket.hostFeature,
      gap: 'world-border',
      note: 'The world border ignores entities on a ship.',
    ),
  ];

  /// `common/.../mixin/**`, client-side (82 files). The plugin is server-only,
  /// so these are recorded by path and not ported.
  static const List<String> commonClientMixins = [
    'mixin/block_decal_render/LevelExtractorMixin.java',
    'mixin/block_decal_render/LevelRendererMixin.java',
    'mixin/camera/camera_rotation/CompassItemPropertyFunctionMixin.java',
    'mixin/camera/camera_rotation/GuiMixin.java',
    'mixin/camera/camera_zoom/CameraMixin.java',
    'mixin/camera/camera_zoom/MouseHandlerMixin.java',
    'mixin/camera/new_camera_types/CameraTypeMixin.java',
    'mixin/camera/new_camera_types/GameRendererMixin.java',
    'mixin/camera/new_camera_types/MinecraftMixin.java',
    'mixin/clip_overwrite/ClientLevelMixin.java',
    'mixin/clip_overwrite/LocalPlayerMixin.java',
    'mixin/command/ClientSuggestionProviderMixin.java',
    'mixin/compatibility/iris/ExtendedShaderMixin.java',
    'mixin/compatibility/shouldersurfing/EntityHelperMixin.java',
    'mixin/compatibility/shouldersurfing/PerspectiveMixin.java',
    'mixin/compatibility/shouldersurfing/ShoulderSurfingImplMixin.java',
    'mixin/compatibility/vista/LODMixin.java',
    'mixin/compatibility/vista/ViewFinderControllerMixin.java',
    'mixin/conduit/ConduitRendererMixin.java',
    'mixin/debug_render/DebugScreenOverlayMixin.java',
    'mixin/debug_render/LevelRendererMixin.java',
    'mixin/dynamic_directional_shading/AmbientOcclusionFaceMixin.java',
    'mixin/dynamic_directional_shading/ModelBlockRendererCacheMixin.java',
    'mixin/dynamic_directional_shading/ModelBlockRendererMixin.java',
    'mixin/entity/entities_stick_sublevels/ClientPacketListenerMixin.java',
    'mixin/entity/entities_stick_sublevels/effects/LocalPlayerMixin.java',
    'mixin/entity/entities_stick_sublevels/EntityRenderDispatcherMixin.java',
    'mixin/entity/entities_stick_sublevels/player/LocalPlayerMixin.java',
    'mixin/entity/entities_stick_sublevels/player/RemotePlayerMixin.java',
    'mixin/entity/entities_turn_with_sub_levels/GameRendererMixin.java',
    'mixin/entity/entity_aabb_lookup/ClientLevelMixin.java',
    'mixin/entity/entity_leashing/EntityRendererMixin.java',
    'mixin/entity/entity_rendering/EntityRendererMixin.java',
    'mixin/entity/entity_rendering/LevelRendererMixin.java',
    'mixin/entity/entity_rendering/shadows/EntityRenderDispatcherMixin.java',
    'mixin/entity/entity_rotations_and_riding/ClientPacketListenerMixin.java',
    'mixin/entity/entity_rotations_and_riding/EntityRendererMixin.java',
    'mixin/entity/entity_rotations_and_riding/LocalPlayerMixin.java',
    'mixin/entity/entity_sublevel_collision/CameraMixin.java',
    'mixin/entity/entity_swimming/CameraMixin.java',
    'mixin/loaded_chunk_debug/BlockUpdatePacketMixin.java',
    'mixin/loaded_chunk_debug/ChunkBorderRendererMixin.java',
    'mixin/loaded_chunk_debug/ClientChunkCacheStorageAccessor.java',
    'mixin/options/OptionsScreenMixin.java',
    'mixin/particle/BlockMarkerMixin.java',
    'mixin/particle/ClientLevelMixin.java',
    'mixin/particle/FlameParticleMixin.java',
    'mixin/particle/LevelRendererMixin.java',
    'mixin/particle/ParticleEngineMixin.java',
    'mixin/particle/ParticleGroupMixin.java',
    'mixin/particle/ParticleMixin.java',
    'mixin/particle/SuspendedParticleMixin.java',
    'mixin/particle/TerrainParticleMixin.java',
    'mixin/player_freezing/LocalPlayerMixin.java',
    'mixin/plot/ClientChunkCacheMixin.java',
    'mixin/plot/container/ClientLevelMixin.java',
    'mixin/plot/lighting/ClientPacketListenerMixin.java',
    'mixin/plot/lighting/RenderChunkRegionMixin.java',
    'mixin/plot/MinecraftMixin.java',
    'mixin/punching/MinecraftMixin.java',
    'mixin/punching/MultiPlayerGameModeMixin.java',
    'mixin/respawn_point/sleeping/LivingEntityRendererMixin.java',
    'mixin/sky_light_shadow/LevelRendererMixin.java',
    'mixin/stop_rain/LevelRenderMixin.java',
    'mixin/sublevel_render/BlockEntityRenderDispatcherMixin.java',
    'mixin/sublevel_render/block_entity_render/LevelRendererMixin.java',
    'mixin/sublevel_render/BlockEntityRenderStateMixin.java',
    'mixin/sublevel_render/BrightnessCombinerMixin.java',
    'mixin/sublevel_render/impl/sodium/LevelRendererMixin.java',
    'mixin/sublevel_render/impl/sodium/SodiumWorldRendererMixin.java',
    'mixin/sublevel_render/impl/vanilla/LevelRendererMixin.java',
    'mixin/sublevel_render/impl/vanilla/ViewAreaMixin.java',
    'mixin/sublevel_render/LevelRendererMixin.java',
    'mixin/sublevel_sounds/AbstractSoundInstanceMixin.java',
    'mixin/sublevel_sounds/ChannelAccessor.java',
    'mixin/sublevel_sounds/ClientLevelMixin.java',
    'mixin/sublevel_sounds/SoundEngineMixin.java',
    'mixin/toast/IntegratedServerMixin.java',
    'mixin/water_occlusion/CameraMixin.java',
    'mixin/water_occlusion/ClientLevelMixin.java',
    'mixin/water_occlusion/FogRendererMixin.java',
    'mixin/water_occlusion/GameRendererMixin.java',
  ];

  /// `common/.../mixinterface/**` (33 files).
  static const List<MixinEntry> commonMixInterfaces = [
    MixinEntry(
      'mixinterface/BlockEntityRenderDispatcherExtension.java',
      'BlockEntityRenderDispatcher',
      MixinBucket.notApplicable,
      note: 'Client renderer state.',
    ),
    MixinEntry(
      'mixinterface/block_properties/BlockStateExtension.java',
      'BlockState',
      MixinBucket.notApplicable,
      note:
          'Physics properties on states; replaced by the plugin property map.',
    ),
    MixinEntry(
      'mixinterface/camera/camera_zoom/CameraZoomExtension.java',
      'Camera',
      MixinBucket.notApplicable,
      note: 'Client camera state.',
    ),
    MixinEntry(
      'mixinterface/clip_overwrite/ClipContextExtension.java',
      'ClipContext',
      MixinBucket.notApplicable,
      note: 'Port passes the ignored sub-level as a parameter.',
    ),
    MixinEntry(
      'mixinterface/clip_overwrite/LevelPoseProviderExtension.java',
      'Level',
      MixinBucket.notApplicable,
      note: 'Client render pose lookup.',
    ),
    MixinEntry(
      'mixinterface/compatibility/iris/ExtendedShaderExtension.java',
      'ExtendedShader',
      MixinBucket.notApplicable,
      note: 'Iris compat.',
    ),
    MixinEntry(
      'mixinterface/dynamic_directional_shading/ModelBlockRendererCacheExtension.java',
      'ModelBlockRendererCache',
      MixinBucket.notApplicable,
      note: 'Client shading cache.',
    ),
    MixinEntry(
      'mixinterface/entity/entities_stick_sublevels/EntityStickExtension.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Plot position and lerp state for a tracked entity.',
    ),
    MixinEntry(
      'mixinterface/entity/entities_stick_sublevels/LivingEntityStickExtension.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-wire-position',
      note: 'Lerp state for a tracked living entity.',
    ),
    MixinEntry(
      'mixinterface/entity/entities_stick_sublevels/packet_mixin/PacketActuallyInSubLevelExtension.java',
      'ClientboundMoveEntityPacket',
      MixinBucket.hostFeature,
      gap: 'packet-extension',
      note: 'The extra packet boolean.',
    ),
    MixinEntry(
      'mixinterface/entity/entities_stick_sublevels/player/ServerboundMovePlayerPacketExtension.java',
      'ServerboundMovePlayerPacket',
      MixinBucket.hostFeature,
      gap: 'player-move-packet',
      note: 'Move packet carries the ship.',
    ),
    MixinEntry(
      'mixinterface/entity/entity_collision/EntityExtension.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Cached collision context; allocation only.',
    ),
    MixinEntry(
      'mixinterface/entity/entity_sublevel_collision/EntityMovementExtension.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'Tracking sub-level and collision info on an entity.',
    ),
    MixinEntry(
      'mixinterface/entity/entity_sublevel_collision/LevelExtension.java',
      'Level',
      MixinBucket.notApplicable,
      note: 'Scratch vectors; the port keeps its own.',
    ),
    MixinEntry(
      'mixinterface/entity/entity_sublevel_collision/LivingEntityMovementExtension.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'Inherited velocity on a living entity.',
    ),
    MixinEntry(
      'mixinterface/EntityExtension.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Vanilla `collide` accessor for the collision code.',
    ),
    MixinEntry(
      'mixinterface/entity/pathfinding/PathExtension.java',
      'Path',
      MixinBucket.hostFeature,
      gap: 'pathfinding',
      note: 'Marks a path as computed in a ship.',
    ),
    MixinEntry(
      'mixinterface/loaded_chunk_debug/DebugChunkProviderAttachments.java',
      'ChunkMap',
      MixinBucket.notApplicable,
      note: 'Debug data.',
    ),
    MixinEntry(
      'mixinterface/loaded_chunk_debug/DebugLevelChunkExtension.java',
      'LevelChunk',
      MixinBucket.notApplicable,
      note: 'Debug timestamp.',
    ),
    MixinEntry(
      'mixinterface/particle/ParticleExtension.java',
      'Particle',
      MixinBucket.notApplicable,
      note: 'Client particle state.',
    ),
    MixinEntry(
      'mixinterface/physics/ServerLevelSceneExtension.java',
      'ServerLevel',
      MixinBucket.notApplicable,
      note: 'Physics scene id; the port keeps it on the physics system.',
    ),
    MixinEntry(
      'mixinterface/player_freezing/PlayerFreezeExtension.java',
      'Player',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Freeze state (`FrozenPlayer`).',
    ),
    MixinEntry(
      'mixinterface/plot/serialization/ChunkAccessExtension.java',
      'ChunkAccess',
      MixinBucket.hostFeature,
      gap: 'chunk-serialization',
      note: 'Chunk attachments in a plot chunk.',
    ),
    MixinEntry(
      'mixinterface/plot/serialization/LevelChunkTicksExtension.java',
      'LevelChunkTicks',
      MixinBucket.hostFeature,
      gap: 'chunk-serialization',
      note: 'Copies scheduled ticks.',
    ),
    MixinEntry(
      'mixinterface/plot/SubLevelContainerHolder.java',
      'Level',
      MixinBucket.pluginHook,
      hook: 'world-load-event',
      note: 'The per-level container (`SubLevelContainer.of`).',
    ),
    MixinEntry(
      'mixinterface/respawn_point/ServerPlayerRespawnExtension.java',
      'ServerPlayer',
      MixinBucket.pluginHook,
      hook: 'spawn-change-event',
      note: 'The respawn anchor id (`RespawnAnchor`).',
    ),
    MixinEntry(
      'mixinterface/toast/SableToastableServer.java',
      'MinecraftServer',
      MixinBucket.notApplicable,
      note: 'Singleplayer toast; client-only.',
    ),
    MixinEntry(
      'mixinterface/udp/ConnectionExtension.java',
      'Connection',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'The connection\'s UDP channel.',
    ),
    MixinEntry(
      'mixinterface/udp/ServerConnectionListenerExtension.java',
      'ServerConnectionListener',
      MixinBucket.hostFeature,
      gap: 'udp-channel',
      note: 'The server\'s UDP channel.',
    ),
    MixinEntry(
      'mixinterface/voxel_shape_iteration/FastVoxelShapeIterable.java',
      'VoxelShape',
      MixinBucket.notApplicable,
      note: 'Faster shape iteration; not needed in Dart.',
    ),
    MixinEntry(
      'mixinterface/water_occlusion/CameraWaterOcclusionExtension.java',
      'Camera',
      MixinBucket.notApplicable,
      note: 'Client camera water state.',
    ),
    MixinEntry(
      'mixinterface/water_occlusion/WaterOcclusionContainerHolder.java',
      'Level',
      MixinBucket.notApplicable,
      note: 'W2 owns the water-occlusion container.',
    ),
    MixinEntry(
      'mixinterface/world_border/WorldBorderExtension.java',
      'WorldBorder',
      MixinBucket.hostFeature,
      gap: 'world-border',
      note: 'The border needs the level to project positions.',
    ),
  ];

  /// `common/.../mixinhelpers/**` (16 files).
  static const List<MixinEntry> commonMixinHelpers = [
    MixinEntry(
      'mixinhelpers/block_outline_render/SubLevelCamera.java',
      'SubLevelCamera',
      MixinBucket.notApplicable,
      note: 'Client outline renderer.',
    ),
    MixinEntry(
      'mixinhelpers/camera/camera_rotation/EntitySubLevelRotationHelper.java',
      'Entity',
      MixinBucket.notApplicable,
      note: 'Client camera rotation.',
    ),
    MixinEntry(
      'mixinhelpers/camera/new_camera_types/SableCameraTypes.java',
      'CameraType',
      MixinBucket.notApplicable,
      note: 'Client camera types.',
    ),
    MixinEntry(
      'mixinhelpers/CanFallAtleastHelper.java',
      'CanFallAtleastHelper',
      MixinBucket.hostFeature,
      gap: 'entity-movement-sweep',
      note: 'Ported as `SubLevelStanding.canFallAtLeast`.',
    ),
    MixinEntry(
      'mixinhelpers/compatibility/shouldersurfing/SablePerspectives.java',
      'Perspective',
      MixinBucket.notApplicable,
      note: 'Client compat.',
    ),
    MixinEntry(
      'mixinhelpers/entity/entity_collision/TheFasterEntityCollisionContext.java',
      'CollisionContext',
      MixinBucket.notApplicable,
      note: 'Cached collision context; allocation only.',
    ),
    MixinEntry(
      'mixinhelpers/entity/entity_rendering/EntityRenderRotationState.java',
      'EntityRenderState',
      MixinBucket.notApplicable,
      note: 'Client render state.',
    ),
    MixinEntry(
      'mixinhelpers/entity/entity_rendering/shadows/SubLevelEntityShadowRenderer.java',
      'EntityRenderDispatcher',
      MixinBucket.notApplicable,
      note: 'Client shadows.',
    ),
    MixinEntry(
      'mixinhelpers/entity/entity_rendering/SubLevelPoseHelper.java',
      'EntityRenderer',
      MixinBucket.notApplicable,
      note: 'Client pose.',
    ),
    MixinEntry(
      'mixinhelpers/entity/entity_riding_sub_level_vehicle/EntityRidingSubLevelVehicleHelper.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'entity-riding',
      note: 'Ported as `SubLevelEntityRules.kickRidingEntity`.',
    ),
    MixinEntry(
      'mixinhelpers/entity/sublevels_block_sky/SubLevelsBlockSkyMixinHelper.java',
      'Mob',
      MixinBucket.hostFeature,
      gap: 'can-see-sky',
      note: 'Sky check against ship blocks.',
    ),
    MixinEntry(
      'mixinhelpers/loaded_chunk_debug/SableChunkDebugRenderer.java',
      'SableChunkDebugRenderer',
      MixinBucket.notApplicable,
      note: 'Client debug.',
    ),
    MixinEntry(
      'mixinhelpers/sublevel_render/vanilla/VanillaSubLevelBlockEntityRenderer.java',
      'BlockEntityRenderer',
      MixinBucket.notApplicable,
      note: 'Client rendering.',
    ),
    MixinEntry(
      'mixinhelpers/voxel_shape_iteration/FastVoxelShapeIterator.java',
      'FastVoxelShapeIterator',
      MixinBucket.notApplicable,
      note: 'Faster shape iteration.',
    ),
    MixinEntry(
      'mixinhelpers/voxel_shape_iteration/LongArrayDiscreteVoxelShape.java',
      'DiscreteVoxelShape',
      MixinBucket.notApplicable,
      note: 'Faster shape storage.',
    ),
  ];

  /// NeoForge `mixin/**`, non-Create (23 files).
  static const List<MixinEntry> neoforgeMixins = [
    MixinEntry(
      'neoforge/mixin/block_entity_visible/BlockEntityRenderDispatcherMixin.java',
      'BlockEntityRenderDispatcher',
      MixinBucket.notApplicable,
      note: 'Client visibility.',
    ),
    MixinEntry(
      'neoforge/mixin/block_outline_render/LevelRendererMixin.java',
      'LevelRenderer',
      MixinBucket.notApplicable,
      note: 'Client outline.',
    ),
    MixinEntry(
      'neoforge/mixin/camera_rotation/CameraMixin.java',
      'Camera',
      MixinBucket.notApplicable,
      note: 'Client camera.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/backpacks/BackpackPickupEventsMixin.java',
      'BackpackPickupEvents',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/AbstractBlockEntityVisualMixin.java',
      'AbstractBlockEntityVisual',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/BlockEntityStorageMixin.java',
      'BlockEntityStorage',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/EmbeddedEnvironmentMixin.java',
      'EmbeddedEnvironment',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/EngineImplMixin.java',
      'EngineImpl',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/EnvironmentStorageMixin.java',
      'EnvironmentStorage',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/LightStorageAccessor.java',
      'LightStorage',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/MatrixBufferMixin.java',
      'MatrixBuffer',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/RenderDispatcherImplMixin.java',
      'RenderDispatcherImpl',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/ShaderSourcesMixin.java',
      'ShaderSources',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/flywheel/VisualManagerImplMixin.java',
      'VisualManagerImpl',
      MixinBucket.notApplicable,
      note: 'Flywheel rendering.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/pmweather/AnemometerBlockEntityMixin.java',
      'AnemometerBlockEntity',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat; the mod is not part of the port.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/pmweather/AnemometerBlockMixin.java',
      'AnemometerBlock',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/pmweather/PMWeatherMixin.java',
      'PMWeather',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/pmweather/RadarRendererMixin.java',
      'RadarRenderer',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat.',
    ),
    MixinEntry(
      'neoforge/mixin/compatibility/sodiumextras/EmbyToolsMixin.java',
      'EmbyTools',
      MixinBucket.notApplicable,
      note: 'Third-party mod compat.',
    ),
    MixinEntry(
      'neoforge/mixin/dynamic_directional_shading/SectionCompilerMixin.java',
      'SectionCompiler',
      MixinBucket.notApplicable,
      note: 'Client shading.',
    ),
    MixinEntry(
      'neoforge/mixin/entities_stick_sublevels/effects/LivingEntityMixin.java',
      'LivingEntity',
      MixinBucket.hostFeature,
      gap: 'entity-block-pos',
      note: 'Block-fall sound uses the ship block.',
    ),
    MixinEntry(
      'neoforge/mixin/entity/entity_swimming/EntityMixin.java',
      'Entity',
      MixinBucket.hostFeature,
      gap: 'fluid-occlusion',
      note: 'Swimming in water carried by a ship.',
    ),
    MixinEntry(
      'neoforge/mixin/sound/MovingSoundInstanceDelegateMixin.java',
      'MovingSoundInstanceDelegate',
      MixinBucket.notApplicable,
      note: 'Client sound.',
    ),
  ];

  /// NeoForge non-Create support code (platform, events, physics callbacks,
  /// gametest, mod entry points): 19 files.
  static const List<MixinEntry> neoforgeSupport = [
    MixinEntry(
      'neoforge/event/ForgeSablePostPhysicsTickEvent.java',
      'ForgeSablePostPhysicsTickEvent',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Port has `SablePostPhysicsTickEvent` (W4).',
    ),
    MixinEntry(
      'neoforge/event/ForgeSablePrePhysicsTickEvent.java',
      'ForgeSablePrePhysicsTickEvent',
      MixinBucket.pluginHook,
      hook: 'server-tick-start-event',
      note: 'Port has `SablePrePhysicsTickEvent` (W4).',
    ),
    MixinEntry(
      'neoforge/event/ForgeSableSubLevelContainerReadyEvent.java',
      'ForgeSableSubLevelContainerReadyEvent',
      MixinBucket.pluginHook,
      hook: 'world-load-event',
      note: 'Port has `SableSubLevelContainerReadyEvent` (W4).',
    ),
    MixinEntry(
      'neoforge/gametest/AssemblyTest.java',
      'AssemblyTest',
      MixinBucket.notApplicable,
      note: 'Game tests; the port tests on the VM.',
    ),
    MixinEntry(
      'neoforge/gametest/PhysicsTest.java',
      'PhysicsTest',
      MixinBucket.notApplicable,
      note: 'Game tests.',
    ),
    MixinEntry(
      'neoforge/gametest/SableTestHelper.java',
      'SableTestHelper',
      MixinBucket.notApplicable,
      note: 'Game test helper.',
    ),
    MixinEntry(
      'neoforge/gametest/TestProgressBar.java',
      'TestProgressBar',
      MixinBucket.notApplicable,
      note: 'Game test boss bar.',
    ),
    MixinEntry(
      'neoforge/mixinhelper/entity/SableInterimCalculation.java',
      'SableInterimCalculation',
      MixinBucket.hostFeature,
      gap: 'fluid-occlusion',
      note: 'Scratch values for the fluid interaction pass.',
    ),
    MixinEntry(
      'neoforge/physics/callback/AbstractBellBlockCallback.java',
      'AbstractBellBlockCallback',
      MixinBucket.pluginHook,
      hook: 'block-collision-callback',
      note: 'Create bell variant; W6 registers it.',
    ),
    MixinEntry(
      'neoforge/physics/callback/BeltBlockCallback.java',
      'BeltBlockCallback',
      MixinBucket.pluginHook,
      hook: 'block-collision-callback',
      note: 'Create belt variant; W6 registers it.',
    ),
    MixinEntry(
      'neoforge/platform/SableAssemblyPlatformImpl.java',
      'SableAssemblyPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction; collapses into the plugin.',
    ),
    MixinEntry(
      'neoforge/platform/SableChunkEventPlatformImpl.java',
      'SableChunkEventPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction; W2 has the chunk host.',
    ),
    MixinEntry(
      'neoforge/platform/SableEventPlatformImpl.java',
      'SableEventPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction.',
    ),
    MixinEntry(
      'neoforge/platform/SableEventPublishPlatformImpl.java',
      'SableEventPublishPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction.',
    ),
    MixinEntry(
      'neoforge/platform/SableLoaderPlatformImpl.java',
      'SableLoaderPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction.',
    ),
    MixinEntry(
      'neoforge/platform/SablePlatformImpl.java',
      'SablePlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction.',
    ),
    MixinEntry(
      'neoforge/platform/SablePlotPlatformImpl.java',
      'SablePlotPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Loader abstraction; W2 has the plot host.',
    ),
    MixinEntry(
      'neoforge/platform/SableSubLevelRenderPlatformImpl.java',
      'SableSubLevelRenderPlatformImpl',
      MixinBucket.notApplicable,
      note: 'Client rendering.',
    ),
    MixinEntry(
      'neoforge/SableNeoForge.java',
      'SableNeoForge',
      MixinBucket.notApplicable,
      note: 'Mod entry point; the plugin entry replaces it.',
    ),
  ];

  /// Create compatibility patches: 156 files (135 mixins plus their helpers and
  /// interfaces). Workstream W6 owns them; they are counted here so the totals
  /// add up.
  static const int createCompatibilityFiles = 156;

  /// Flywheel rendering patches: 19 files, client-only.
  static const int flywheelClientFiles = 19;

  /// All server-side entries, across the four lists.
  static List<MixinEntry> get serverEntries => [
    ...commonServerMixins,
    ...commonMixInterfaces,
    ...commonMixinHelpers,
    ...neoforgeMixins,
    ...neoforgeSupport,
  ];

  /// How many entries are in [bucket].
  static int countOf(MixinBucket bucket) =>
      serverEntries.where((e) => e.bucket == bucket).length;

  /// The gap ids the host-feature entries need, with how many patches each
  /// explains.
  static Map<String, int> get gapsUsed {
    final result = <String, int>{};
    for (final entry in serverEntries) {
      final gap = entry.gap;
      if (gap == null) continue;
      result[gap] = (result[gap] ?? 0) + 1;
    }
    return result;
  }

  /// The hooks the plugin-hook entries use, with how many patches each covers.
  static Map<String, int> get hooksUsed {
    final result = <String, int>{};
    for (final entry in serverEntries) {
      final hook = entry.hook;
      if (hook == null) continue;
      result[hook] = (result[hook] ?? 0) + 1;
    }
    return result;
  }

  /// The entry for [path], or `null`.
  static MixinEntry? byPath(String path) {
    for (final entry in serverEntries) {
      if (entry.path == path) return entry;
    }
    return null;
  }
}
