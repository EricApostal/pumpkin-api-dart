// The block state rules of the pipe blocks (pure): which block is what, which faces are open,
// the straight axis of a pipe, rotation and mirroring. `FluidPipeBlock`, `AxisPipeBlock`,
// `EncasedPipeBlock`, `GlassFluidPipeBlock`, `SmartFluidPipeBlock`, `FluidValveBlock`, `PumpBlock`.
import '../api/block_state.dart';
import '../common/direction.dart';

abstract final class PipeKeys {
  static const String fluidPipe = 'create:fluid_pipe';
  static const String encasedPipe = 'create:encased_fluid_pipe';
  static const String glassPipe = 'create:glass_fluid_pipe';
  static const String smartPipe = 'create:smart_fluid_pipe';
  static const String valve = 'create:fluid_valve';
  static const String pump = 'create:mechanical_pump';
  static const String hosePulley = 'create:hose_pulley';
  static const String fluidTank = 'create:fluid_tank';
  static const String creativeFluidTank = 'create:creative_fluid_tank';
  static const String spout = 'create:spout';
  static const String itemDrain = 'create:item_drain';
  static const String steamEngine = 'create:steam_engine';
  static const String steamWhistle = 'create:steam_whistle';
  static const String copperCasing = 'create:copper_casing';

  /// Blocks that are `LiquidBlock`s.
  static const Set<String> liquidBlocks = {
    'minecraft:water',
    'minecraft:lava',
    'create:honey',
    'create:chocolate',
  };
}

abstract final class PipeBlocks {
  /// `FluidPipeBlock.isPipe`.
  static bool isPipe(BState s) => s.key == PipeKeys.fluidPipe;

  static bool isEncased(BState s) => s.key == PipeKeys.encasedPipe;

  /// `instanceof AxisPipeBlock` (the glass pipe).
  static bool isAxisPipe(BState s) => s.key == PipeKeys.glassPipe;

  /// `PumpBlock.isPump`.
  static bool isPump(BState s) => s.key == PipeKeys.pump;

  static bool isValve(BState s) => s.key == PipeKeys.valve;

  static bool isSmartPipe(BState s) => s.key == PipeKeys.smartPipe;

  static bool isLiquidBlock(BState s) => PipeKeys.liquidBlocks.contains(s.key);

  static bool isTank(BState s) => s.key == PipeKeys.fluidTank || s.key == PipeKeys.creativeFluidTank;

  /// `PumpBlock.FACING`.
  static Direction pumpFacing(BState s) => s.dir('facing') ?? Direction.north;

  /// `FluidPipeBlock.isOpenAt` / `EncasedPipeBlock` property by direction.
  static bool isOpenAtSixWay(BState s, Direction d) => s.flag(d.serializedName);

  /// `AxisPipeBlock.isOpenAt`.
  static bool isOpenAtAxis(BState s, Direction d) => d.axis == (s.axisOf('axis') ?? Axis.y);

  /// `PumpBlock.isOpenAt`.
  static bool isOpenAtPump(BState s, Direction d) => d.axis == pumpFacing(s).axis;

  /// `FluidValveBlock.getPipeAxis`: the axis the valve passes fluid along.
  static Axis valvePipeAxis(BState state) {
    final facing = state.dir('facing') ?? Direction.north;
    var alongFirst = !state.flag('axis_along_first');
    for (final axis in Axis.values) {
      if (axis == facing.axis) continue;
      if (!alongFirst) {
        alongFirst = true;
        continue;
      }
      return axis;
    }
    throw StateError('Impossible axis.');
  }

  /// `SmartFluidPipeBlock.getPipeAxis`.
  static Axis smartPipeAxis(BState state) =>
      state['face'] == 'wall' ? Axis.y : (state.dir('facing') ?? Direction.north).axis;

  /// `IAxisPipe.getAxisOf`: glass pipes, valves and smart pipes.
  static Axis? axisOfPipe(BState state) {
    if (isAxisPipe(state)) return state.axisOf('axis');
    if (isValve(state)) return valvePipeAxis(state);
    if (isSmartPipe(state)) return smartPipeAxis(state);
    return null;
  }

  /// `FluidPropagator.getStraightPipeAxis`.
  static Axis? straightPipeAxis(BState state) {
    if (isPump(state)) return pumpFacing(state).axis;
    if (isAxisPipe(state)) return state.axisOf('axis');
    if (!isPipe(state)) return null;

    Axis? axisFound;
    var connections = 0;
    for (final axis in Axis.values) {
      final d1 = Direction.fromAxisAndDirection(axis, AxisDirection.negative);
      final d2 = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
      final openAt1 = isOpenAtSixWay(state, d1);
      final openAt2 = isOpenAtSixWay(state, d2);
      if (openAt1) connections++;
      if (openAt2) connections++;
      if (openAt1 && openAt2) {
        if (axisFound != null) return null;
        axisFound = axis;
      }
    }
    return connections == 2 ? axisFound : null;
  }

  /// Whether the pipe block [s] is open towards [d] by its own rules, for the blocks that react
  /// to neighbour changes (`isOpenAt` of each block class). `false` for other blocks.
  static bool isOpenAt(BState s, Direction d) {
    if (isPipe(s)) return isOpenAtSixWay(s, d);
    if (isEncased(s)) return isOpenAtSixWay(s, d);
    if (isAxisPipe(s)) return isOpenAtAxis(s, d);
    if (isPump(s)) return isOpenAtPump(s, d);
    if (isValve(s)) return d.axis == valvePipeAxis(s);
    if (isSmartPipe(s)) return d.axis == smartPipeAxis(s);
    return false;
  }

  /// `FluidPipeBlockRotation.rotate`.
  static BState rotate(BState state, BlockRotation rotation) {
    var rotated = state;
    for (final direction in Direction.horizontals) {
      rotated = rotated.setFlag(rotation.rotate(direction).serializedName, state.flag(direction.serializedName));
    }
    return rotated;
  }

  /// `FluidPipeBlockRotation.mirror`.
  static BState mirror(BState state, BlockMirror mirror) {
    var mirrored = state;
    for (final direction in Direction.horizontals) {
      mirrored = mirrored.setFlag(mirror.mirrorDirection(direction).serializedName, state.flag(direction.serializedName));
    }
    return mirrored;
  }

  /// `FluidPipeBlockRotation.transform` for a rotation of [rotation] around [rotationAxis] and an
  /// optional mirror.
  static BState transform(BState state, {BlockRotation rotation = BlockRotation.none, Axis rotationAxis = Axis.y, BlockMirror? mirror}) {
    var s = state;
    if (mirror != null && mirror != BlockMirror.none) s = PipeBlocks.mirror(s, mirror);
    if (rotationAxis == Axis.y) return rotate(s, rotation);
    var rotated = s;
    for (final direction in Direction.values) {
      rotated = rotated.setFlag(_rotateAround(direction, rotationAxis, rotation).serializedName, s.flag(direction.serializedName));
    }
    return rotated;
  }

  static Direction _rotateAround(Direction d, Axis axis, BlockRotation rotation) {
    var out = d;
    for (var i = 0; i < rotation.quarterTurns; i++) {
      out = out.clockWiseAround(axis);
    }
    return out;
  }

  /// `EncasedPipeBlock.transferSixWayProperties`.
  static BState transferSixWayProperties(BState from, BState to) {
    var t = to;
    for (final d in Direction.values) {
      t = t.setFlag(d.serializedName, from.flag(d.serializedName));
    }
    return t;
  }

  /// A fluid pipe state open exactly along [axis] (`FluidPipeBlock.getAxisState`).
  static BState axisState(BState defaultState, Axis axis) {
    var s = defaultState;
    for (final d in Direction.values) {
      s = s.setFlag(d.serializedName, d.axis == axis);
    }
    return s;
  }

  /// `SmartFluidPipeBlock` / `FluidValveBlock` / `PumpBlock` are not mirrored by the pipe rules.
}
