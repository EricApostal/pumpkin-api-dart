// The host half of the track blocks: the [TrackLevel] over a host `World`, the block entity of a
// track block (`TrackBlockEntityHost`) and the one of a fake track block
// (`FakeTrackBlockEntityHost`). The logic itself lives in `track_block_entity.dart` /
// `fake_track_block.dart`; this file only forwards the host lifecycle and keeps the plugin block
// entities in step with block state changes. It also holds the host half of `TrackBlockItem`:
// `useOn` runs from the `itemUseFirst` event (`useTrackItemOnBlock`), because the host has no
// item behaviour hook.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/perf.dart';
import '../../manifest/manifest.dart';
import '../entity/train_level.dart' show TrainSettings;
import '../station/host_ops.dart' show playCreateSound, sendOverlay;
import '../support/ctag_host.dart';
import '../support/runtime.dart';
import '../util/ctag.dart';
import 'fake_track_block.dart';
import 'i_track_block.dart';
import 'track_block_entity.dart';
import 'track_block_item.dart';
import 'track_level.dart';
import 'track_placement.dart' show ConnectingFrom, TrackPlacement;
import 'track_write_plan.dart';

/// `TrackLevel` over a host [World]. Reads go through [HostBlockGetter]; block writes keep the
/// track and fake track block entities in the store, like Java's `EntityBlock.newBlockEntity`.
final class HostTrackLevel extends TrackLevel {
  final World world;
  final BlockEntityStore store;

  HostTrackLevel(this.world, this.store);

  late final HostBlockGetter _blocks = HostBlockGetter(world);

  /// `level.dimension()`: the dimension key (`minecraft:overworld`), not the world's folder
  /// name. The graph keys its nodes, edges and edge points by it, and it is what goes on the
  /// wire in `create:sync_rail_graph`'s dimension palette; a client resolving a node's dimension
  /// to `minecraft:overworld` cannot match a node stored as `world`.
  @override
  String get dimension => world.getDimension();

  /// The key of the block entity store, which is keyed by `World.getId()` (the folder name).
  String get _worldId => world.getId();

  @override
  BState stateAt(Pos p) => _blocks.stateAt(p);

  @override
  bool isLoaded(Pos p) => _blocks.isLoaded(p);

  @override
  bool isFaceSturdy(Pos p, Direction face) => _blocks.isFaceSturdy(p, face);

  @override
  List<BlockBox> collisionBoxes(Pos p) => _blocks.collisionBoxes(p);

  @override
  bool supportShapeEmpty(Pos p) => _blocks.supportShapeEmpty(p);

  @override
  bool canBeReplaced(Pos p) => _blocks.canBeReplaced(p);

  @override
  bool hasTag(Pos p, String tag) => _blocks.hasTag(p, tag);

  @override
  bool isWater(Pos p) => _blocks.isWater(p);

  @override
  TrackBlockEntity? getTrackBlockEntity(Pos pos) =>
      store.typed<TrackBlockEntityHost>(_worldId, pos.toBlockPos())?.track;

  @override
  FakeTrackBlockEntity? getFakeTrackBlockEntity(Pos pos) =>
      store.typed<FakeTrackBlockEntityHost>(_worldId, pos.toBlockPos())?.entity;

  @override
  TrackLevel? getLevel(String dimension) {
    final other = store.worlds.byId(dimension);
    return other == null ? null : HostTrackLevel(other, store);
  }

  @override
  Future<void> setBlock(Pos pos, BState state) async {
    final stateId = stateIdOf(state);
    final currentId = world.getBlockStateId(pos: pos.toBlockPos());
    if (currentId == stateId) {
      // `LevelChunk.setBlockState` returns null for an unchanged state, and `Level.setBlock`
      // then returns without firing `onPlace`/`onRemove`: a track that is written over itself
      // keeps its block entity.
      return;
    }
    await setBlockState(world, pos, state);
    await _syncBlockEntity(pos, state);
  }

  /// One placement phase in one host call: `world.placeBlocks` writes every block of the batch,
  /// then runs the neighbour, shape and light updates once for the whole batch.
  ///
  /// Java writes a placement as a run of `setBlock`s; here each one used to be a round trip into
  /// the server plus its own neighbour, shape and light update - a long run fills in over
  /// hundreds of calls inside one tick, which is the spike (and the delay) a player sees. The
  /// per-block behaviour is the same as [setBlock]: an unchanged state is skipped (so a track
  /// written over itself keeps its block entity), a track with `turn` gets its block entity and a
  /// block that is no track any more loses it.
  ///
  /// The write also passes [BlockFlagsFlag.skipBlockAddedCallback]: the host then writes the
  /// whole batch without calling back into this plugin for each block. Those callbacks are what
  /// the tick was spent on - each one is a host-to-plugin round trip of tens of milliseconds
  /// while the handler itself takes ~0.06ms (measured with the `[perf]` labels before/after this
  /// change) - and the plugin runs the same placed handling itself, once per written position,
  /// right after the write ([_firePlaced]), so no block is ever left without its block entity.
  @override
  Future<void> setBlocks(List<(Pos, BState)> changes) async {
    final writes = planTrackWrite(
      changes,
      currentStateAt: (pos) => world.getBlockStateId(pos: pos.toBlockPos()),
      idOf: stateIdOf,
    );
    if (writes.isEmpty) return;
    final placements = [
      for (final (pos, _, stateId, _) in writes)
        BlockPlacementChange(pos.toBlockPos(), stateId),
    ];
    // The `placed` event of every written block, which the host is asked not to fire.
    final handling = planPlacedHandling(writes);

    if (!Perf.enabled) {
      await world.placeBlocks(placements, flags: _bulkWriteFlags);
    } else {
      final watch = Stopwatch()..start();
      try {
        await world.placeBlocks(placements, flags: _bulkWriteFlags);
      } finally {
        Perf.record(
          'track.write(${placements.length})',
          watch.elapsedMicroseconds,
        );
      }
    }
    final syncWatch = Perf.enabled ? (Stopwatch()..start()) : null;
    try {
      for (var i = 0; i < writes.length; i++) {
        final (pos, state, _, _) = writes[i];
        final placed = handling[i];
        // Before the sync: the block entity of a track with `turn` is created here, and
        // `TrackBlock.onPlace` / `setPlacedBy` read it.
        if (placed != null) await _firePlaced(placed);
        await _syncBlockEntity(pos, state);
      }
    } finally {
      if (syncWatch != null) {
        Perf.record('track.syncBlockEntities', syncWatch.elapsedMicroseconds);
      }
    }
  }

  /// The flags of one placement write: notify the neighbours and the clients like `setBlock`
  /// does, but do not call back into the plugin per block.
  static const Set<BlockFlagsFlag> _bulkWriteFlags = {
    ...BlockUpdateFlags.normal,
    BlockFlagsFlag.skipBlockAddedCallback,
  };

  /// Runs the `placed` handling of one written block itself, the way the host would have for a
  /// single write (`BlockBehavior.onPlaced`: the block entity of the block and
  /// `TrackBlock.onPlace`). See `track_write_plan.dart` for why the plugin fires it.
  Future<void> _firePlaced(PlacedBlock placed) async {
    final (pos, blockKey, stateIndex, oldStateId) = placed;
    await CustomBlockBehaviors.firePlaced(
      targetWorld: world,
      pos: pos.toBlockPos(),
      blockKey: blockKey,
      stateIndex: stateIndex,
      oldStateId: oldStateId,
    );
  }

  /// Java's `EntityBlock.newBlockEntity` / `onRemove`: a track block keeps its block entity only
  /// while `turn` is set, a fake track block always has one.
  Future<void> _syncBlockEntity(Pos pos, BState state) async {
    final blockPos = pos.toBlockPos();
    if (state.key == fakeTrackKey) {
      if (store.at(_worldId, blockPos) is! FakeTrackBlockEntityHost) {
        store.createAt(world, blockPos, FakeTrackBlockEntityHost.type);
      }
      return;
    }

    if (TrackBlockRegistry.ofState(state) != null && hasBe(state)) {
      if (store.at(_worldId, blockPos) is! TrackBlockEntityHost) {
        store.createAt(world, blockPos, TrackBlockEntityHost.type);
      }
      return;
    }

    final existing = store.at(_worldId, blockPos);
    if (existing is TrackBlockEntityHost ||
        existing is FakeTrackBlockEntityHost) {
      await world.removePluginBlockEntity(blockPos);
    }
  }

  @override
  Future<void> removeBlockEntity(Pos pos) async {
    await world.removePluginBlockEntity(pos.toBlockPos());
  }

  @override
  Future<void> removeBlock(Pos pos) => setBlock(pos, BState.air);

  @override
  Future<bool> destroyBlock(Pos pos, bool dropBlock) =>
      world.breakBlock(pos.toBlockPos(), drop: dropBlock);

  @override
  void scheduleTick(Pos pos, String blockKey, int delay) =>
      world.scheduleBlockTick(
        pos: pos.toBlockPos(),
        delayTicks: delay.clamp(0, 255),
        priority: TickPriority.normal,
      );

  /// The host does not expose the block tick queue's block argument; `hasScheduledTick` answers
  /// for the block currently at the position, which is the block key this code asks about.
  @override
  bool hasScheduledTick(Pos pos, String blockKey) =>
      world.hasScheduledTick(pos: pos.toBlockPos());

  @override
  bool hasNonWaterFluid(Pos pos) {
    final f = world.getFluidState(pos: pos.toBlockPos());
    return f != null && f.fluid != 'minecraft:water';
  }

  @override
  void sendRemoveBlockEntity(Pos pos) {
    final bus = Tr.loaded ? Tr.i.bus : null;
    bus?.sendToTracking('create:remove_te', world, pos.toBlockPos(), {
      'pos': pos,
    });
  }

  @override
  math.Random get random => _random;

  static final math.Random _random = math.Random();

  @override
  void spawnItemEntity(Vec3 pos, String itemKey, int count) {
    if (count <= 0) return;
    unawaited(
      world.dropItem(pos, ItemStack.create(registryKey: itemKey, count: count)),
    );
  }

  @override
  void sendBlockParticles(String blockKey, Vec3 pos) =>
      world.particle(Particle.block, pos, offset: (0.0, 0.0, 0.0), speed: 0);

  @override
  int get maxTrackPlacementLength =>
      TrainSettings.current.maxTrackPlacementLength;

  @override
  bool isInvalidForTrackPaving(String itemKey) =>
      invalidForTrackPaving.contains(itemKey);

  @override
  PaveBlockInfo? paveBlockOf(String itemKey) {
    if (!itemKey.startsWith('create:')) return null;
    final path = itemKey.substring('create:'.length);
    ManifestItem? item;
    for (final i in kItems) {
      if (i.key == path) {
        item = i;
        break;
      }
    }
    final blockKey = item?.blockKey;
    if (blockKey == null) return null;
    final block = manifestBlocksByKey[blockKey];
    if (block == null) return null;
    final key = 'create:$blockKey';
    return PaveBlockInfo(
      blockKey: key,
      defaultState: BState(key, block.defaultState),
      isEntityBlock: kBlockEntityTypes.any(
        (t) => t.validBlocks.contains(blockKey),
      ),
      collisionEmpty: block.noCollision,
      isWall: block.javaClass.contains('WallBlock'),
    );
  }

  @override
  void notifyPortalFailure(Pos pos, String fail, Pos? failPos) {
    final bus = Tr.loaded ? Tr.i.bus : null;
    if (bus == null) return;
    final text = failPos == null
        ? 'Portal track failed: $fail'
        : 'Portal track failed: $fail at $failPos';
    for (final player in bus.roster.players) {
      if (player.getWorld().getId() != _worldId) continue;
      player.sendSystemMessage(
        text: TextComponent.fromLegacyString(input: text),
        overlay: true,
      );
    }
  }
}

/// `AllItemTags.INVALID_FOR_TRACK_PAVING`.
final Set<String> invalidForTrackPaving = {
  for (final tag in tagDefs)
    if (tag.category == 'item' && tag.id == 'create:invalid_for_track_paving')
      for (final e in tag.entries)
        if (!e.isTag) e.id,
};

/// `TrackBlockEntity` on the host: owns the pure [TrackBlockEntity] and forwards the lifecycle.
final class TrackBlockEntityHost extends CreateBlockEntity
    implements TrackBlockEntityEnv {
  static const String type = 'create:track';

  TrackBlockEntityHost(super.worldId, super.pos) {
    lazyTickRate = TrackBlockEntity.lazyTickRate;
  }

  late final TrackBlockEntity track = TrackBlockEntity(pos.toPos(), this);

  @override
  TrackLevel? get level {
    final w = world;
    return w == null ? null : HostTrackLevel(w, store);
  }

  @override
  void notifyUpdate() => sendData();

  @override
  void setChanged() => markDirty();

  @override
  bool get isRemoved => removed;

  @override
  void tick() => unawaited(track.tick());

  @override
  void lazyTick() => unawaited(track.lazyTick());

  @override
  void onRemoved() => unawaited(track.remove());

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    track.read(tag.toCTag(), clientPacket: clientPacket);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final pure = CTag();
    track.write(pure, clientPacket: clientPacket);
    pure.mergeInto(tag);
  }
}

/// `FakeTrackBlockEntity` on the host. The block's `randomTick` is emulated with the vanilla rate
/// (3 in 4096 per tick), because the host does not call random ticks of plugin blocks.
final class FakeTrackBlockEntityHost extends CreateBlockEntity {
  static const String type = 'create:fake_track';

  FakeTrackBlockEntityHost(super.worldId, super.pos);

  late final FakeTrackBlockEntity entity = FakeTrackBlockEntity(pos.toPos(), (
    p,
  ) async {
    final w = world;
    if (w == null) return;
    await HostTrackLevel(w, store).removeBlock(p);
  });

  static final math.Random _random = math.Random();

  @override
  bool get syncsToClient => false;

  @override
  void tick() {
    if (_random.nextInt(4096) >= 3) return;
    unawaited(entity.randomTick());
  }
}

/// The player as `TrackPlacement` and `BezierConnection` use it, over a host [Player].
///
/// `TrackPlacement.tryConnect` reads and writes the player's inventory synchronously, so [load]
/// takes a snapshot of the 36 main slots and the offhand first; [flush] writes the slots the
/// algorithm changed back to the host inventory (the Java code mutates the live `Inventory`).
/// The plain constructor is for the curve item hand-over of `BezierConnection.addItemsToPlayer`,
/// which needs neither the inventory nor the look angle.
final class HostTrackPlacementPlayer implements TrackPlacementPlayer {
  final Player player;

  final TrackInventory? _snapshot;

  /// The stacks of the snapshot when it was taken, to find the slots that changed.
  final List<TrackItemStack?> _before = [];
  TrackItemStack? _offhandBefore;

  HostTrackPlacementPlayer(this.player, [this._snapshot]);

  /// Reads the slots `TrackPlacement` uses (`getNonEquipmentItems()`, the selected slot and the
  /// offhand) into a player the placement can read and write.
  static Future<HostTrackPlacementPlayer> load(Player player) async {
    final inventory = player.getInventory();
    final main = inventory.asInventory();
    // One host call for the 36 slots instead of one per slot.
    final hostItems = main.getAllItems();
    final items = <TrackItemStack?>[];
    for (var slot = 0; slot < 36; slot++) {
      items.add(
        await _readStack(slot < hostItems.length ? hostItems[slot] : null),
      );
    }
    final offhand = await _readStack(inventory.getOffHand());
    final result = HostTrackPlacementPlayer(
      player,
      TrackInventory(items, inventory.getSelectedSlot(), offhand),
    );
    // The placement mutates the snapshot in place (it clears the `connecting_from` component of
    // the selected slot), so the "before" side has to be a copy.
    result._before.addAll(items.map((s) => s?.copy()));
    result._offhandBefore = offhand?.copy();
    return result;
  }

  @override
  Vec3 getLookAngle() => player.lookDirection;

  @override
  bool isCreative() => player.getGamemode() == GameMode.creative;

  @override
  TrackInventory get inventory => _snapshot ?? TrackInventory(const [], 0);

  @override
  void placeItemBackInInventory(String itemKey, int count) {
    if (count <= 0) return;
    unawaited(
      player.give(ItemStack.create(registryKey: itemKey, count: count)),
    );
  }

  /// Writes the slots the placement changed back: the stack count and the removal of the
  /// `connecting_from` component of the selected slot. Unchanged slots are left alone, so the
  /// client is not resynced for them.
  Future<void> flush() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final inventory = player.getInventory();
    final main = inventory.asInventory();
    for (var slot = 0; slot < snapshot.nonEquipmentItems.length; slot++) {
      final now = snapshot.nonEquipmentItems[slot];
      final before = slot < _before.length ? _before[slot] : null;
      if (now == null || now.count <= 0) {
        if (before != null) await main.setItem(slot: slot, item: null);
        continue;
      }
      if (before != null &&
          before.count == now.count &&
          (before.connectingFrom != null) == (now.connectingFrom != null)) {
        continue;
      }
      final stack = main.getItem(slot: slot);
      if (stack == null) continue;
      await stack.setCount(count: now.count);
      if (now.connectingFrom == null) {
        _removeComponent(stack, trackConnectingFromComponent);
      }
      await main.setItem(slot: slot, item: stack);
    }

    final offhand = snapshot.offhand;
    final offhandBefore = _offhandBefore;
    if (offhand == null || offhand.count <= 0) {
      if (offhandBefore != null) await inventory.setOffHand(item: null);
      return;
    }
    if (offhandBefore != null &&
        offhandBefore.count == offhand.count &&
        (offhandBefore.connectingFrom != null) ==
            (offhand.connectingFrom != null)) {
      return;
    }
    final stack = inventory.getOffHand();
    if (stack == null) return;
    await stack.setCount(count: offhand.count);
    if (offhand.connectingFrom == null) {
      _removeComponent(stack, trackConnectingFromComponent);
    }
    await inventory.setOffHand(item: stack);
  }

  static Future<TrackItemStack?> _readStack(ItemStack? stack) async {
    if (stack == null) return null;
    try {
      final itemKey = await stack.getRegistryKey();
      final count = await stack.getCount();
      return TrackItemStack(
        itemKey,
        count,
        connectingFrom: readConnectingFrom(stack),
        extendedCurve: readBoolComponent(stack, trackExtendedCurveComponent),
      );
    } finally {
      // The copies `getItem` / `getAllItems` / `getOffHand` hand out own a host resource.
      stack.dispose();
    }
  }
}

/// `stack.get(AllDataComponents.TRACK_CONNECTING_FROM)`.
ConnectingFrom? readConnectingFrom(ItemStack stack) {
  final bytes = stack.customComponent(trackConnectingFromComponent);
  if (bytes == null) return null;
  try {
    return PacketBuffer.decode(bytes, ConnectingFrom.read);
  } on Object {
    return null;
  }
}

/// A boolean data component (`create:track_extend_curve`, `AllDataComponents.java:151`), `null` when
/// absent.
bool? readBoolComponent(ItemStack stack, String key) {
  final bytes = stack.customComponent(key);
  if (bytes == null) return null;
  try {
    return PacketBuffer.decode(bytes, (r) => r.readBool());
  } on Object {
    return null;
  }
}

/// `stack.remove(component)`, ignoring a component the stack does not have.
void _removeComponent(ItemStack stack, String key) {
  try {
    stack.removeCustomComponent(key);
  } on Object {
    // the stack has no such component: nothing to clear
  }
}

/// `TrackBlockItem.useOn(context)` on the host, through the `itemUseFirst` hook.
///
/// Returns `null` when the click is not for this item (the host goes on and places a single
/// block), else what the host should do with it. The first click on a track selects it (the
/// `connecting_from` component of the held stack); the second click runs
/// [TrackBlockItem.useOn] -> [TrackPlacement.tryConnect], which places the extents of both ends
/// and the curve - the whole run - so the host must not place the clicked block itself.
Future<ItemUseFirstResult?> useTrackItemOnBlock(ItemUseFirstEventData e) async {
  // Java: an off-hand use falls through to `super.useOn`.
  if (e.hand == Hand.left) return null;

  final String itemKey;
  try {
    itemKey = await e.stack.getRegistryKey();
  } on Object {
    return null;
  }
  if (!TrackBlockRegistry.keys.contains(itemKey)) return null;

  final player = e.player;
  final world = player.getWorld();
  final level = HostTrackLevel(world, Tr.i.store);
  final stack = TrackItemStack(
    itemKey,
    await e.stack.getCount(),
    connectingFrom: readConnectingFrom(e.stack),
    extendedCurve: readBoolComponent(e.stack, trackExtendedCurveComponent),
  );
  final pos = e.blockPos.toPos();
  final lookVec = player.lookDirection;

  // The player the placement reads and writes; its slots are written back below, after the
  // placement took the items it needs.
  final placementPlayer = await HostTrackPlacementPlayer.load(player);
  final result = await TrackBlockItem.useOn(
    level: level,
    player: placementPlayer,
    stack: stack,
    clickedPos: pos,
    clickedFace: e.face.toDirection(),
    clickedState: level.stateAt(pos),
    lookVec: lookVec,
    yRot: player.getYaw(),
    sneaking: _isSneaking(player),
  );
  await placementPlayer.flush();

  switch (result.outcome) {
    case TrackUseOutcome.pass:
      // No selection and no track clicked: the host places the single block.
      return null;
    case TrackUseOutcome.selected:
      if (!await _writeConnectingFrom(player, e.hand, stack.connectingFrom!)) {
        // The host refused the component: the click is not a selection, so let the block place.
        return null;
      }
      // `SoundEvents.ITEM_FRAME_ADD_ITEM` at the clicked block.
      world.playCustomSound(
        soundName: 'minecraft:entity.item_frame.add_item',
        category: SoundCategory.blocks,
        pos: pos.center,
        volume: 0.75,
        pitch: 1,
      );
      return ItemUseFirstResult.success;
    case TrackUseOutcome.selectionCleared:
      await clearTrackComponents(player, e.hand);
      _overlay(player, result.message);
      return ItemUseFirstResult.success;
    case TrackUseOutcome.junctionStart:
    case TrackUseOutcome.turnStart:
      _overlay(player, result.message);
      return ItemUseFirstResult.success;
    case TrackUseOutcome.failed:
      return ItemUseFirstResult.consume;
    case TrackUseOutcome.denied:
      _overlay(
        player,
        result.message,
        white: result.message == 'create.track.second_point',
      );
      playCreateSound(world, pos, 'deny');
      return ItemUseFirstResult.consume;
    case TrackUseOutcome.placed:
      // Java clears both components of the main hand stack and plays the block's place sound.
      await clearTrackComponents(player, e.hand);
      world.playCustomSound(
        soundName: 'minecraft:block.metal.place',
        category: SoundCategory.blocks,
        pos: pos.center,
        volume: 1,
        // `soundtype.getPitch() * 0.8F` of the metal sound type.
        pitch: 0.8,
      );
      return ItemUseFirstResult.success;
  }
}

/// `stack.set(AllDataComponents.TRACK_CONNECTING_FROM, value)` on the held stack. The event's
/// stack is a copy, so the component is written to the item in the player's hand. Returns false
/// when the host rejects the component (the data component type or its codec is not registered).
Future<bool> _writeConnectingFrom(Player player, Hand hand, ConnectingFrom value) async {
  final stack = player.getItemInHand(hand: hand);
  if (stack == null) return false;
  try {
    stack.setCustomComponent(
      trackConnectingFromComponent,
      PacketBuffer.encode(value.write),
    );
  } on Object catch (error) {
    Tr.i.log.warn('Cannot store $trackConnectingFromComponent: $error');
    return false;
  }
  await player.setItemInHand(hand: hand, stack: stack);
  return true;
}

/// `stack.remove(TRACK_CONNECTING_FROM)` and `stack.remove(TRACK_EXTENDED_CURVE)` of the stack
/// in [hand] (`TrackBlockItem.useOn` clears the selection of the main hand stack).
Future<void> clearTrackComponents(Player player, Hand hand) async {
  final stack = player.getItemInHand(hand: hand);
  if (stack == null) return;
  for (final key in const [trackConnectingFromComponent, trackExtendedCurveComponent]) {
    try {
      stack.removeCustomComponent(key);
    } on Object {
      // the stack does not have the component
    }
  }
  await player.setItemInHand(hand: hand, stack: stack);
}

bool _isSneaking(Player player) {
  final entity = player.asEntity();
  try {
    return entity.isSneaking();
  } finally {
    entity.dispose();
  }
}

void _overlay(Player player, String? key, {bool white = false}) {
  if (key == null) return;
  sendOverlay(player, trackMessage(key), color: white ? 'f' : 'c');
}
