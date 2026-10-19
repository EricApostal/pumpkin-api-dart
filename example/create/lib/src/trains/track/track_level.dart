// The world as the pure track logic sees it, and the small models around it (pure).
//
// Java passes a `Level` / `ServerLevel` / `LevelAccessor` everywhere. Here reads go through
// [TrackLevel] (a [BlockGetter] plus the track block entities and the other dimensions), and the
// writes that Java does in one statement are `Future`s, because the host changes blocks
// asynchronously: the pure code awaits them in the order Java runs them. [HostTrackLevel]
// (`track_host.dart`) is the host implementation, [MemoryTrackLevel] the one tests use.
import 'dart:math' as math;

import '../../common/common.dart';
import '../../api/block_state.dart';
import 'bezier_track_point_location.dart';
import 'fake_track_block.dart';
import 'track_block_entity.dart';
import 'track_placement.dart' show ConnectingFrom;

/// `BlockStateProperties.WATERLOGGED` property name.
const String waterloggedProperty = 'waterlogged';

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

  /// `level.removeBlockEntity(pos)`.
  void removeBlockEntity(Pos pos);

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
