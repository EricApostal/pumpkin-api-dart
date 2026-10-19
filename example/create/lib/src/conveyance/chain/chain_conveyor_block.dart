// The `create:chain_conveyor` block: its definition, the interaction shape, the placement rule
// (no two conveyors in the same 3x3) and the hooks of `ChainConveyorBlock.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/kinetics.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/blocks.dart';
import '../../kinetics/block_factory.dart' show createBlockFromManifest;
import '../runtime.dart';
import 'chain_conveyor_block_entity.dart';

/// The `IRotate` rules of the chain conveyor: a shaft on the y axis, rotating on y.
class ChainConveyorBlockDef extends KineticBlockDef {
  const ChainConveyorBlockDef();

  @override
  KAxis rotationAxis(KState state) => KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) => face.axis == KAxis.y;
}

/// `AllShapes.CHAIN_CONVEYOR_INTERACTION` (boxes reach outside the block).
BlockShape chainConveyorInteractionShape() => BlockShape.boxes([
  BlockBox(-10 / 16, 2 / 16, 0, 26 / 16, 14 / 16, 1),
  BlockBox(0, 2 / 16, -10 / 16, 1, 14 / 16, 26 / 16),
  BlockBox(-5 / 16, 2 / 16, -5 / 16, 21 / 16, 14 / 16, 21 / 16),
  BlockBox.unit,
]);

/// The `create:chain_conveyor` block.
CreateBlock buildChainConveyorBlock() {
  return createBlockFromManifest(
    'chain_conveyor',
    blockEntityType: 'create:chain_conveyor',
    selectionShape: chainConveyorInteractionShape(),
    collisionShape: BlockShape.fullCube,
    behavior: BlockBehavior(
      onUse: _use,
      onCanPlace: _canPlace,
      onPlayerWillDestroy: _willDestroy,
    ),
  );
}

ChainConveyorBlockEntity? _be(ConveyanceRuntime rt, String worldId, Pos pos) =>
    rt.typedAt<ChainConveyorBlockEntity>(worldId, pos);

Future<BlockUseResult> _use(Server server, CustomBlockUseEventData e) async {
  if (!ConveyanceRuntime.loaded) return BlockUseResult.pass;
  if (!e.withItem) return BlockUseResult.tryEmptyHand;
  final key = await _itemKey(e.item);
  // The chain connections and package placements arrive through payloads; the click only has to
  // be accepted so the client can send them.
  if (key == 'minecraft:iron_chain' || key == 'create:package_frogport')
    return BlockUseResult.success;
  return BlockUseResult.tryEmptyHand;
}

Future<String?> _itemKey(ItemStack stack) async {
  try {
    if (await stack.getCount() <= 0) return null;
    return await stack.getRegistryKey();
  } on Object {
    return null;
  }
}

/// `ChainConveyorBlock.getStateForPlacement`: refuse when any block of the 3x3 at the same y is
/// already a chain conveyor.
Future<bool> _canPlace(Server server, CustomBlockCanPlaceEventData e) async {
  if (!ConveyanceRuntime.loaded) return e.canPlace;
  final getter = HostBlockGetter(e.targetWorld);
  final pos = e.pos.toPos();
  for (var x = -1; x <= 1; x++) {
    for (var z = -1; z <= 1; z++) {
      if (getter.stateAt(pos.offset(x, 0, z)).key == 'create:chain_conveyor')
        return false;
    }
  }
  return e.canPlace;
}

Future<bool> _willDestroy(
  Server server,
  CustomBlockPlayerWillDestroyEventData e,
) async {
  if (!ConveyanceRuntime.loaded) return true;
  if (!e.player.isCreative) return true;
  final rt = ConveyanceRuntime.i;
  final worldId = rt.ctx.worlds.touch(e.targetWorld);
  final be = _be(rt, worldId, e.pos.toPos());
  if (be != null) be.cancelDrops = true;
  return true;
}
