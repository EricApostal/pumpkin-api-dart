// Host side of the millstone block: the `CreateBlock` (shape, kinetic rules and hooks) and its
// interaction with dropped items and the player's hand.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/blocks.dart';
import '../crusher/kinetic_hooks.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'millstone_block_entity.dart';
import 'millstone_keys.dart';

/// `AllShapes.MILLSTONE`: `shape(0, 0, 0, 16, 6, 16).add(2, 6, 2, 14, 16, 14)`.
final BlockShape millstoneShape = BlockShape.boxes([
  BlockBox(0, 0, 0, 1, 6 / 16, 1),
  BlockBox(2 / 16, 6 / 16, 2 / 16, 14 / 16, 1, 14 / 16),
]);

/// `MillstoneBlock implements ICogWheel`: the shaft sits on the bottom face, so a hand crank or
/// a shaft below turns it.
final class MillstoneKineticDef extends KineticBlockDef {
  const MillstoneKineticDef();

  @override
  KAxis rotationAxis(KState state) => KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) => face == Dir.down;

  @override
  bool get isSmallCog => true;
}

late final CreateBlock _millstoneBlock;

/// `MillstoneBlock`.
CreateBlock buildMillstoneBlock() {
  final block = createBlockFromManifest(
    'millstone',
    blockEntityType: millstoneKey,
    collisionShape: millstoneShape,
    selectionShape: millstoneShape,
    behavior: kineticBehaviorWith(
      buildKineticBehavior(
        () => _millstoneBlock,
        use: _use,
        pathfindable: false,
      ),
      onLandedUpon: _landed,
    ),
  );
  _millstoneBlock = block;
  return block;
}

/// `MillstoneBlock.useItemOn`: with an empty hand the output (or the input) is handed back to
/// the player; with an item in hand the use is retried without it.
Future<BlockUseResult> _use(HookCtx c, CustomBlockUseEventData e) async {
  if (e.withItem && await e.item.getCount() > 0) {
    return BlockUseResult.tryEmptyHand;
  }
  final be = ProcessingRuntime.instance.store.typed<MillstoneBlockEntity>(
    c.worldId,
    e.pos,
  );
  if (be != null) await be.emptyIntoPlayer(e.player, c.world);
  return BlockUseResult.success;
}

/// `MillstoneBlock.fallOn`: an item entity that lands on the millstone is inserted into the
/// input (the host calls `onLandedUpon` for landings; there is no `fallOn` hook).
Future<double> _landed(Server server, CustomBlockLandedEventData e) async {
  final rt = ProcessingRuntime.instance;
  final item = e.targetWorld.getEntityById(id: e.entityId)?.asItem();
  if (item != null) {
    final worldId = rt.worlds.touch(e.targetWorld);
    final be = rt.store.typed<MillstoneBlockEntity>(worldId, e.pos);
    if (be != null) await be.insertDroppedItem(item);
  }
  return e.damageMultiplier;
}
