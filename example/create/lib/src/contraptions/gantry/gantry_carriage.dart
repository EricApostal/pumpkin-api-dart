// `GantryCarriageBlock` and `GantryCarriageBlockEntity`: the pinion that rides a gantry shaft and
// assembles the gantry contraption. The shaft itself is a kinetics block; its parts are asked
// through [GantryShaftLike].
//
// Java: `content/contraptions/gantry/{GantryCarriageBlock,GantryCarriageBlockEntity}`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, manifestBlock, toDirection;
import '../../common/common.dart';
import '../../core/blocks.dart';
import '../../kinetics/api.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_nbt.dart';
import '../blocks/actuator_runtime.dart';
import '../core/structure_info.dart';
import 'gantry_contraption.dart';
import 'gantry_contraption_entity.dart';

const String gantryCarriageKey = 'create:gantry_carriage';
const String gantryShaftKey = 'create:gantry_shaft';

/// The gantry carriage definition.
List<CreateBlock> buildGantryBlocks() => [
  manifestBlock(
    'gantry_carriage',
    placement: const [PlacementRule.clickedFace('facing')],
    behavior: BlockBehavior(
      onUseWithoutItem: (server, e) async {
        if (e.sneaking) return BlockUseResult.pass;
        final runtime = ActuatorRuntime.maybe;
        final be = runtime?.store.at(e.targetWorld.getId(), e.pos);
        if (be is GantryCarriageBlockEntity) be.checkValidGantryShaft();
        return BlockUseResult.success;
      },
      onNeighborUpdate: (server, e) async {
        // The carriage cannot survive without a shaft behind it.
        final state = HostBlockGetter.stateOfId(e.stateIndex);
        final facing = state.dir('facing') ?? Direction.north;
        final shaft = HostBlockGetter(e.targetWorld)
            .stateAt((e.pos.x, e.pos.y, e.pos.z).relative(facing.opposite));
        if (shaft.key != gantryShaftKey) {
          await e.targetWorld.breakBlock(e.pos, drop: true);
        }
      },
      onUpdateShape: (server, e) {
        // `cycleAxisIfNecessary`: the axis along first follows the shaft's axis.
        final state = HostBlockGetter.stateOfId(e.stateIndex);
        final facing = state.dir('facing');
        if (facing == null || facing.opposite != toDirection(e.direction))
          return null;
        final other = HostBlockGetter.stateOfId(e.neighborStateId);
        if (other.key != gantryShaftKey) return null;
        final shaftAxis = other.axisOf('facing') ?? Axis.y;
        if (shaftAxis == toDirection(e.direction).axis) return null;
        final valid = getValidGantryShaftAxis(state);
        if (valid == shaftAxis) return null;
        return BlockRegistry.resolveState(state.key, {
          ...state.props,
          'axis_along_first': '${!state.flag('axis_along_first')}',
        });
      },
    ),
  ),
];

/// `GantryCarriageBlock.getValidGantryShaftAxis`: the axis the carriage can ride.
Axis getValidGantryShaftAxis(BState state) {
  final facingAxis = state.dir('facing')?.axis ?? Axis.y;
  final rotationAxis = const DirectionalAxisBlockDef().rotationAxis(
    KState(state.key, state.props),
  );
  for (final axis in Axis.values) {
    if (axis.name != rotationAxis.name && axis != facingAxis) return axis;
  }
  return Axis.y;
}

/// `GantryCarriageBlock.getGantryPinionModifier`.
double getGantryPinionModifier(Direction shaft, Direction pinionDirection) {
  final shaftAxis = shaft.axis;
  final directionModifier = shaft.axisDirection.step;
  if (shaftAxis == Axis.y &&
      (pinionDirection == Direction.north ||
          pinionDirection == Direction.east)) {
    return -directionModifier.toDouble();
  }
  if (shaftAxis == Axis.x &&
      (pinionDirection == Direction.down ||
          pinionDirection == Direction.south)) {
    return -directionModifier.toDouble();
  }
  if (shaftAxis == Axis.z &&
      (pinionDirection == Direction.up || pinionDirection == Direction.west)) {
    return -directionModifier.toDouble();
  }
  return directionModifier.toDouble();
}

/// `GantryCarriageBlockEntity`.
class GantryCarriageBlockEntity extends KineticBlockEntity
    implements AssemblyExceptionHolding {
  GantryCarriageBlockEntity(super.worldId, super.pos);

  bool assembleNextTick = false;
  AssemblyException? lastException;

  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  BState get stateNow =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  /// `checkValidGantryShaft`.
  void checkValidGantryShaft() {
    if (shouldAssemble()) queueAssembly();
  }

  /// `queueAssembly`.
  void queueAssembly() => assembleNextTick = true;

  @override
  void tick() {
    super.tick();
    if (!assembleNextTick) return;
    assembleNextTick = false;
    unawaited(_tryAssemble());
  }

  Future<void> _tryAssemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    final state = stateNow;
    if (state.key != gantryCarriageKey) return;
    final direction = state.dir('facing') ?? Direction.north;

    final shaft = GantryShafts.at(
      worldId,
      localPos.relative(direction.opposite),
    );
    if (shaft == null || shaft.shaftState.key != gantryShaftKey) return;

    final shaftState = shaft.shaftState;
    final speed = shaft.pinionMovementSpeed;
    final shaftOrientation = shaftState.dir('facing') ?? Direction.north;
    final movementDirection = speed < 0
        ? shaftOrientation.opposite
        : shaftOrientation;

    final contraption = GantryContraption(direction);
    try {
      lastException = null;
      if (!await contraption.assemble(level, localPos)) return;
      sendData();
    } on AssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    if (ContraptionCollision.isCollidingWithWorld?.call(
          level,
          contraption,
          localPos.relative(movementDirection),
          movementDirection,
        ) ??
        false) {
      return;
    }

    await contraption.removeBlocksFromWorld(level, posZero);
    final entity = factory.createGantry(worldId, contraption, shaftOrientation);
    entity.setPos(localPos.toVec3());
    factory.spawn(worldId, entity);

    final sequence = shaft.sequenceContext;
    if (sequence != null &&
        sequence.instruction == SequencerInstructions.turnDistance &&
        entity is GantryContraptionEntity) {
      entity.limitMovement(sequence.getEffectiveValue(shaft.theoreticalSpeed));
    }
  }

  bool shouldAssemble() {
    final state = stateNow;
    if (state.key != gantryCarriageKey) return false;
    final facing = (state.dir('facing') ?? Direction.north).opposite;
    final shaft = GantryShafts.at(worldId, localPos.relative(facing));
    if (shaft == null) return false;
    if (shaft.shaftState.key != gantryShaftKey) return false;
    if (shaft.shaftState.flag('powered')) return false;
    return shaft.canAssembleOn;
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
    if (stateTo.block != gantryShaftKey || !stateTo.flag('powered'))
      return defaultModifier;
    final direction = Dir.approximateNearest(diff.x, diff.y, diff.z);
    final facing = stateFrom.dirOf('facing') ?? Dir.north;
    if (facing != direction.opposite) return defaultModifier;
    final shaft = stateTo.dirOf('facing') ?? Dir.north;
    return getGantryPinionModifier(toDirection2(shaft), toDirection2(facing));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  AssemblyException? get lastAssemblyException => lastException;
}

/// Converts a kinetic direction to a vanilla direction.
Direction toDirection2(Dir d) => Direction.values[d.index];
