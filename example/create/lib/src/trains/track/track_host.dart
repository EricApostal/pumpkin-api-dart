// The host half of the track blocks: the [TrackLevel] over a host `World`, the block entity of a
// track block (`TrackBlockEntityHost`) and the one of a fake track block
// (`FakeTrackBlockEntityHost`). The logic itself lives in `track_block_entity.dart` /
// `fake_track_block.dart`; this file only forwards the host lifecycle and keeps the plugin block
// entities in step with block state changes.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/block_entity.dart';
import '../../manifest/manifest.dart';
import '../entity/train_level.dart' show TrainSettings;
import '../support/ctag_host.dart';
import '../support/runtime.dart';
import '../util/ctag.dart';
import 'fake_track_block.dart';
import 'i_track_block.dart';
import 'track_block_entity.dart';
import 'track_level.dart';

/// `TrackLevel` over a host [World]. Reads go through [HostBlockGetter]; block writes keep the
/// track and fake track block entities in the store, like Java's `EntityBlock.newBlockEntity`.
final class HostTrackLevel extends TrackLevel {
  final World world;
  final BlockEntityStore store;

  HostTrackLevel(this.world, this.store);

  late final HostBlockGetter _blocks = HostBlockGetter(world);

  @override
  String get dimension => world.getId();

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
    await setBlockState(world, pos, state);
    _syncBlockEntity(pos, state);
  }

  /// Java's `EntityBlock.newBlockEntity` / `onRemove`: a track block keeps its block entity only
  /// while `turn` is set, a fake track block always has one.
  void _syncBlockEntity(Pos pos, BState state) {
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
      world.removePluginBlockEntity(blockPos);
    }
  }

  @override
  void removeBlockEntity(Pos pos) =>
      world.removePluginBlockEntity(pos.toBlockPos());

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

  /// The host does not expose the block tick queue; scheduling the same tick twice is harmless
  /// (`TrackBlock.onPlace` only uses this to avoid a duplicate one-tick delay).
  @override
  bool hasScheduledTick(Pos pos, String blockKey) => false;

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

/// The player as `TrackPlacement` and `BezierConnection` use it, over a host [Player]. Only the
/// inventory hand-over and the creative flag are used by the curve removal; the host exposes no
/// look angle, so [getLookAngle] is the zero vector (the placement packets carry the look angle
/// themselves).
final class HostTrackPlacementPlayer implements TrackPlacementPlayer {
  final Player player;

  HostTrackPlacementPlayer(this.player);

  @override
  Vec3 getLookAngle() => vec3Zero;

  @override
  bool isCreative() => player.getGamemode() == GameMode.creative;

  @override
  TrackInventory get inventory => TrackInventory(const [], 0);

  @override
  void placeItemBackInInventory(String itemKey, int count) {
    if (count <= 0) return;
    unawaited(
      player.give(ItemStack.create(registryKey: itemKey, count: count)),
    );
  }
}
