// The block entities of the pipes, the mechanical pump and the fluid valve.
// The connection logic is in `fluid_transport_behaviour.dart`; this file adds
// the block entity state (the smart pipe's filter, the valve's pointer) and the
// pump's pressure distribution.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show HostBlockGetter;
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../decoration/bracketed_behaviour.dart';
import '../kinetics/geometry.dart' show Dir;
import '../kinetics/kinetic_block_entity.dart';
import '../processing/common/stack.dart';
import '../processing/host/stack_host.dart';
import 'fluid_host.dart';
import 'fluid_propagator.dart';
import 'fluid_runtime.dart';
import 'fluid_transport_behaviour.dart';
import 'fluid_world.dart';
import 'lerped_float_nbt.dart';
import 'pipe_blocks.dart';
import 'pump_logic.dart';

/// The [Dir] of the kinetic logic for a [Direction] (both use Minecraft's enum order).
Dir toKineticDir(Direction d) => Dir.values[d.index];

/// The [Direction] of the fluid logic for a [Dir].
Direction toFluidDir(Dir d) => Direction.values[d.index];

/// The block state of [be] as the fluid logic sees it.
BState blockStateOf(CreateBlockEntity be) {
  final w = be.world;
  if (w == null) return BState.air;
  return HostBlockGetter.stateOfId(w.getBlockStateId(pos: be.pos));
}

/// `FluidPipeBlockEntity`.
class FluidPipeBlockEntity extends CreateBlockEntity {
  FluidPipeBlockEntity(super.worldId, super.pos) {
    addBehaviour(StandardPipeTransportBehaviour());
    // `FluidPipeBlockEntity.canHaveBracket`: the encased pipe has no bracket.
    addBehaviour(
      BracketedBlockEntityBehaviour(
        canHave: (state) => !PipeBlocks.isEncased(state),
      ),
    );
  }

  FluidTransportBehaviour get transport =>
      getBehaviour<FluidTransportBehaviour>()!;
}

/// `StraightPipeBlockEntity`.
class StraightPipeBlockEntity extends CreateBlockEntity {
  StraightPipeBlockEntity(super.worldId, super.pos) {
    addBehaviour(createTransportBehaviour());
    if (addsBracket) addBehaviour(BracketedBlockEntityBehaviour());
  }

  /// `StraightPipeBlockEntity.addBehaviours` adds the bracket; the smart pipe
  /// (`SmartFluidPipeBlockEntity`) does not.
  bool get addsBracket => true;

  /// The behaviour of the block; subclasses replace it.
  FluidTransportBehaviour createTransportBehaviour() =>
      StraightPipeTransportBehaviour();

  FluidTransportBehaviour get transport =>
      getBehaviour<FluidTransportBehaviour>()!;
}

/// `SmartFluidPipeBlockEntity`: a straight pipe with a fluid filter.
class SmartFluidPipeBlockEntity extends StraightPipeBlockEntity {
  SmartFluidPipeBlockEntity(super.worldId, super.pos);

  @override
  bool get addsBracket => false;

  /// The fluid the filter accepts, `null` for any fluid (`FilteringBehaviour.forFluids`).
  String? filterFluid;

  /// The data of the filtered fluid (the potion type): two potions are different fluids.
  List<int>? filterData;

  /// The filter holds an item that has no fluid (`FilterItemStack.test(FluidStack)` is then
  /// `false` for every fluid). `false` means there is no filter at all, which accepts anything.
  bool filterMatchesNothing = false;

  /// The item of a "matches no fluid" filter. `FilteringBehaviour.write` persists the filter
  /// *item* and `FilterItemStack.test(FluidStack)` re-derives "no fluid" from it, so the item is
  /// what carries this filter across a reload; the port derives the fluid from the item, so the
  /// item has to be kept as well (see [write]).
  String? filterItem;

  /// `FilteringBehaviour.setFilter` with a fluid.
  void setFilterFluid(String? fluid, [List<int>? data]) {
    filterFluid = fluid;
    filterData = data;
    filterItem = null;
    filterMatchesNothing = false;
  }

  /// `FilteringBehaviour.setFilter` with an item that holds no fluid.
  void setFilterMatchesNothing(String item) {
    filterItem = item;
    filterFluid = null;
    filterData = null;
    filterMatchesNothing = true;
  }

  @override
  FluidTransportBehaviour createTransportBehaviour() =>
      SmartPipeTransportBehaviour();

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    // `FilteringBehaviour.forFluids` stores the item (a bucket, or a potion bottle); the fluid is
    // derived from it. Virtual fluids have no bucket item, so their id is kept in `FilterFluid`
    // (a plugin-private key) to survive the round trip.
    filterFluid = tag.getString('FilterFluid');
    filterData = tag.getIntArray('FilterFluidData');
    filterItem = null;
    filterMatchesNothing = false;
    if (filterFluid == null) {
      final stack = StackNbt.read(tag.getCompound('Filter'));
      if (stack.isNotEmpty) {
        final fluid = FluidRegistries.fromBucket(stack.key);
        if (fluid == null) {
          filterItem = stack.key;
          filterMatchesNothing = true;
        } else {
          filterFluid = fluid.fluid;
          filterData = fluid.data;
        }
      }
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final fluid = filterFluid;
    final bucket = fluid == null ? null : FluidRegistries.bucketFor(fluid);
    // `FilteringBehaviour.write` writes the filter item itself; a fluid-less item *is* the filter
    // ("matches no fluid"), so it has to go out again or the next read sees no filter at all.
    final item = bucket ?? filterItem;
    tag.putCompound(
      'Filter',
      item == null ? NbtCompound() : StackNbt.write(PStack(item, 1)),
    );
    if (fluid != null && bucket == null) tag.putString('FilterFluid', fluid);
    final data = filterData;
    if (fluid != null && data != null && data.isNotEmpty) {
      tag.putIntArray('FilterFluidData', data);
    }
    // `FilteringBehaviour.write` always writes the count; the smart pipe's slot shows no count.
    tag.putInt('FilterAmount', 64);
    tag.putBool('UpTo', true);
  }
}

/// `FluidValveBlockEntity`: opens and closes with its speed.
class FluidValveBlockEntity extends KineticBlockEntity {
  FluidValveBlockEntity(super.worldId, super.pos) {
    addBehaviour(ValveTransportBehaviour());
  }

  /// `pointer`: the lerped position of the valve (0 closed, 1 open).
  double pointer = 0;

  /// `getChaseSpeed`.
  double get chaseSpeed => (speed.abs() / 16 / 20).clamp(0.0, 1.0);

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    sendData();
  }

  @override
  void tick() {
    super.tick();

    // `pointer.tickChaser()` (linear).
    final target = speed > 0 ? 1.0 : 0.0;
    final step = chaseSpeed;
    final diff = target - pointer;
    if (diff.abs() <= step) {
      pointer = target;
    } else {
      pointer += diff.sign * step;
    }

    final state = blockState;
    if (!state.block.endsWith('fluid_valve')) return;
    final open = state.flag('enabled');
    if (open && pointer == 0) {
      unawaited(switchToState(state.setFlag('enabled', false)));
      return;
    }
    if (!open && pointer == 1) {
      unawaited(switchToState(state.setFlag('enabled', true)));
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    LerpedFloatNbt.write(
      tag,
      'Pointer',
      pointer,
      target: speed > 0 ? 1 : 0,
      speed: chaseSpeed,
    );
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    pointer = LerpedFloatNbt.read(tag, 'Pointer');
  }
}

/// `PumpBlockEntity`: a kinetic block entity that distributes pressure over the
/// pipes on its two faces.
class PumpBlockEntity extends KineticBlockEntity implements PumpPeer {
  PumpBlockEntity(super.worldId, super.pos) {
    addBehaviour(PumpTransportBehaviour());
  }

  /// `sidesToUpdate`: the front and back need a new pressure distribution.
  final List<bool> sidesToUpdate = [false, false];

  /// `pressureUpdate`.
  bool pressureUpdate = false;

  /// `scheduleFlip`: a `Reversed` tag from an older save flips the block.
  bool scheduleFlip = false;

  FluidTransportBehaviour get transport =>
      getBehaviour<FluidTransportBehaviour>()!;

  /// The pump's facing direction (`PumpBlock.FACING`).
  Direction get facing => PipeBlocks.pumpFacing(blockStateOf(this));

  Pos get posOf => (this.pos.x, this.pos.y, this.pos.z);

  HostFluidWorld get fluidWorld => FluidsRuntime.instance.levelOf(worldId)!;

  @override
  void tick() {
    super.tick();

    if (scheduleFlip) {
      scheduleFlip = false;
      unawaited(
        switchToState(
          blockState.set('facing', toKineticDir(facing.opposite).name),
        ),
      );
      return;
    }

    for (final front in const [true, false]) {
      if (!sidesToUpdate[front ? 0 : 1]) continue;
      sidesToUpdate[front ? 0 : 1] = false;
      distributePressureTo(front ? facing : facing.opposite);
    }
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (previousSpeed.abs() == speed.abs()) return;
    if (speed != 0) awardAdvancement('pump');
    updatePressureChange();
  }

  /// `updatePressureChange()`.
  void updatePressureChange() {
    pressureUpdate = false;
    final level = fluidWorld;
    final front = posOf.relative(facing);
    final back = posOf.relative(facing.opposite);
    FluidPropagator.propagateChangedPipe(level, front, level.stateAt(front));
    FluidPropagator.propagateChangedPipe(level, back, level.stateAt(back));
    transport.wipePressure();
    sidesToUpdate[0] = true;
    sidesToUpdate[1] = true;
  }

  /// `distributePressureTo(side)`.
  void distributePressureTo(Direction side) {
    if (speed == 0) return;
    PumpLogic.distributePressureTo(
      fluidWorld,
      posOf,
      speed,
      side,
      pull: isPullingOnSide(isFront(side)),
    );
  }

  @override
  bool isFront(Direction side) => side == facing;

  @override
  bool isPullingOnSide(bool front) => !front;

  @override
  void updatePipesOnSide(Direction side) {
    if (!isSideAccessible(side)) return;
    sidesToUpdate[isFront(side) ? 0 : 1] = true;
    transport.wipePressure();
  }

  /// `isSideAccessible(side)`.
  bool isSideAccessible(Direction side) => facing.axis == side.axis;

  /// `award(advancement)` for the pump.
  void awardAdvancement(String advancement) =>
      FluidsRuntime.instance.award(worldId, posOf, advancement);

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.getBool('Reversed') ?? false) scheduleFlip = true;
  }
}
