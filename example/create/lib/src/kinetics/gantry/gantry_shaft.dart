// `GantryShaftBlock` and `GantryShaftBlockEntity`: the shaft a gantry carriage rides. The
// carriage itself is in the contraptions module and asks the shaft through `GantryShaftLike`;
// the pure rules (parts, placement, pinion speed, redstone) are in `gantry_shaft_logic.dart`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../core/blocks.dart';
import '../../contraptions/gantry/gantry_carriage.dart'
    show
        GantryCarriageBlockEntity,
        gantryCarriageKey,
        getGantryPinionModifier,
        toDirection2;
import '../../contraptions/gantry/gantry_contraption_entity.dart'
    show GantryShaftLike;
import '../behavior_builder.dart';
import '../block_defs.dart';
import '../block_factory.dart';
import '../geometry.dart';
import '../kinetic_block_entity.dart';
import '../node.dart';
import '../placement.dart';
import '../placement_helper_host.dart';
import '../runtime.dart';
import '../use_records.dart';
import 'gantry_shaft_logic.dart';

/// `GantryShaftBlockEntity`: a shaft that drives a gantry carriage instead of a machine.
class GantryShaftBlockEntity extends KineticBlockEntity
    implements GantryShaftLike {
  GantryShaftBlockEntity(super.worldId, super.pos);

  /// `getBlockState()` as the contraptions module sees states.
  @override
  BState get shaftState => BState(blockState.block, blockState.props);

  /// `syncSequenceContext()`: a sequenced gearshift's context reaches the gantry.
  @override
  bool get syncSequenceContext => true;

  @override
  double get pinionMovementSpeed => gantryShaftPinionSpeed(blockState, speed);

  @override
  bool get canAssembleOn => gantryShaftCanAssemble(blockState, speed);

  /// `checkAttachedCarriageBlocks`: queue the assembly of every carriage riding this shaft.
  void checkAttachedCarriageBlocks() {
    if (!canAssembleOn) return;
    final axis = (blockState.dirOf('facing') ?? Dir.north).axis;
    for (final d in Dir.values) {
      if (d.axis == axis) continue;
      final offset = kpos.relative(d);
      final pinionState = level.stateAt(offset);
      if (pinionState.block != gantryCarriageKey) continue;
      if (pinionState.dirOf('facing') != d) continue;
      final be = level.nodeAt(offset);
      if (be is GantryCarriageBlockEntity) be.queueAssembly();
    }
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    checkAttachedCarriageBlocks();
  }

  @override
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  ) {
    final defaultModifier = super.propagateRotationTo(
      target,
      stateFrom,
      stateTo,
      diff,
      connectedViaAxes,
      connectedViaCogs,
    );
    if (connectedViaAxes) return defaultModifier;
    if (!stateFrom.flag('powered')) return defaultModifier;
    if (stateTo.block != gantryCarriageKey) return defaultModifier;
    final direction = Dir.approximateNearest(diff.x, diff.y, diff.z);
    final pinionFacing = stateTo.dirOf('facing');
    if (pinionFacing != direction) return defaultModifier;
    final shaftFacing = stateFrom.dirOf('facing');
    if (shaftFacing == null || pinionFacing == null) return defaultModifier;
    return getGantryPinionModifier(
      toDirection2(shaftFacing),
      toDirection2(pinionFacing),
    );
  }

  @override
  bool isCustomConnection(KineticNode other, KState state, KState otherState) {
    if (otherState.block != gantryCarriageKey) return false;
    final diff = other.kpos - kpos;
    final direction = Dir.approximateNearest(diff.x, diff.y, diff.z);
    return otherState.dirOf('facing') == direction;
  }
}

// -- Block ---------------------------------------------------------------------------------

KineticBlockSpec gantryShaftSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'gantry_shaft',
    blockEntityType: 'create:gantry_shaft',
    placement: [PlacementRule.clickedFace('facing')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      use: _use,
      updateShape: (c, e) {
        final direction = Dir.fromName(e.direction.name);
        if (direction == null) return null;
        final neighbour = c.rt.states.decode(e.neighborStateId);
        final updated = gantryShaftUpdatePart(c.state, direction, neighbour);
        if (updated == c.state) return null;
        final oldPart = c.state['part'] ?? 'single';
        final newPart = updated['part'] ?? 'single';
        // `GantryShaftBlock.onPlace`: a part change that joins a line may unblock a carriage.
        if ((oldPart != 'middle' && newPart == 'middle') ||
            (oldPart == 'single' && newPart != 'single')) {
          c.world.scheduleTick(c.pos, const Duration(milliseconds: 50));
        }
        return block.layout.indexOf({
          ...block.definition.defaultState,
          ...updated.props,
        });
      },
      scheduledTick: (c) {
        c.beOf<GantryShaftBlockEntity>()?.checkAttachedCarriageBlocks();
      },
      neighbor: _neighbor,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const GantryShaftDef(),
    placement: _placement,
  );
  return spec;
}

/// `GantryShaftBlock.useItemOn` with the pole placement helper.
Future<BlockUseResult> _use(HookCtx c, CustomBlockUseEventData e) async {
  if (!e.withItem) return BlockUseResult.pass;
  final String item;
  try {
    item = await e.item.getRegistryKey();
  } catch (_) {
    return BlockUseResult.tryEmptyHand;
  }
  if (item != gantryShaftKey) return BlockUseResult.tryEmptyHand;
  final block = c.rt.kineticBlocks[item];
  if (block == null) return BlockUseResult.fail;
  final w = helperWorldFor(c.rt, c.worldId, c.world);
  final hit = (
    c.pos.x + e.cursor.$1,
    c.pos.y + e.cursor.$2,
    c.pos.z + e.cursor.$3,
  );
  final offset = gantryShaftPoleOffset(w, c.kpos, c.state, hit);
  if (!offset.success) return BlockUseResult.fail;
  final placed = await placeOffset(
    c.rt,
    c.world,
    c.worldId,
    offset,
    block,
    e.player,
    e.hand,
  );
  return placed ? BlockUseResult.success : BlockUseResult.fail;
}

/// `GantryShaftBlock.getStateForPlacement`.
Future<KState> _placement(
  PlacementContext ctx,
  KState placed,
  UseRecord? use,
  World world,
) async {
  var state = placed.set('facing', directionalFacing(ctx).name);
  final initialFacing = state.dirOf('facing') ?? Dir.north;
  final neighbour = ctx.stateAt(ctx.pos.relative(initialFacing.opposite));
  final clickedState = neighbour.block == gantryShaftKey
      ? neighbour
      : ctx.stateAt(ctx.pos.relative(ctx.clickedFace.opposite));
  final clickedFacing = clickedState.dirOf('facing');
  if (clickedState.block == gantryShaftKey &&
      clickedFacing != null &&
      clickedFacing.axis == initialFacing.axis) {
    state = state.set(
      'facing',
      (ctx.sneaking ? clickedFacing.opposite : clickedFacing).name,
    );
  }
  final powered = gantryShaftShouldBePowered(
    state,
    ctx.pos,
    await world.hasNeighborSignal(pos: toBlockPos(ctx.pos)),
    (p) => world.isLoaded(pos: toBlockPos(p)),
    ctx.stateAt,
  );
  return state.setFlag('powered', powered);
}

/// `GantryShaftBlock.neighborChanged`: the powered state of the whole line follows redstone.
Future<void> _neighbor(HookCtx c, CustomBlockNeighborUpdateEventData e) async {
  final state = c.level.stateAt(c.kpos);
  if (state.block != gantryShaftKey) return;
  final previouslyPowered = state.flag('powered');
  final shouldPower = await c.world.hasNeighborSignal(pos: c.pos);

  if (!previouslyPowered &&
      !shouldPower &&
      gantryShaftShouldBePowered(
        state,
        c.kpos,
        false,
        (p) => c.world.isLoaded(pos: toBlockPos(p)),
        c.level.stateAt,
      )) {
    // `KineticBlock.onPlace` + `updateIndirectNeighbourShapes`: a new connection re-propagates.
    final be = c.be;
    if (be != null) {
      be.warnOfMovement();
      be.clearKineticInformation();
      be.updateSpeed = true;
    }
    await c.setState(
      state.setFlag('powered', true),
      flags: BlockUpdateFlags.normal,
    );
    return;
  }

  if (previouslyPowered == shouldPower) return;

  final facing = state.dirOf('facing') ?? Dir.north;
  final toUpdate = <KPos>[];
  for (final d in Dir.inAxis(facing.axis)) {
    var currentPos = c.kpos.relative(d);
    while (true) {
      if (!c.world.isLoaded(pos: toBlockPos(currentPos))) break;
      final currentState = c.level.stateAt(currentPos);
      if (currentState.block != gantryShaftKey) break;
      if (currentState.dirOf('facing') != facing) break;
      if (!shouldPower &&
          currentState.flag('powered') &&
          await c.world.hasNeighborSignal(pos: toBlockPos(currentPos))) {
        return;
      }
      if (currentState.flag('powered') == shouldPower) break;
      toUpdate.add(currentPos);
      currentPos = currentPos.relative(d);
    }
  }

  toUpdate.add(c.kpos);
  for (final pos in toUpdate) {
    final blockState = c.level.stateAt(pos);
    final be = c.rt.store.at(c.worldId, toBlockPos(pos));
    if (be is KineticBlockEntity) be.detachKinetics();
    if (blockState.block == gantryShaftKey) {
      final id = c.rt.states.idOf(blockState.setFlag('powered', shouldPower));
      if (id != null) {
        await c.world.setBlockState(
          pos: toBlockPos(pos),
          state: id,
          updateFlags: BlockUpdateFlags.clientsOnly,
        );
      }
    }
  }
}
