// The runtime wiring of Offroad: the block entity store the block callbacks need,
// the per-world multi-mining managers, and the link between a borehead bearing
// and the contraption it drives.
//
// Java gets the controller of a rock cutting wheel from the contraption entity:
//
// ```java
// final BlockPos controllerPos = ((BoreheadContraptionEntity) context.contraption.entity).getControllerPos();
// final BlockEntity be = context.world.getBlockEntity(controllerPos);
// if (be instanceof BoreheadBearingBlockEntity bhbe) { ... }
// ```
//
// The port's `Contraption.entity` is only a [ContraptionEntityHandle] (id, uuid,
// position), with no controller position, so the bearing registers itself here
// when it assembles or attaches and the actor looks it up by contraption
// identity. Same pairing, one indirection.
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' as math;

import 'package:create/create.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/common/host_bridge.dart' show BlockHelper, PosToHost;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show BlockEntitySubLevelActor, SableLevel, SubLevelHelper;

import '../handlers/multi_mining.dart';
import '../network/borehead_sync_packet.dart';

/// What a rock cutting wheel needs of the bearing that drives it
/// (`BoreheadBearingBlockEntity`).
abstract interface class BoreheadMiningController {
  /// `isStalled()`.
  bool get isStalled;

  /// `getSpeed()`.
  double get speed;

  /// `requestNewIndexAndIncrement(context)` (`BoreheadBearingBlockEntity.java:538`).
  int requestNewIndexAndIncrement({required bool isRockCuttingWheel});

  /// `updatePosition(index, originPosition)` (`BoreheadBearingBlockEntity.java:549`).
  void updatePosition(int index, Vec3 originPosition);
}

/// `MultiMiningServerManager` over one host world.
final class HostMultiMiningLevel implements MultiMiningLevel {
  HostMultiMiningLevel(this.world);

  final World world;

  /// `state.getDestroySpeed(level, pos)`; -1 for a block that cannot be broken.
  @override
  double hardnessAt(Pos pos) =>
      BlockRegistry.stateFromId(world.getBlockStateId(pos: pos.toBlockPos()))?.hardness ?? 0;

  @override
  String blockKeyAt(Pos pos) =>
      BlockRegistry.stateFromId(world.getBlockStateId(pos: pos.toBlockPos()))?.blockName ?? 'minecraft:air';

  /// `BlockBreakingKineticBlockEntity.isBreakable(state, hardness)` and a
  /// non-empty collision shape (`BoreheadBearingBlockEntity.java:205`).
  ///
  /// TODO(parity): Java also requires `!state.getCollisionShape(level, pos).isEmpty()`,
  /// so a rock cutter does not mine a block it can pass through (flowers, torches).
  /// The host has no collision-shape query; `isSolid` is the nearest stand-in and
  /// is stricter for slabs and stairs.
  @override
  bool isBreakableAt(Pos pos) {
    final state = BlockRegistry.stateFromId(world.getBlockStateId(pos: pos.toBlockPos()));
    if (state == null) return false;
    if (state.isAir || state.isLiquid || state.hardness == -1) return false;
    if (Tags.block(state.blockName, 'create:non_breakable')) return false;
    return state.isSolid;
  }

  /// `BlockHelper.destroyBlock(level, pos, 1, consumer)`: the drops of [pos],
  /// with the block removed.
  ///
  /// TODO(parity): the drops come back as item key and count, so a drop stack
  /// that carries NBT (a spawner, a shulker box) loses it on the way through
  /// `MultiMiningSupplier.acceptItem`. Block drops rarely carry components; the
  /// Java hands the `ItemStack` itself to the supplier.
  @override
  Future<List<MinedDrop>> destroyBlock(Pos pos) async {
    final drops = <MinedDrop>[];
    await BlockHelper.destroyBlockWith(world, pos, 1, (stack) async {
      final count = await stack.getCount();
      if (count <= 0) return;
      drops.add(MinedDrop(await stack.getRegistryKey(), count));
      stack.dispose();
    });
    return drops;
  }

  /// `Block.popResource(level, pos, stack)`.
  @override
  Future<void> popResource(Pos pos, MinedDrop drop) async {
    await world.dropItem(pos.center, ItemStacks.plain(drop.itemKey, count: drop.count));
  }
}

/// `SableLevel` over a host world (the same adapter Simulated and Aeronautics
/// use; the host does not expose the build height, so the vanilla limits stand).
final class OffroadSableLevel implements SableLevel {
  OffroadSableLevel(this.world);

  final World world;

  /// `Level.dimension().identifier().toString()`: the dimension key (`minecraft:overworld`), not
  /// the world id (`World.getId()`, the folder name `world`). See `SableLevel.dimensionId`.
  @override
  String get dimensionId => world.getDimension();

  @override
  bool get isClientSide => false;

  @override
  int get minY => -64;

  @override
  int get maxY => 319;

  @override
  int get gameTime => 0;

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  @override
  String? biomeAt(int x, int y, int z) => null;
}

/// The Offroad state of one world.
final class OffroadWorldRuntime {
  OffroadWorldRuntime(this.world, {required int Function() breakerIds, math.Random? random})
    : level = HostMultiMiningLevel(world),
      sableLevel = OffroadSableLevel(world),
      manager = MultiMiningServerManager(breakerIds, random: random);

  final World world;

  /// The level the manager reads.
  final HostMultiMiningLevel level;

  /// The sub-level view, for the wheel mount's suspension.
  final OffroadSableLevel sableLevel;

  /// The actors already registered in a plot.
  final Set<String> registeredActors = {};

  /// `MultiMiningServerManager.get(level)`: one per level.
  final MultiMiningServerManager manager;

  /// The bearing that drives each assembled contraption, by contraption identity.
  final Map<Object, BoreheadMiningController> controllers = {};
}

/// The Offroad runtime, keyed by world id.
abstract final class OffroadHooks {
  static final Map<String, OffroadWorldRuntime> _runtimes = {};

  /// The block entity store, for the block callbacks and the actors that need a
  /// block entity (`BlockBehavior` has no store of its own). Set by the module.
  static BlockEntityStore? store;

  /// The next id for a multi-mining breaking id; Create's `NEXT_BREAKER_ID`.
  static int Function() breakerIds = () => 0;

  /// The runtime of [world], created on first use.
  static OffroadWorldRuntime of(World world) =>
      _runtimes.putIfAbsent(world.getId(), () => OffroadWorldRuntime(world, breakerIds: breakerIds));

  /// The runtime of the world with [worldId], `null` when it never ticked.
  static OffroadWorldRuntime? byId(String worldId) => _runtimes[worldId];

  /// The sub-level view of [worldId], `null` before the world's first tick.
  ///
  /// A contraption actor only knows its world id; the level view is the one the
  /// world's runtime built (`tickWorld` creates it before any actor ticks).
  static SableLevel? sableLevelOf(String worldId) => _runtimes[worldId]?.sableLevel;

  /// Forgets every runtime (plugin unload).
  static void clear() {
    _runtimes.clear();
    breakerIds = () => 0;
  }

  /// Puts every wheel mount into the plot that contains it, so the physics
  /// system calls `sable$physicsTick` (`ServerLevelPlot.actorAt` is a host gap,
  /// as in `AeronauticsHooks`).
  static void _registerActors(OffroadWorldRuntime runtime) {
    final store = OffroadHooks.store;
    if (store == null) return;
    for (final candidate in store.inWorld(runtime.world.getId())) {
      if (candidate is! BlockEntitySubLevelActor) continue;
      final key = '${candidate.worldId}:${candidate.pos.x},${candidate.pos.y},${candidate.pos.z}';
      if (!runtime.registeredActors.add(key)) continue;

      final pos = (candidate.pos.x, candidate.pos.y, candidate.pos.z);
      final subLevel = SubLevelHelper.getContaining(runtime.sableLevel, pos);
      if (subLevel == null) {
        runtime.registeredActors.remove(key);
        continue;
      }
      subLevel.getPlot().blockEntityActors[pos] = candidate as BlockEntitySubLevelActor;
    }
  }

  /// Forgets an actor that unloaded.
  static void forgetActor(String worldId, BlockPos pos) =>
      _runtimes[worldId]?.registeredActors.remove('$worldId:${pos.x},${pos.y},${pos.z}');

  /// The controller of [contraption], `null` when no bearing assembled it.
  static BoreheadMiningController? controllerOf(Object? contraption) =>
      contraption == null ? null : _runtimes.values.map((r) => r.controllers[contraption]).nonNulls.firstOrNull;

  /// `BoreheadBearingBlockEntity.initializeContraption` / `disassemble`: pairs a
  /// bearing with the contraption it drives, or forgets it.
  static void bind(World world, Object contraption, BoreheadMiningController controller) =>
      of(world).controllers[contraption] = controller;

  static void unbind(World world, Object contraption) => of(world).controllers.remove(contraption);

  /// One server tick of [world]: advances the mining of every position the
  /// bearings collected this tick (`MultiMiningServerManager.tick`) and sends
  /// the sync payloads to the players tracking the supplier.
  ///
  /// [players] is `WorldTick.playersInWorld`, the players of the ticking world
  /// (`Server.getPlayersInWorld`).
  ///
  /// TODO(parity): Java sends the payload to the players tracking the
  /// `BlockEntity` that supplies the position (`ServerPlayer.send` through the
  /// `PlayerTracking` of the bearing); the host has no per-block-entity tracking
  /// set, so the payload goes to every player in the world. The packet is small
  /// and idempotent (an absolute progress per position).
  static Future<void> tickWorld(World world, {List<Player> players = const []}) async {
    final runtime = of(world);

    _registerActors(runtime);

    final packets = await runtime.manager.tick(runtime.level);
    for (final packet in packets) {
      final bytes = MultiMiningSyncPacket.codec.encode(packet);
      for (final player in players) {
        // Bedrock players have no custom payloads (`CreateNetwork._send`).
        final java = player.asJava();
        if (java == null) continue;
        try {
          await java.sendCustomPayload(channel: MultiMiningSyncPacket.channel, data: bytes);
        } finally {
          java.dispose();
        }
      }
    }
  }
}
