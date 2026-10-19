// The host side shared by the conveyance blocks: the module context, the services of the
// other modules (kinetics, configs, payload bus, sounds, advancements), the last block click
// of each player (the placement context the host does not pass on) and small helpers.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart';
import '../api/blocks.dart';
import '../api/config.dart';
import '../api/kinetics.dart';
import '../api/payloads.dart';
import '../api/sounds.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/module.dart';
import 'chain/chain_conveyor_port.dart';
import 'items/item_data.dart';

/// The last block click of a player (`playerUseBlock`): what the host's `placed` event does not
/// tell (`BlockPlaceContext`).
final class ClickContext {
  final Pos clickedPos;
  final d.Direction face;

  /// Hit location inside the clicked block, 0..1.
  final (double, double, double) cursor;
  final bool sneaking;
  final Hand hand;
  final int tick;

  const ClickContext(
    this.clickedPos,
    this.face,
    this.cursor,
    this.sneaking,
    this.hand,
    this.tick,
  );

  /// Whether this click placed a block at [pos] (the neighbour of the clicked block, or the
  /// clicked block itself when it was replaced).
  bool placedAt(Pos pos) =>
      clickedPos.relative(face) == pos || clickedPos == pos;
}

/// The runtime of the conveyance module (set in `onLoad`; blocks, block entities and
/// behaviours reach it through [ConveyanceRuntime.i]).
final class ConveyanceRuntime {
  static ConveyanceRuntime? _instance;

  static ConveyanceRuntime get i =>
      _instance ?? (throw StateError('The conveyance module is not loaded'));

  static bool get loaded => _instance != null;

  final CreateContext ctx;

  /// The blocks of the module by key (`create:belt`).
  final Map<String, CreateBlock> blocks = {};

  /// Last block click by player uuid.
  final Map<String, ClickContext> clicks = {};

  int serverTick = 0;

  ConveyanceRuntime(this.ctx) {
    _instance = this;
    // The host's placement event does not carry the click (the `BlockPlaceContext`), so the last
    // block click of each player is kept for the blocks whose placement depends on it.
    ctx.host.intercept(Events.playerUseBlock, (server, e) async {
      clicks[e.player.uuidString] = ClickContext(
        e.blockPos.toPos(),
        d.Direction.values[e.face.index],
        e.cursor,
        e.sneaking,
        e.hand,
        serverTick,
      );
      return e;
    });
    ctx.listen(Events.serverTickStart, (server, _) => serverTick++);
  }

  void dispose() {
    if (identical(_instance, this)) _instance = null;
  }

  Logger get log => ctx.log;
  BlockEntityStore get store => ctx.blockEntities;

  KineticNetworkService? get kinetics =>
      ctx.services.find<KineticNetworkService>();
  CreateConfigs? get configs => ctx.services.find<CreateConfigs>();
  PayloadBus? get bus => ctx.services.find<PayloadBus>();
  CreateSounds? get sounds => ctx.services.find<CreateSounds>();
  CreateAdvancements? get advancements =>
      ctx.services.find<CreateAdvancements>();

  /// The package ports of the chain conveyors (provided by this module).
  ChainConveyorPortRegistry get chainPorts =>
      ctx.services.require<ChainConveyorPortRegistry>();

  // -- Config ----------------------------------------------------------------------------------

  int get maxBeltLength => configs?.server.kinetics.maxBeltLength.value ?? 20;
  int get maxChainConveyorLength =>
      configs?.server.kinetics.maxChainConveyorLength.value ?? 32;
  int get maxEjectorDistance =>
      configs?.server.kinetics.maxEjectorDistance.value ?? 32;
  int get ejectorScanInterval =>
      configs?.server.kinetics.ejectorScanInterval.value ?? 120;
  int get fanBlockCheckRate =>
      configs?.server.kinetics.fanBlockCheckRate.value ?? 30;
  int get defaultExtractionTimer =>
      configs?.server.logistics.defaultExtractionTimer.value ?? 8;
  int get vaultCapacity => configs?.server.logistics.vaultCapacity.value ?? 20;
  int get chainConveyorCapacity =>
      configs?.server.logistics.chainConveyorCapacity.value ?? 20;
  int get brassTunnelTimer =>
      configs?.server.logistics.brassTunnelTimer.value ?? 10;

  // -- World access ----------------------------------------------------------------------------

  World? worldOf(String worldId) => ctx.worlds.byId(worldId);

  /// The block state at [pos] of world [worldId] (air when the world is gone).
  BState stateAt(String worldId, Pos pos) {
    final w = worldOf(worldId);
    if (w == null) return BState.air;
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos.toBlockPos()));
  }

  /// The block entity at [pos], or `null`.
  CreateBlockEntity? beAt(String worldId, Pos pos) =>
      store.at(worldId, pos.toBlockPos());

  T? typedAt<T extends CreateBlockEntity>(String worldId, Pos pos) =>
      store.typed<T>(worldId, pos.toBlockPos());

  /// `BlockEntityBehaviour.get(world, pos, type)`.
  T? behaviourAt<T extends BlockEntityBehaviour>(String worldId, Pos pos) =>
      beAt(worldId, pos)?.getBehaviour<T>();

  bool posLoaded(String worldId, Pos pos) =>
      worldOf(worldId)?.isLoaded(pos: pos.toBlockPos()) ?? false;

  /// The click of [playerId] that placed a block at [pos] (consumed), or `null`.
  ClickContext? clickFor(Uuid? playerId, Pos pos) {
    if (playerId == null) return null;
    final c = clicks[playerId.asString];
    if (c == null || !c.placedAt(pos) || serverTick - c.tick > 2) return null;
    clicks.remove(playerId.asString);
    return c;
  }

  /// A player by uuid, or `null`.
  Player? playerOf(Server server, Uuid? id) =>
      id == null ? null : server.getPlayerByUuid(id: id);

  // -- Effects ---------------------------------------------------------------------------------

  /// Plays a Create sound by its `AllSoundEvents` name.
  void playCreateSound(
    World world,
    Pos pos,
    String name, {
    double volume = 1,
    double pitch = 1,
  }) {
    try {
      sounds?.playAtBlock(world, pos, name, volume: volume, pitch: pitch);
    } on Object catch (e) {
      log.debug('Sound $name failed: $e');
    }
  }

  /// Plays a sound event at the block centre.
  void playSound(
    World world,
    Pos pos,
    String sound, {
    double volume = 1,
    double pitch = 1,
    SoundCategory category = SoundCategory.blocks,
  }) {
    world.playCustomSound(
      soundName: sound,
      category: category,
      pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      volume: volume,
      pitch: pitch,
    );
  }

  /// Awards an advancement; failures are logged.
  Future<void> award(Player player, String id) async {
    final a = advancements;
    if (a == null) return;
    try {
      await a.award(player, id);
    } on Object catch (e) {
      log.debug('Advancement $id failed: $e');
    }
  }

  /// Runs [body] without awaiting; errors are logged with [what].
  void fire(String what, FutureOr<void> Function() body) {
    unawaited(
      Future<void>.sync(body).catchError((Object e, StackTrace s) {
        log.error('$what failed', error: e, stackTrace: s);
      }),
    );
  }

  /// Breaks the block at [pos] like a machine would (`level.destroyBlock(pos, true)`).
  void destroyBlock(String worldId, Pos pos, {bool drop = true}) {
    final w = worldOf(worldId);
    if (w == null) return;
    fire(
      'Breaking the block at $pos',
      () => w.breakBlock(pos.toBlockPos(), drop: drop),
    );
  }

  /// Writes [state] at [pos] (flags default to a normal block change).
  Future<void> setState(
    String worldId,
    Pos pos,
    BState state, {
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) async {
    final w = worldOf(worldId);
    if (w == null) return;
    await setBlockState(w, pos, state, flags: flags);
  }

  /// Fire-and-forget [setState].
  void setStateLater(
    String worldId,
    Pos pos,
    BState state, {
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) => fire(
    'Setting the state at $pos',
    () => setState(worldId, pos, state, flags: flags),
  );
}

/// `ProperWaterloggedBlock.withWater`: [state] waterlogged when [pos] holds a water source.
BState withWater(World world, BState state, Pos pos) {
  if (!state.has('waterlogged')) return state;
  return state.setFlag('waterlogged', replacesWater(world, pos));
}

/// An unsigned UUID as the int array of `UUIDUtil.CODEC`.
List<int> uuidToIntArray(Uuid id) => [
  (id.high >> 32).toSigned(32),
  id.high.toSigned(32),
  (id.low >> 32).toSigned(32),
  id.low.toSigned(32),
];

Uuid uuidFromIntArray(List<int> a) {
  int part(int hi, int lo) => ((hi & 0xffffffff) << 32) | (lo & 0xffffffff);
  return Uuid(high: part(a[0], a[1]), low: part(a[2], a[3]));
}

/// `Containers.dropItemStack` position helper: the centre of a block plus an offset.
(double, double, double) blockCenter(Pos p, [double dy = 0]) =>
    (p.$1 + 0.5, p.$2 + 0.5 + dy, p.$3 + 0.5);

/// A random double generator shared by the blocks.
final math.Random sharedRandom = math.Random();

/// The item key of a host stack, `null` when it is empty.
Future<String?> keyOfHeld(ItemStack? stack) async {
  if (stack == null) return null;
  if (await stack.getCount() <= 0) return null;
  return stack.getRegistryKey();
}

/// Whether [key] is a held item that is empty air.
bool isAir(String? key) => key == null || key == airKey;
