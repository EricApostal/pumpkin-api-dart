// `DrillBlock` / `DrillBlockEntity`: the mechanical drill. It grinds through the block in front of
// it and hurts entities that touch its head. Ported from
// `content/kinetics/drill/DrillBlock.java` and `DrillBlockEntity.java`. The cobblestone
// generator optimisation (`CobbleGenOptimisation`) is not ported; the drill simply drops the
// broken block's loot.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/damage.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../processing_runtime.dart';
import '../saw/block_breaking.dart';
import '../saw/saw_spec.dart' show casing12Rules;

/// `DrillBlockEntity`.
final class DrillBlockEntity extends BlockBreakingKineticBlockEntity {
  DrillBlockEntity(super.worldId, super.pos);

  @override
  Pos getBreakingPos() {
    final facing = blockState.dirOf('facing') ?? Dir.north;
    return (pos.x + facing.dx, pos.y + facing.dy, pos.z + facing.dz);
  }
}

/// `DrillBlock.getStateForPlacement` (`DirectionalKineticBlock`): next to a shaft the drill turns
/// away from it, otherwise it faces the player.
KState drillPlacement(PlacementContext ctx) {
  Dir? preferred;
  for (final side in Dir.values) {
    final state = ctx.stateAt(ctx.pos.relative(side));
    final def = ctx.blocks.defFor(state);
    if (def == null || !def.hasShaftTowards(state, side.opposite)) continue;
    if (preferred != null && preferred.axis != side.axis) {
      preferred = null;
      break;
    }
    preferred = side;
  }

  final Dir facing;
  if (preferred == null || (ctx.hasPlayer && ctx.sneaking)) {
    final nearest = ctx.nearestLooking;
    facing = ctx.hasPlayer && ctx.sneaking ? nearest : nearest.opposite;
  } else {
    facing = preferred.opposite;
  }
  return KState('create:mechanical_drill', {'facing': facing.name});
}

/// `DrillBlock.entityInside`: hurt entities (not items) that overlap the drill head.
Future<void> drillEntityInside(
  Server server,
  CustomBlockEntityCollisionEventData e,
) async {
  if (e.entityType == 'minecraft:item') return;
  if (!ProcessingRuntime.isLoaded) return;
  final rt = ProcessingRuntime.instance;
  final entity = e.targetWorld.getEntityById(id: e.entityId);
  if (entity == null) return;

  final bb = entity.getBoundingBox();
  final head = Aabb.ofBlock(e.pos.toPos()).deflate(.1);
  final box = Aabb(
    bb.min.$1,
    bb.min.$2,
    bb.min.$3,
    bb.max.$1,
    bb.max.$2,
    bb.max.$3,
  );
  if (!head.intersects(box)) return;

  final be = rt.store.typed<DrillBlockEntity>(
    rt.worlds.touch(e.targetWorld),
    e.pos,
  );
  if (be == null || be.speed == 0) return;
  await CreateDamage.drill.hurtEntity(entity, kineticDamage(be.speed));
}

/// The block and block entity type of the mechanical drill.
KineticBlockSpec drillSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'mechanical_drill',
    blockEntityType: 'create:drill',
    shapeRules: casing12Rules(),
    placement: const [
      PlacementRule.lookingDirection('facing'),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: withBlockHooks(
      buildKineticBehavior(
        () => block,
        specRef: () => spec,
        pathfindable: false,
        neighbor: (c, e) {
          // DrillBlock.neighborChanged: restart the breaking progress.
          c.beOf<DrillBlockEntity>()?.destroyNextTick();
          if (c.state.flag('waterlogged')) {
            c.world.scheduleFluidFlow(c.pos, delayTicks: 5);
          }
        },
      ),
      onEntityCollision: drillEntityInside,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const FacingBlockDef(shaftAtFront: false),
    placement: (ctx, placed, use, world) =>
        drillPlacement(ctx)
            .set('waterlogged', placed['waterlogged'] ?? 'false'),
  );
  return spec;
}
