// `RollerBlock` and `RollerBlockEntity`: the mechanical roller. The block entity keeps the filter
// material and the rolling mode, and shares them with the rollers next to it.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart'
    show BState, HostBlockGetter, setBlockState, toDirection;
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../../mounted/minecart_contraption_item.dart' show shrinkHeld;
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import '../attached_actor_block.dart';

/// `RollerBlockEntity.RollingMode`.
enum RollingMode {
  tunnelPave,
  straightFill,
  wideFill;

  static RollingMode of(int value) =>
      value >= 0 && value < values.length ? values[value] : tunnelPave;
}

/// `RollerBlockEntity`.
final class RollerBlockEntity extends CreateBlockEntity {
  static const String type = 'create:mechanical_roller';

  RollerBlockEntity(super.worldId, super.pos);

  /// `filtering.getFilter()`.
  StoredStack filterStack = StoredStack.empty;

  /// `mode.getValue()`.
  int mode = 0;

  /// `manuallyAnimatedSpeed`: for simulations such as Ponder.
  double manuallyAnimatedSpeed = 0;

  bool _dontPropagate = false;

  RollingMode get rollingMode => RollingMode.of(mode);

  double getAnimatedSpeed() => manuallyAnimatedSpeed;

  void setAnimatedSpeed(double speed) => manuallyAnimatedSpeed = speed;

  void setFilter(StoredStack stack, {bool notify = true}) {
    filterStack = stack;
    if (notify) sendData();
  }

  void setMode(int value, {bool notify = true}) {
    mode = value;
    if (notify) sendData();
  }

  /// `isValidMaterial`: the filter must be a full, solid block without a block entity.
  bool isValidMaterial(StoredStack stack) {
    if (stack.isEmpty) return true;
    final block = BlockRegistry.of(stack.item);
    if (block == null) return false;
    final state = block.defaultState;
    if (state.blockEntityType != 0) return false;
    if (block.name.endsWith('_stairs')) return false;
    final shapes = state.collisionShapes;
    if (shapes.isEmpty) return false;
    final box = shapes.first;
    return shapes.length == 1 &&
        box.min.$1 <= 0 &&
        box.min.$2 <= 0 &&
        box.min.$3 <= 0 &&
        box.max.$1 >= 1 &&
        box.max.$2 >= 1 &&
        box.max.$3 >= 1;
  }

  /// `searchForSharedValues`: a roller placed next to another one takes its values.
  void searchForSharedValues() {
    final w = world;
    if (w == null) return;
    final props = w.getBlockState(pos: this.pos).propertyMap;
    final facing = Direction.byName(props['facing'] ?? '') ?? Direction.south;
    for (final side in Iterate.positiveAndNegative) {
      final otherPos = this.pos.toPos().relative(facing.clockWise, side);
      if (w.getBlockStateId(pos: otherPos.toBlockPos()) !=
          w.getBlockStateId(pos: this.pos))
        continue;
      final other = store.typed<RollerBlockEntity>(
        worldId,
        otherPos.toBlockPos(),
      );
      if (other == null) continue;
      acceptSharedValues(other.mode, other.filterStack);
      shareValuesToAdjacent();
      break;
    }
  }

  /// `acceptSharedValues`.
  void acceptSharedValues(int mode, StoredStack filter) {
    _dontPropagate = true;
    setFilter(filter, notify: false);
    setMode(mode, notify: false);
    _dontPropagate = false;
    sendData();
  }

  /// `shareValuesToAdjacent`.
  void shareValuesToAdjacent() {
    if (_dontPropagate) return;
    final w = world;
    if (w == null) return;
    final props = w.getBlockState(pos: this.pos).propertyMap;
    final facing = Direction.byName(props['facing'] ?? '') ?? Direction.south;
    for (final side in Iterate.positiveAndNegative) {
      for (var i = 1; i < 100; i++) {
        final otherPos = this.pos.toPos().relative(facing.clockWise, side * i);
        if (w.getBlockStateId(pos: otherPos.toBlockPos()) !=
            w.getBlockStateId(pos: this.pos))
          break;
        final other = store.typed<RollerBlockEntity>(
          worldId,
          otherPos.toBlockPos(),
        );
        if (other == null) break;
        other.acceptSharedValues(mode, filterStack);
      }
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final filter = tag.getCompound('Filter');
    filterStack = filter == null
        ? StoredStack.empty
        : StoredStack(
            filter.getString('id') ?? 'minecraft:air',
            filter.getInt('count') ?? 0,
          );
    mode = tag.getInt('ScrollValue') ?? 0;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (filterStack.isNotEmpty) {
      tag.putCompound(
        'Filter',
        NbtCompound()
          ..putString('id', filterStack.item)
          ..putInt('count', filterStack.count),
      );
    }
    tag.putInt('ScrollValue', mode);
  }
}

/// `RollerBlockItem.place`: when the block below the clicked block is full on top, the roller is
/// placed on top of the clicked block instead of on the clicked face. Returns true when the
/// interaction was handled (the caller cancels the event).
Future<bool> useRollerItem(Server server, PlayerUseBlockEventData e) async {
  final String itemKey;
  try {
    itemKey = await e.item.getRegistryKey();
  } on Object {
    return false;
  }
  if (itemKey != 'create:mechanical_roller') return false;

  final world = e.player.getWorld();
  final getter = HostBlockGetter(world);
  final clicked = e.blockPos.toPos();
  if (!getter.isFaceSturdy(clicked.below, Direction.up)) return false;

  final face = toDirection(e.face);
  var target = clicked.above;
  if (!getter.canBeReplaced(target)) {
    target = target.relative(face);
    if (!getter.canBeReplaced(target)) return false;
  }

  // `RollerBlock.getStateForPlacement`: always the horizontal look direction, turned around.
  final facing = Direction.fromYRot(e.player.getYaw()).opposite;

  final state = BState('create:mechanical_roller', {
    'facing': facing.serializedName,
    'waterlogged': '${getter.isWater(target)}',
  });
  await setBlockState(world, target, state);

  if (e.player.getGamemode() != GameMode.creative) {
    await shrinkHeld(e.player, e.hand, e.item);
  }
  world.playCustomSound(
    soundName: 'minecraft:block.stone.place',
    category: SoundCategory.blocks,
    pos: target.center,
    volume: 1,
    pitch: 1,
  );
  return true;
}

/// `RollerBlock`.
CreateBlock buildRollerBlock() => buildAttachedActorBlock(
  'mechanical_roller',
  blockEntityType: RollerBlockEntity.type,
  fullCube: true,
  // `RollerBlock.canSurvive` returns true: the roller needs no support.
  requireSupport: false,
  behavior: BlockBehavior(
    onPlaced: (server, e) async {
      final runtime = actors;
      if (runtime == null) return;
      runtime.blockEntities
          .typed<RollerBlockEntity>(e.targetWorld.getId(), e.pos)
          ?.searchForSharedValues();
    },
  ),
);
