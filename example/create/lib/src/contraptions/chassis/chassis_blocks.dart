// The block definitions of the chassis family and the sticker, with their use behaviours (glue on
// a chassis side, redstone on the sticker).
//
// Java: `content/contraptions/chassis/{AbstractChassisBlock,LinearChassisBlock,RadialChassisBlock,
// StickerBlock}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/common.dart';
import '../../core/blocks.dart';
import 'chassis_logic.dart';
import 'chassis_placement.dart';

/// `AllItems.SUPER_GLUE` / `minecraft:slime_ball`.
const String superGlueItemKey = 'create:super_glue';
const String slimeBallItem = 'minecraft:slime_ball';

/// The chassis and sticker block definitions.
List<CreateBlock> buildChassisBlocks() => [
  _chassisBlock(
    'linear_chassis',
    blockEntityType: 'create:linear_chassis',
    placement: linearChassisPlacementRules,
  ),
  _chassisBlock(
    'secondary_linear_chassis',
    blockEntityType: 'create:secondary_linear_chassis',
    placement: linearChassisPlacementRules,
  ),
  _chassisBlock(
    'radial_chassis',
    blockEntityType: 'create:radial_chassis',
    placement: radialChassisPlacementRules,
  ),
  manifestBlock(
    'sticker',
    blockEntityType: 'create:sticker',
    placement: stickerPlacementRules,
    behavior: stickerBehavior(),
  ),
];

/// A linear or radial chassis. The behaviour needs the block itself, because the `update-shape`
/// answer is a state index of the block (see [linearChassisShapeAnswer]).
CreateBlock _chassisBlock(
  String key, {
  required String blockEntityType,
  required List<PlacementRule> placement,
}) {
  late final CreateBlock block;
  block = manifestBlock(
    key,
    blockEntityType: blockEntityType,
    placement: placement,
    behavior: chassisBehavior(() => block),
  );
  return block;
}

/// `AbstractChassisBlock.useItemOn` / `useWithoutItem`: a slime ball or super glue adds the sticky
/// side, an empty sneaking hand removes it, and a slime ball on a sticky side fills every side.
BlockBehavior chassisBehavior(CreateBlock Function() blockRef) => BlockBehavior(
  onUseWithItem: (server, e) async {
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    // The clicked state (`useItemOn`'s `state` argument), not the event's per-block `stateIndex`.
    final state = HostBlockGetter(e.targetWorld).stateAt(pos);
    final String itemKey;
    try {
      itemKey = await e.item.getRegistryKey();
    } catch (_) {
      return BlockUseResult.tryEmptyHand;
    }
    final isGlue = itemKey == slimeBallItem || itemKey == superGlueItemKey;
    if (!isGlue) return BlockUseResult.tryEmptyHand;
    final next = chassisGlueClick(
      state,
      toDirection(e.face),
      true,
      e.sneaking,
      false,
      (face) => _glueAllowedOnSide(e.targetWorld, pos, state, face),
    );
    if (next == null || next == state) return BlockUseResult.tryEmptyHand;
    await setBlockState(e.targetWorld, pos, next);
    return BlockUseResult.success;
  },
  onUseWithoutItem: (server, e) async {
    if (!e.sneaking || !await _isEmpty(e.item)) return BlockUseResult.pass;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final state = HostBlockGetter(e.targetWorld).stateAt(pos);
    final next = chassisGlueClick(
      state,
      toDirection(e.face),
      false,
      true,
      true,
      (face) => _glueAllowedOnSide(e.targetWorld, pos, state, face),
    );
    if (next == null || next == state) return BlockUseResult.pass;
    await setBlockState(e.targetWorld, pos, next);
    return BlockUseResult.success;
  },
  onUpdateShape: (server, e) {
    // `LinearChassisBlock.updateShape`: a neighbouring chassis of the same kind and axis clears
    // the glue of the shared side.
    final state = HostBlockGetter(e.targetWorld).stateAt(
      (e.pos.x, e.pos.y, e.pos.z),
    );
    if (!isLinearChassis(state)) return null;
    final other = HostBlockGetter.stateOfId(e.neighborStateId);
    return linearChassisShapeAnswer(
      blockRef().layout,
      state,
      toDirection(e.direction),
      other,
    );
  },
);

/// `LinearChassisBlock.glueAllowedOnSide` (radial chassis always allows it).
bool _glueAllowedOnSide(World world, Pos pos, BState state, Direction face) {
  if (!isLinearChassis(state)) return true;
  final other = HostBlockGetter(world).stateAt(pos.relative(face));
  return linearGlueAllowedOnSide(state, other);
}

Future<bool> _isEmpty(ItemStack stack) async {
  try {
    return await stack.getCount() == 0;
  } on Object {
    return true;
  }
}

/// `StickerBlock`: powered from the neighbours when placed, powered on a neighbour change; while
/// powered it is extended.
BlockBehavior stickerBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    if (await e.targetWorld.hasNeighborSignal(pos: e.pos)) {
      final state = HostBlockGetter(e.targetWorld).stateAt(
        (e.pos.x, e.pos.y, e.pos.z),
      );
      await _setStickerPowered(e.targetWorld, e.pos, state, true);
    }
  },
  onNeighborUpdate: (server, e) async {
    final state = HostBlockGetter(e.targetWorld).stateAt(
      (e.pos.x, e.pos.y, e.pos.z),
    );
    if (state.key != 'create:sticker') return;
    final powered = state.flag('powered');
    final shouldPower = await e.targetWorld.hasNeighborSignal(pos: e.pos);
    if (powered == shouldPower) return;
    await _setStickerPowered(e.targetWorld, e.pos, state, shouldPower);
  },
);

Future<void> _setStickerPowered(
  World world,
  BlockPos pos,
  BState state,
  bool powered,
) async {
  var next = state.setFlag('powered', powered);
  if (powered) next = next.setFlag('extended', !next.flag('extended'));
  final id = BlockRegistry.resolveState(next.key, next.props);
  if (id == null) return;
  await world.setBlockState(
    pos: pos,
    state: id,
    updateFlags: {BlockFlagsFlag.notifyListeners},
  );
}
