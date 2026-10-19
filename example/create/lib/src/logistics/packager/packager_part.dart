// The packager blocks and the part that registers them (`PackagerBlock`, `RepackagerBlock`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/lvl.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/package.dart';
import '../model/stack.dart';
import 'packager_block_entity.dart';
import 'repackager/repackager_block_entity.dart';

/// The `facing` property of the packagers (manifest value order).
final BlockProperty packagerFacing = BlockProperty.enumeration('facing', [
  'north',
  'east',
  'south',
  'west',
  'up',
  'down',
]);

/// `PackagerBlock`.
CreateBlock packagerBlock() => CreateBlock(
  key: 'create:packager',
  properties: [packagerFacing, CreateProps.flag('linked'), CreateProps.powered],
  defaultState: const {'linked': 'true'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  blockEntityType: PackagerBlockEntity.type,
  placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onUse: _onUse,
    onComparatorOutput: _comparator,
  ),
);

/// `RepackagerBlock`: a packager without the `linked` state.
CreateBlock repackagerBlock() => CreateBlock(
  key: 'create:repackager',
  properties: [packagerFacing, CreateProps.powered],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  blockEntityType: RepackagerBlockEntity.type,
  placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
  behavior: BlockBehavior(
    onNeighborUpdate: _onNeighborUpdate,
    onUse: _onUse,
    onComparatorOutput: _comparator,
  ),
);

Future<void> _onNeighborUpdate(
  Server server,
  CustomBlockNeighborUpdateEventData e,
) async {
  final be = Lg.i.store.typed<PackagerBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return;

  final world = e.targetWorld;
  final targetPos = be.targetPos.toBlockPos();
  if (e.sourcePos.x == targetPos.x &&
      e.sourcePos.y == targetPos.y &&
      e.sourcePos.z == targetPos.z) {
    be.triggerStockCheck();
  }

  // `neighborChanged`: the `powered` state follows the redstone input; a rising edge activates.
  final poweredNow = await world.hasRedstoneNeighborSignal(e.pos);
  final info = BlockStates.info(e.stateIndex);
  final wasPowered = info?.properties['powered'] == 'true';
  if (wasPowered == poweredNow) return;
  final lvl = Lvl(world);
  await lvl.setProps(e.pos.toPos(), {
    'powered': poweredNow ? 'true' : 'false',
  }, neighbors: true);
  if (!wasPowered) be.activate();
}

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<PackagerBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;

  if (be.heldBox.isNotEmpty) {
    if (be.animationTicks > 0) return BlockUseResult.success;
    await giveToPlayer(e.player, be.heldBox);
    be.heldBox = LStack.empty;
    be.notifyUpdate();
    return BlockUseResult.success;
  }

  if (be.animationTicks > 0) return BlockUseResult.success;
  final stack = await Lg.i.read(e.item);
  if (!PackageItem.isPackage(stack)) return BlockUseResult.success;

  if (!await be.unwrapBox(stack, simulate: true)) return BlockUseResult.success;
  await be.unwrapBox(stack, simulate: false);
  be.triggerStockCheck();
  await consumeOneInHand(e.player, e.hand);
  return BlockUseResult.success;
}

Future<int?> _comparator(
  Server server,
  CustomBlockComparatorOutputEventData e,
) async {
  final be = Lg.i.store.typed<PackagerBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return 0;
  final empty = be.heldBox.isEmpty && be.animationTicks == 0;
  return empty ? 0 : 15;
}

/// The `packager` part.
final class PackagerPart extends LogisticsPart {
  @override
  String get name => 'packager';

  @override
  void register(CreateRegistry registry) {
    registry.block(packagerBlock());
    registry.block(repackagerBlock());

    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: PackagerBlockEntity.type,
        validBlocks: ['create:packager'],
        create: PackagerBlockEntity.new,
        tickInterval: 1,
      ),
    );
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: RepackagerBlockEntity.type,
        validBlocks: ['create:repackager'],
        create: RepackagerBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    // The package entity is spawned by the package part; the packager only needs the inventory
    // helpers, which are pure.
    unawaited(Future<void>.value());
  }
}
