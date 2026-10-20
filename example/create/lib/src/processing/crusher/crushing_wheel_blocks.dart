// Host side of the crushing wheel blocks: the `CreateBlock`s with their kinetic rules and
// hooks, and the dynamic collision shape of the controller.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/blocks.dart';
import '../../kinetics/placement.dart'
    show clickedFaceForPlacedState, rotatedPillarAxis;
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'crushing_keys.dart';
import 'crushing_wheel_block_entity.dart';
import 'crushing_wheel_controller_block_entity.dart';
import 'kinetic_hooks.dart';

late final CreateBlock _wheelBlock;
late final KineticBlockSpec _wheelSpec;

/// `CrushingWheelBlock`: a kinetic block on its `axis` property, shaft towards both ends.
CreateBlock buildCrushingWheelBlock() {
  final block = createBlockFromManifest(
    'crushing_wheel',
    blockEntityType: crushingWheelKey,
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: kineticBehaviorWith(
      buildKineticBehavior(
        () => _wheelBlock,
        specRef: () => _wheelSpec,
        canPlace: _canPlaceWheel,
        replaced: _wheelReplaced,
      ),
      onEntityCollision: _wheelEntityInside,
    ),
  );
  _wheelBlock = block;
  _wheelSpec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    // `RotatedPillarKineticBlock.getStateForPlacement`: follow the neighbouring shafts,
    // otherwise the clicked face / looking axis.
    placement: (ctx, placed, use, world) async =>
        KState(crushingWheelKey, {'axis': rotatedPillarAxis(ctx).name}),
  );
  return block;
}

/// `CrushingWheelControllerBlock`: the invisible block between two wheels. Its collision shape
/// is a 13/16 slab that leaves the input side open, and it is empty while an entity is being
/// crushed.
CreateBlock buildCrushingWheelControllerBlock() => createBlockFromManifest(
  'crushing_wheel_controller',
  blockEntityType: crushingWheelControllerKey,
  useLootTable: false,
  pistonBehavior: PistonBehavior.block,
  shapeRules: _controllerShapeRules(),
  behavior: withEntityCollisionShape(
    BlockBehavior(
      onEntityCollision: _controllerEntityInside,
      onUpdateShape: _controllerUpdateShape,
      isPathfindable: (server, e) => false,
    ),
    _controllerShape,
  ),
);

// -- Crushing wheel ------------------------------------------------------------------------

/// `CrushingWheelBlock.canSurvive`: wheels only line up along their axis and never next to a
/// controller that is on a different side than their axis. Checked against the axis
/// `getStateForPlacement` will pick (the host asks before the placement correction runs).
Future<bool> _canPlaceWheel(HookCtx c, CustomBlockCanPlaceEventData e) async {
  if (!e.canPlace) return false;
  final player = e.player;
  if (player == null) {
    return _canSurvive(c.level, c.kpos, c.state.axisOf('axis') ?? KAxis.y);
  }
  final ctx = await _placementContext(c, player, e.face, e.pos);
  if (ctx == null) return true;
  return _canSurvive(c.level, c.kpos, rotatedPillarAxis(ctx));
}

bool _canSurvive(HostKineticLevel level, KPos pos, KAxis axis) {
  for (final direction in Dir.values) {
    final neighbour = level.stateAt(pos.relative(direction));
    if (neighbour.block == crushingWheelControllerKey &&
        direction.axis != axis) {
      return false;
    }
    if (neighbour.block != crushingWheelKey) continue;
    if (neighbour.axisOf('axis') != axis || axis != direction.axis) {
      return false;
    }
  }
  return true;
}

/// What `BlockPlaceContext` knows when the host asks `canPlace` (the same inputs
/// `buildKineticBehavior`'s placement fix uses).
Future<PlacementContext?> _placementContext(
  HookCtx c,
  Uuid player,
  BlockDirection? face,
  BlockPos pos,
) async {
  final p = c.server.getPlayerByUuid(id: player);
  if (p == null) return null;
  final record = c.rt.useRecords.matching(player.asString, pos);
  final clicked =
      record?.face ??
      (face == null ? null : Dir.fromName(face.name)?.opposite) ??
      clickedFaceForPlacedState(c.state);
  return PlacementContext(
    pos: KPos(pos.x, pos.y, pos.z),
    clickedFace: clicked,
    nearestLooking: nearestLookingDirection(p.getYaw(), p.getPitch()),
    horizontal: horizontalDirection(p.getYaw()),
    sneaking: record?.sneaking ?? p.asEntity().isSneaking(),
    stateAt: c.level.stateAt,
    blocks: c.rt.blocks,
  );
}

/// `CrushingWheelBlock.affectNeighborsAfterRemoval`: the controllers next to the wheel go away
/// with it (they only exist between two wheels).
Future<void> _wheelReplaced(
  HookCtx c,
  CustomBlockStateReplacedEventData e,
) async {
  final axis = c.state.axisOf('axis') ?? KAxis.y;
  final air = KineticsRuntime.instance.states.idOf(KState.air);
  if (air == null) return;
  for (final direction in Dir.values) {
    if (direction.axis == axis) continue;
    final controllerPos = c.kpos.relative(direction);
    if (c.level.stateAt(controllerPos).block != crushingWheelControllerKey) {
      continue;
    }
    await c.world.setBlockState(
      pos: toBlockPos(controllerPos),
      state: air,
      updateFlags: BlockUpdateFlags.normal,
    );
  }
}

/// `CrushingWheelBlock.entityInside`: an entity standing on or inside a turning wheel is pushed
/// across the wheel axis (the wheels act like a treadmill).
Future<void> _wheelEntityInside(
  Server server,
  CustomBlockEntityCollisionEventData e,
) async {
  final rt = ProcessingRuntime.instance;
  final worldId = rt.worlds.touch(e.targetWorld);
  final state = KineticsRuntime.instance.level(worldId).stateAt(toKPos(e.pos));
  if (state.block != crushingWheelKey) return;

  final entity = e.targetWorld.getEntityById(id: e.entityId);
  if (entity == null) return;
  final entityPos = entity.getPosition();
  if (entityPos.$2 >= e.pos.y + 1.25 || !entity.isOnGround()) return;

  final speed =
      rt.store.typed<CrushingWheelBlockEntity>(worldId, e.pos)?.speed ?? 0;
  final axis = state.axisOf('axis') ?? KAxis.y;
  var x = 0.0;
  var z = 0.0;
  if (axis == KAxis.x) {
    z = speed / 20;
    x += (e.pos.x + .5 - entityPos.$1) * .1;
  }
  if (axis == KAxis.z) {
    x = speed / -20;
    z += (e.pos.z + .5 - entityPos.$3) * .1;
  }
  final velocity = entity.getVelocity();
  entity.setVelocity(velocity: (velocity.$1 + x, velocity.$2, velocity.$3 + z));
}

// -- Controller ----------------------------------------------------------------------------

/// `AllShapes.CRUSHING_WHEEL_CONTROLLER_COLLISION`: `shape(0, 0, 0, 16, 13, 16)` oriented
/// with `forDirectional(DOWN)`, so the 3/16 gap is on the side opposite `facing`.
List<ShapeRule> _controllerShapeRules() {
  BlockBox box(num x0, num y0, num z0, num x1, num y1, num z1) =>
      BlockBox(x0 / 16, y0 / 16, z0 / 16, x1 / 16, y1 / 16, z1 / 16);
  BlockShape shape(List<BlockBox> boxes) => BlockShape.boxes(boxes);
  ShapeRule rule(String facing, BlockBox b) => ShapeRule(
    when: {'facing': facing},
    collisionShape: shape([b]),
    selectionShape: shape([b]),
  );
  // `AllShapes.CRUSHING_WHEEL_CONTROLLER_COLLISION` is `shape(0, 0, 0, 16, 13, 16)
  // .forDirectional(Direction.DOWN)`. `forDirectional(shape, facing)` rotates from `facing`, and
  // `rotate` returns the shape unchanged when `from == to`, so `down` is the identity: the slab
  // is y 0..13 and the solid part sits on the `facing` side, the opening away from it.
  return [
    rule('down', box(0, 0, 0, 16, 13, 16)),
    rule('up', box(0, 3, 0, 16, 16, 16)),
    rule('north', box(0, 0, 0, 16, 16, 13)),
    rule('south', box(0, 0, 3, 16, 16, 16)),
    rule('east', box(3, 0, 0, 16, 16, 16)),
    rule('west', box(0, 0, 0, 13, 16, 16)),
  ];
}

/// `CrushingWheelControllerBlock.getCollisionShape`: empty for the entity being crushed (it
/// would be pushed out otherwise) and for an item this controller ejected, so the output can
/// land on the block instead of falling back through the open side.
List<BlockBox>? _controllerShape(
  Server server,
  CustomBlockCollisionShapeEventData e,
) {
  final rt = ProcessingRuntime.instance;
  final worldId = rt.worlds.touch(e.targetWorld);
  final be = rt.store.typed<CrushingWheelControllerBlockEntity>(worldId, e.pos);
  if (be == null) return null;
  final state = KineticsRuntime.instance.level(worldId).stateAt(toKPos(e.pos));
  // `if (!state.getValue(VALID)) return standardShape;`
  if (!state.flag('valid')) return null;
  if (be.isProcessingEntity(e.entityId)) return const <BlockBox>[];
  if ((state.dirOf('facing') ?? Dir.north) == Dir.up) return null;
  final entity = e.targetWorld.getEntityById(id: e.entityId);
  if (entity != null && be.bypasses(entity)) return const <BlockBox>[];
  return null;
}

/// `CrushingWheelControllerBlock.entityInside`: start crushing the entity that touches the
/// controller. (`makeStuckInBlock` has no host equivalent; the controller keeps the entity in
/// place through its velocity every tick instead.)
Future<void> _controllerEntityInside(
  Server server,
  CustomBlockEntityCollisionEventData e,
) async {
  final rt = ProcessingRuntime.instance;
  final worldId = rt.worlds.touch(e.targetWorld);
  final state = KineticsRuntime.instance.level(worldId).stateAt(toKPos(e.pos));
  if (state.block != crushingWheelControllerKey || !state.flag('valid')) return;
  final be = rt.store.typed<CrushingWheelControllerBlockEntity>(worldId, e.pos);
  if (be == null) return;
  await be.checkEntityForProcessing(
    server,
    e.targetWorld,
    e.entityId,
    e.entityUuid,
  );
}

/// `CrushingWheelControllerBlock.updateShape`: a neighbour changed, the wheel speed may have.
int? _controllerUpdateShape(Server server, CustomBlockUpdateShapeEventData e) {
  final rt = ProcessingRuntime.instance;
  final worldId = rt.worlds.touch(e.targetWorld);
  final be = rt.store.typed<CrushingWheelControllerBlockEntity>(worldId, e.pos);
  if (be != null) {
    be.updateSpeed(
      KineticsRuntime.instance.level(worldId).stateAt(toKPos(e.pos)),
    );
  }
  return null;
}
