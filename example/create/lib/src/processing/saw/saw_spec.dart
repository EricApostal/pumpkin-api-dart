// The block of the mechanical saw (`SawBlock`): its shape, the state a player's placement turns
// into, and the server hooks (cutting, damage, item insertion).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/damage.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'block_breaking.dart';
import 'saw_block.dart';

/// `AllShapes.CASING_12PX.forDirectional()`: 12px along the facing axis, at the back.
BlockBox casingBox(Direction facing) {
  const edge = 12 / 16;
  const inset = 4 / 16;
  return switch (facing) {
    Direction.up => BlockBox(0, 0, 0, 1, edge, 1),
    Direction.down => BlockBox(0, inset, 0, 1, 1, 1),
    Direction.south => BlockBox(0, 0, 0, 1, 1, edge),
    Direction.north => BlockBox(0, 0, inset, 1, 1, 1),
    Direction.east => BlockBox(0, 0, 0, edge, 1, 1),
    Direction.west => BlockBox(inset, 0, 0, 1, 1, 1),
  };
}

/// The per-facing shape rules of the 12px casing (saw and drill).
List<ShapeRule> casing12Rules() => [
  for (final d in Direction.values)
    ShapeRule(
      when: {'facing': d.serializedName},
      collisionShape: BlockShape.boxes([casingBox(d)]),
      selectionShape: BlockShape.boxes([casingBox(d)]),
    ),
];

/// `SawBlock.getStateForPlacement` (a `DirectionalAxisKineticBlock` with `FLIPPED`).
KState sawPlacement(PlacementContext ctx) {
  var facing = ctx.nearestLooking.opposite;
  if (ctx.hasPlayer && ctx.sneaking) facing = facing.opposite;

  var alongFirst = false;
  final faceAxis = facing.axis;

  bool prefers(Dir dir, bool shaftAxis) {
    if (!shaftAxis) return false;
    final neighbourPos = ctx.pos.relative(dir);
    final state = ctx.stateAt(neighbourPos);
    final def = ctx.blocks.defFor(state);
    return def != null && def.hasShaftTowards(state, dir.opposite);
  }

  if (faceAxis.isHorizontal) {
    alongFirst = faceAxis == KAxis.z;
    final positivePerpendicular = faceAxis == KAxis.x ? Dir.south : Dir.east;

    final shaftAbove = prefers(Dir.up, true);
    final shaftBelow = prefers(Dir.down, true);
    final preferLeft = prefers(positivePerpendicular, false);
    final preferRight = prefers(positivePerpendicular.opposite, false);

    if (shaftAbove || shaftBelow || preferLeft || preferRight) {
      alongFirst = faceAxis == KAxis.x;
    }
  }

  if (faceAxis.isVertical) {
    alongFirst = ctx.horizontal.axis == KAxis.x;
    Dir? preferredSide;
    for (final side in Dir.horizontals) {
      if (!prefers(side, true) && !prefers(side.clockWise(KAxis.y), false)) {
        continue;
      }
      if (preferredSide != null && preferredSide.axis != side.axis) {
        preferredSide = null;
        break;
      }
      preferredSide = side;
    }
    if (preferredSide != null) alongFirst = preferredSide.axis == KAxis.x;
  }

  final flipped = facing.axis == KAxis.y && ctx.horizontal.isPositive;
  return KState('create:mechanical_saw', {
    'facing': facing.name,
    'axis_along_first': '$alongFirst',
    'flipped': '$flipped',
  });
}

/// `SawBlock.entityInside`: hurt entities (not items) that overlap the blade.
Future<void> sawEntityInside(
  Server server,
  CustomBlockEntityCollisionEventData e,
) async {
  if (e.entityType == 'minecraft:item') return;
  if (!ProcessingRuntime.isLoaded) return;
  final rt = ProcessingRuntime.instance;
  final entity = e.targetWorld.getEntityById(id: e.entityId);
  if (entity == null) return;

  final bb = entity.getBoundingBox();
  final blade = Aabb.ofBlock(e.pos.toPos()).deflate(.1);
  final box = Aabb(
    bb.min.$1,
    bb.min.$2,
    bb.min.$3,
    bb.max.$1,
    bb.max.$2,
    bb.max.$3,
  );
  if (!blade.intersects(box)) return;

  final be = rt.store.typed<SawBlockEntity>(
    rt.worlds.touch(e.targetWorld),
    e.pos,
  );
  if (be == null || be.speed == 0) return;
  await CreateDamage.saw.hurtEntity(entity, kineticDamage(be.speed));
}

/// `SawBlock.fallOn`: a dropped item that lands on an upward saw is inserted.
Future<double> sawLandedUpon(
  Server server,
  CustomBlockLandedEventData e,
) async {
  if (!ProcessingRuntime.isLoaded) return e.damageMultiplier;
  final rt = ProcessingRuntime.instance;
  final item = e.targetWorld.getEntityById(id: e.entityId)?.asItem();
  if (item == null) return e.damageMultiplier;
  final be = rt.store.typed<SawBlockEntity>(
    rt.worlds.touch(e.targetWorld),
    e.pos,
  );
  if (be != null) await be.insertItem(item);
  return e.damageMultiplier;
}

/// `SawBlock.useItemOn`: an empty hand takes the contents back; an item on the top slot sets the
/// recipe filter.
Future<BlockUseResult> sawUse(HookCtx c, CustomBlockUseEventData e) async {
  final be = c.beOf<SawBlockEntity>();
  if (be == null) return BlockUseResult.pass;
  final facing = c.state.dirOf('facing') ?? Dir.north;

  if (!e.withItem) {
    if (facing != Dir.up) return BlockUseResult.pass;
    await be.dropInventoryTo(e.player, c.world);
    return BlockUseResult.success;
  }

  if (facing != Dir.up || e.face != BlockDirection.up || e.sneaking) {
    return BlockUseResult.pass;
  }
  final key = await e.item.getRegistryKey();
  if (key == 'create:wrench' || key == 'create:mechanical_arm') {
    return BlockUseResult.pass;
  }
  be.filter.setFilter(await HostStacks.read(e.item));
  return BlockUseResult.success;
}

/// The block and block entity type of the mechanical saw.
KineticBlockSpec sawSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'mechanical_saw',
    blockEntityType: 'create:saw',
    shapeRules: casing12Rules(),
    placement: const [PlacementRule.lookingDirection('facing')],
    behavior: withBlockHooks(
      buildKineticBehavior(
        () => block,
        specRef: () => spec,
        pathfindable: false,
        use: sawUse,
      ),
      onEntityCollision: sawEntityInside,
      onLandedUpon: sawLandedUpon,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const SawBlockDef(),
    placement: (ctx, placed, use, world) => sawPlacement(ctx),
  );
  return spec;
}
