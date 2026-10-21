// The world as the pure track logic sees it, and the small models around it (pure).
//
// Java passes a `Level` / `ServerLevel` / `LevelAccessor` everywhere. Here reads go through
// [TrackLevel] (a [BlockGetter] plus the track block entities and the other dimensions), and the
// writes that Java does in one statement are `Future`s, because the host changes blocks
// asynchronously: the pure code awaits them in the order Java runs them. [HostTrackLevel]
// (`track_host.dart`) is the host implementation, [MemoryTrackLevel] the one tests use.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../../common/common.dart';
import '../../api/block_state.dart';
import 'bezier_track_point_location.dart';
import 'fake_track_block.dart';
import 'track_block_entity.dart';
import 'track_placement.dart' show ConnectingFrom;

/// `BlockStateProperties.WATERLOGGED` property name.
const String waterloggedProperty = 'waterlogged';

/// `AllDataComponents.TRACK_CONNECTING_FROM`: the track end a held track item connects from.
const String trackConnectingFromComponent = 'create:track_connecting_from';

/// `AllDataComponents.TRACK_EXTENDED_CURVE`: the client's "maximise turn" hint for the next
/// placement (`PlaceExtendedCurvePacket`).
const String trackExtendedCurveComponent = 'create:track_extend_curve';

/// `ProperWaterloggedBlock.withWater(level, state, pos)`: waterlogged blocks placed in a water
/// source become waterlogged, air placed in water becomes water.
BState? withWater(BlockGetter level, BState? state, Pos pos) {
  if (state == null) return null;
  final water = level.isWater(pos);
  if (state.isAir) return water ? const BState('minecraft:water', {'level': '0'}) : state;
  if (!state.has(waterloggedProperty)) return state;
  return state.setFlag(waterloggedProperty, water);
}

/// What a pave item stands for (`BlockItem.getBlock()` and its default state): see
/// `TrackPaver`.
final class PaveBlockInfo {
  /// The block key (`minecraft:stone`).
  final String blockKey;

  /// The default state.
  final BState defaultState;

  /// `block instanceof EntityBlock`.
  final bool isEntityBlock;

  /// `block.defaultBlockState().getCollisionShape(level, pos).isEmpty()`.
  final bool collisionEmpty;

  /// `block instanceof WallBlock`.
  final bool isWall;

  const PaveBlockInfo({
    required this.blockKey,
    required this.defaultState,
    this.isEntityBlock = false,
    this.collisionEmpty = false,
    this.isWall = false,
  });
}

/// The world seen by the track logic.
abstract class TrackLevel extends BlockGetter {
  /// `level.dimension()`: the world id.
  String get dimension;

  /// `level.getMinY()` and the highest buildable y.
  int get minBuildY => -64;
  int get maxBuildY => 319;

  /// `level.isClientSide()`: always `false` on the server.
  bool get isClientSide => false;

  /// The loaded track block entity at [pos] (`level.getBlockEntity(pos) instanceof TrackBlockEntity`).
  TrackBlockEntity? getTrackBlockEntity(Pos pos);

  /// The fake track block entity at [pos].
  FakeTrackBlockEntity? getFakeTrackBlockEntity(Pos pos);

  /// `server.getLevel(dimension)`: another dimension, `null` when it does not exist.
  TrackLevel? getLevel(String dimension);

  /// `level.setBlock(pos, state, Block.UPDATE_ALL)`. Block entities of track blocks follow the
  /// state like Java's `newBlockEntity` does (`HAS_BE`).
  Future<void> setBlock(Pos pos, BState state);

  /// `level.setBlockAndUpdate(pos, state)`.
  Future<void> setBlockAndUpdate(Pos pos, BState state) => setBlock(pos, state);

  /// `level.setBlock(pos, state, Block.UPDATE_ALL)` for a whole run of positions: one call for
  /// the batch instead of one per block.
  ///
  /// Java writes a placement as a straight run of `setBlock`s because a level write is a memory
  /// store. Here every `setBlock` is a host call, and one placement writes the straights of both
  /// ends, the curve and the fake tracks - a long run is hundreds of round trips inside a single
  /// tick, which is the TPS spike a player sees while a track fills in. The host writes a batch
  /// in one call (`World.placeBlocks`: all blocks first, then the neighbour, shape and light
  /// updates once).
  ///
  /// The changes are applied in order and a later entry for the same position wins, so a caller
  /// can collect the writes of one phase and flush them together. The default implementation is
  /// the per-block loop, so a level that does not care (tests) behaves exactly as before.
  Future<void> setBlocks(List<(Pos, BState)> changes) async {
    for (final (pos, state) in changes) {
      await setBlock(pos, state);
    }
  }

  /// `level.removeBlockEntity(pos)`. Awaits the host: removing the entity fires its unload event.
  Future<void> removeBlockEntity(Pos pos);

  /// `level.removeBlock(pos, false)`.
  Future<void> removeBlock(Pos pos);

  /// `level.destroyBlock(pos, dropBlock)`.
  Future<bool> destroyBlock(Pos pos, bool dropBlock);

  /// `level.scheduleTick(pos, block, delay)`.
  void scheduleTick(Pos pos, String blockKey, int delay);

  /// `level.getBlockTicks().hasScheduledTick(pos, block)`.
  bool hasScheduledTick(Pos pos, String blockKey);

  /// `!fluidState.isEmpty() && !fluidState.isSourceOfType(WATER)` at [pos].
  bool hasNonWaterFluid(Pos pos);

  /// `NetworkHelper.sendToClientsTrackingChunk(level, chunk, new RemoveBlockEntityPacket(pos))`.
  void sendRemoveBlockEntity(Pos pos);

  /// `level.getRandom()`.
  math.Random get random;

  /// `server.getGameRules().get(GameRules.BLOCK_DROPS)`.
  bool get blockDropsEnabled => true;

  /// `new ItemEntity(level, x, y, z, stack)` + `setDefaultPickUpDelay` + `addFreshEntity`.
  void spawnItemEntity(Vec3 pos, String itemKey, int count);

  /// `slevel.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, block.defaultBlockState()), x, y, z, 1, 0, 0, 0, 0)`.
  void sendBlockParticles(String blockKey, Vec3 pos);

  /// `AllConfigs.server().trains.maxTrackPlacementLength.get()`.
  int get maxTrackPlacementLength => 32;

  /// `AllItemTags.INVALID_FOR_TRACK_PAVING.matches(item)`.
  bool isInvalidForTrackPaving(String itemKey) => false;

  /// The block item [itemKey] as pave material, `null` when it is no block item.
  PaveBlockInfo? paveBlockOf(String itemKey);

  /// `level.getNearestPlayer(...)`'s `sendSystemMessage` of `portal_track.failed` + the reason.
  void notifyPortalFailure(Pos pos, String fail, Pos? failPos) {}
}

/// An item stack as the track code sees it: the item, the count and the track data components of
/// the stack (`create:track_connecting_from`, `create:track_extend_curve`,
/// `create:track_targeting_item_*`).
final class TrackItemStack {
  String itemKey;
  int count;

  /// `AllDataComponents.TRACK_CONNECTING_FROM`.
  ConnectingFrom? connectingFrom;

  /// `AllDataComponents.TRACK_EXTENDED_CURVE`.
  bool? extendedCurve;

  /// `AllDataComponents.TRACK_TARGETING_ITEM_SELECTED_POS`.
  Pos? selectedPos;

  /// `AllDataComponents.TRACK_TARGETING_ITEM_SELECTED_DIRECTION`.
  bool? selectedDirection;

  /// `AllDataComponents.TRACK_TARGETING_ITEM_BEZIER`.
  BezierTrackPointLocation? selectedBezier;

  TrackItemStack(
    this.itemKey,
    this.count, {
    this.connectingFrom,
    this.extendedCurve,
    this.selectedPos,
    this.selectedDirection,
    this.selectedBezier,
  });

  bool get isEmpty => count <= 0 || itemKey == 'minecraft:air';

  /// `copyWithCount(count)`: keeps the components.
  TrackItemStack copyWithCount(int count) => TrackItemStack(
    itemKey,
    count,
    connectingFrom: connectingFrom,
    extendedCurve: extendedCurve,
    selectedPos: selectedPos,
    selectedDirection: selectedDirection,
    selectedBezier: selectedBezier,
  );

  TrackItemStack copy() => copyWithCount(count);

  @override
  String toString() => 'TrackItemStack($itemKey x$count)';
}

/// The slots of a player's inventory that `TrackPlacement.tryConnect` reads and writes:
/// `getNonEquipmentItems()` (36 slots), the selected hotbar slot and the offhand.
final class TrackInventory {
  final List<TrackItemStack?> nonEquipmentItems;
  int selectedSlot;
  TrackItemStack? offhand;

  TrackInventory(this.nonEquipmentItems, this.selectedSlot, [this.offhand]);

  /// The main hand stack (`player.getMainHandItem()`).
  TrackItemStack? get mainHand => selectedSlot < nonEquipmentItems.length ? nonEquipmentItems[selectedSlot] : null;
}

/// The player as `TrackPlacement` and `BezierConnection` use it.
abstract class TrackPlacementPlayer {
  /// `player.getLookAngle()`.
  Vec3 getLookAngle();

  /// `player.isCreative()`.
  bool isCreative();

  /// The inventory snapshot; changes made by the algorithm are written back by the host.
  TrackInventory get inventory;

  /// `inv.placeItemBackInInventory(new ItemStack(item, count))`.
  void placeItemBackInInventory(String itemKey, int count);
}

/// A [TrackLevel] over a map of block states, for tests and for simulating a placement: blocks
/// absent from [blocks] are air, tracks have no block entity, and no block is water, tagged or
/// sturdy.
final class MemoryTrackLevel extends TrackLevel {
  final Map<Pos, BState> blocks;
  final math.Random _random;

  MemoryTrackLevel([Map<Pos, BState>? blocks, math.Random? random])
    : blocks = blocks ?? <Pos, BState>{},
      _random = random ?? math.Random(0);

  /// Level calls a placement made, counted so a test can see the cost of one placement: every
  /// `stateAt` / `canBeReplaced` / `hasTag` / `isWater` is one host call in game, and every entry
  /// of [writeCounts] is one `setBlock` (three host calls: state, write, shape invalidation) or
  /// one batched [setBlocks] (a single `World.placeBlocks` call). A track placement used to make
  /// one of each per block; the counts are what the TPS spike was made of.
  int readCount = 0;
  final List<int> writeCounts = [];

  @override
  String get dimension => 'minecraft:overworld';

  @override
  BState stateAt(Pos p) {
    readCount++;
    return blocks[p] ?? BState.air;
  }

  @override
  bool isLoaded(Pos p) {
    readCount++;
    return true;
  }

  @override
  bool isFaceSturdy(Pos p, Direction face) {
    readCount++;
    return false;
  }

  @override
  List<BlockBox> collisionBoxes(Pos p) {
    readCount++;
    return const [];
  }

  @override
  bool supportShapeEmpty(Pos p) {
    readCount++;
    return true;
  }

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) {
    readCount++;
    return false;
  }

  @override
  bool isWater(Pos p) {
    readCount++;
    return false;
  }

  @override
  TrackBlockEntity? getTrackBlockEntity(Pos pos) => null;

  @override
  FakeTrackBlockEntity? getFakeTrackBlockEntity(Pos pos) => null;

  @override
  TrackLevel? getLevel(String dimension) => this;

  @override
  Future<void> setBlock(Pos pos, BState state) async {
    writeCounts.add(1);
    blocks[pos] = state;
  }

  /// One batched write: the count entry says how many blocks it carried.
  @override
  Future<void> setBlocks(List<(Pos, BState)> changes) async {
    writeCounts.add(changes.length);
    for (final (pos, state) in changes) {
      blocks[pos] = state;
    }
  }

  @override
  Future<void> removeBlockEntity(Pos pos) async {}

  @override
  Future<void> removeBlock(Pos pos) async => blocks[pos] = BState.air;

  @override
  Future<bool> destroyBlock(Pos pos, bool dropBlock) async {
    blocks[pos] = BState.air;
    return true;
  }

  @override
  void scheduleTick(Pos pos, String blockKey, int delay) {}

  @override
  bool hasScheduledTick(Pos pos, String blockKey) => false;

  @override
  bool hasNonWaterFluid(Pos pos) => false;

  @override
  void sendRemoveBlockEntity(Pos pos) {}

  @override
  math.Random get random => _random;

  @override
  void spawnItemEntity(Vec3 pos, String itemKey, int count) {}

  @override
  void sendBlockParticles(String blockKey, Vec3 pos) {}

  @override
  PaveBlockInfo? paveBlockOf(String itemKey) => null;
}
