// `OpenEndedPipe` (pure): the open end of a pipe. It places fluid sources into the world, takes
// them out of it, and applies the effects of the spilled fluid to the entities below. It acts as
// a tank of 1000 mB for the pipe network. Create 26.x does this inside a transaction; without
// transactions the world changes are applied when the call is not a simulation.
import '../api/effect/open_pipe_effect_handler.dart' as api_effect;
import '../common/bounds.dart';
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'flow_source.dart';
import 'fluid_helper.dart';
import 'fluid_reactions.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'nbt_util.dart';
import 'open_pipe_effects.dart';
import 'vanilla_fluid_targets.dart';

class OpenEndedPipe extends FlowSource {
  FluidWorld? _world;
  final Pos pos;
  final Pos outputPos;
  late final Aabb aoe;
  late final OpenEndFluidHandler fluidHandler;
  bool wasPulling = false;

  OpenEndedPipe(BlockFace face)
    : pos = face.pos,
      outputPos = face.connectedPos,
      super(face) {
    var box = Aabb.ofBlock(outputPos).expandTowards(0, -1, 0);
    if (face.face == Direction.down) box = box.expandTowards(0, -1, 0);
    aoe = box;
    fluidHandler = OpenEndFluidHandler(this);
  }

  FluidWorld? get world => _world;

  @override
  void manageSource(FluidWorld world, PipeNodeView? networkBE) {
    _world = world;
  }

  @override
  FluidStorage? provideHandler(FluidWorld world) {
    _world ??= world;
    return fluidHandler;
  }

  @override
  bool get isEndpoint => true;

  NbtValue serializeNbt() => NbtValue.compound({
    'Fluid': FluidNbt.write(fluidHandler.fluid),
    'Pulling': NbtValue.byte(wasPulling ? 1 : 0),
    'Location': NbtValue.compound({
      'pos': posToNbt(location.pos),
      'direction': NbtValue.string(location.face.serializedName),
    }),
  });

  static OpenEndedPipe fromNbt(
    Map<String, NbtValue> compound,
    Pos blockEntityPos,
    Direction fallbackSide,
  ) {
    var face = fallbackSide;
    final loc = compound.readCompound('Location');
    if (loc != null) {
      final name =
          loc.readString('direction') ??
          loc.readString('face') ??
          loc.readString('Face');
      if (name != null) {
        face = Direction.values.firstWhere(
          (d) => d.serializedName == name.toLowerCase(),
          orElse: () => fallbackSide,
        );
      }
    }
    final oep = OpenEndedPipe(BlockFace(blockEntityPos, face));
    oep.fluidHandler.setFluid(FluidNbt.read(compound['Fluid']));
    oep.wasPulling = compound.readBool('Pulling');
    return oep;
  }

  /// `removeFluidFromSpace(simulate)`.
  FStack removeFluidFromSpace({required bool simulate}) {
    final world = _world;
    if (world == null) return FStack.empty;
    if (!world.isLoaded(outputPos)) return FStack.empty;

    final state = world.stateAt(outputPos);
    final fluidState = world.fluidAt(outputPos);
    final waterlog = state.has('waterlogged');

    final drainBlock = VanillaFluidTargets.drainBlock(
      world,
      outputPos,
      state,
      simulate: simulate,
    );
    if (drainBlock.isNotEmpty) {
      if (!simulate &&
          state.has('honey_level') &&
          drainBlock.fluid == FluidKeys.honey)
        world.award(pos, 'honey_drain');
      return drainBlock;
    }

    if (!waterlog && !world.canBeReplaced(outputPos)) return FStack.empty;
    if (fluidState.isEmpty || !fluidState.isSource) return FStack.empty;

    final stack = FStack(fluidState.fluid, 1000);
    if (simulate) return stack;

    if (FluidHelper.isWater(stack.fluid)) world.award(pos, 'water_supply');

    if (waterlog) {
      world.setBlock(outputPos, state.setFlag('waterlogged', false));
      world.scheduleFluidTick(outputPos, FluidKeys.water, 1);
    } else {
      world.pickupFluidSource(outputPos);
    }
    return stack;
  }

  /// `provideFluidToSpace(fluid, simulate)`.
  bool provideFluidToSpace(FStack fluid, {required bool simulate}) {
    final world = _world;
    if (world == null) return false;
    if (!world.isLoaded(outputPos)) return false;

    final state = world.stateAt(outputPos);
    final fluidState = world.fluidAt(outputPos);
    final waterlog = state.has('waterlogged');

    if (!waterlog && !world.canBeReplaced(outputPos)) return false;
    if (fluid.isEmpty) return false;
    if (!FluidHelper.hasBlockState(fluid.fluid)) return true;

    if (!fluidState.isEmpty &&
        FluidHelper.convertToStill(fluidState.fluid) !=
            FluidHelper.convertToStill(fluid.fluid)) {
      FluidReactions.handlePipeSpillCollision(
        world,
        outputPos,
        fluid.fluid,
        fluidState,
      );
      return false;
    }

    if (fluidState.isSource) return false;
    if (waterlog && fluid.fluid != FluidKeys.water) return false;
    if (simulate) return true;

    if (!world.config.pipesPlaceFluidSourceBlocks) return true;

    if (world.waterEvaporates && FluidHelper.isWater(fluid.fluid)) {
      final r = world.nextDouble() - world.nextDouble();
      world.playSound(
        outputPos,
        'minecraft:block.fire.extinguish',
        volume: 0.5,
        pitch: 2.6 + r * 0.8,
      );
      return true;
    }

    if (waterlog) {
      world.setBlock(outputPos, state.setFlag('waterlogged', true));
      world.scheduleFluidTick(outputPos, FluidKeys.water, 1);
      return true;
    }

    world.placeFluidSource(outputPos, FluidKeys.still(fluid.fluid));
    return true;
  }

  /// Whether `provideFluidToSpace(fluid, false)` would change the world.
  bool changesWorld(FStack fluid) {
    final world = _world;
    if (world == null) return false;
    if (fluid.isEmpty || !FluidHelper.hasBlockState(fluid.fluid)) return false;
    if (!world.config.pipesPlaceFluidSourceBlocks) return false;
    return !(world.waterEvaporates && FluidHelper.isWater(fluid.fluid));
  }
}

/// `OpenEndedPipe.OpenEndFluidHandler`: a tank of 1000 mB that spills into and pulls from the
/// world.
class OpenEndFluidHandler extends FluidTank {
  final OpenEndedPipe _pipe;

  OpenEndFluidHandler(this._pipe) : super(1000);

  /// Effects of fluids are looked up in [OpenPipeEffects] (`OpenPipeEffectHandler.REGISTRY`),
  /// including handlers registered through the public API; the application itself is the
  /// world's (`FluidWorld.applyOpenPipeEffect`).
  bool _hasEffect(FluidWorld world, String fluid) =>
      api_effect.OpenPipeEffects.of(FluidKeys.still(fluid)) != null ||
      OpenPipeEffects.ofWorld(world, fluid) != null;

  @override
  int fill(FStack resource, {required bool simulate}) {
    final world = _pipe.world;
    // Never allow being filled when a source is attached
    if (world == null) return 0;
    if (!world.isLoaded(_pipe.outputPos)) return 0;
    if (resource.isEmpty) return 0;

    if (!_pipe.provideFluidToSpace(resource, simulate: true)) return 0;
    if (simulate) {
      final replaced = fluid.isNotEmpty && !fluid.isSameFluid(resource);
      final toFill =
          _hasEffect(world, resource.fluid) &&
              !FluidHelper.hasBlockState(fluid.fluid)
          ? 1
          : resource.amount;
      final room = capacity - (replaced ? 0 : fluidAmount);
      final f = toFill < room ? toFill : room;
      return !isValidStack(resource) || f < 0 ? 0 : f;
    }

    final containedFluidStack = fluid;
    final hasBlockState = FluidHelper.hasBlockState(containedFluidStack.fluid);
    var containedWasReplaced = false;
    if (containedFluidStack.isNotEmpty &&
        !containedFluidStack.isSameFluid(resource)) {
      setFluid(FStack.empty);
      containedWasReplaced = true;
    }

    if (_pipe.wasPulling) _pipe.wasPulling = false;

    final effect = _hasEffect(world, resource.fluid);
    var toFill = resource.amount;
    if (effect && !hasBlockState) toFill = 1;

    final current = fluid;
    var filled = toFill < capacity - current.amount
        ? toFill
        : capacity - current.amount;
    if (!isValidStack(resource) || filled < 0) filled = 0;
    if (filled > 0) setFluid(resource.withAmount(current.amount + filled));

    if (effect)
      world.applyOpenPipeEffect(resource.withAmount(toFill), _pipe.aoe);

    if (fluidAmount == 1000 || !hasBlockState) {
      final FStack toPlace;
      if (containedFluidStack.isEmpty) {
        toPlace = FStack.empty;
      } else if (containedWasReplaced) {
        toPlace = containedFluidStack;
      } else {
        toPlace = fluid;
      }
      if (_pipe.provideFluidToSpace(toPlace, simulate: true)) {
        setFluid(FStack.empty);
        _pipe.provideFluidToSpace(toPlace, simulate: false);
      }
    }
    return filled;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty) return FStack.empty;
    return _drainInner(resource.amount, resource, simulate);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) =>
      _drainInner(maxDrain, null, simulate);

  FStack _drainInner(int amountIn, FStack? filter, bool simulate) {
    final world = _pipe.world;
    if (world == null) return FStack.empty;
    if (!world.isLoaded(_pipe.outputPos)) return FStack.empty;
    if (amountIn <= 0) return FStack.empty;
    final amount = amountIn > 1000 ? 1000 : amountIn;

    if (!simulate && !_pipe.wasPulling) _pipe.wasPulling = true;

    final fromInternal = _drainFromTank(amount, filter, simulate);
    if (fromInternal.isNotEmpty) return fromInternal;

    final drainedFromWorld = _pipe.removeFluidFromSpace(simulate: true);
    if (drainedFromWorld.isEmpty) return FStack.empty;
    if (filter != null &&
        !drainedFromWorld.isSameFluid(
          filter.withAmount(drainedFromWorld.amount),
        ))
      return FStack.empty;

    final remainder = drainedFromWorld.amount - amount;
    final result = drainedFromWorld.withAmount(
      amount < drainedFromWorld.amount ? amount : drainedFromWorld.amount,
    );
    if (simulate) return result;

    if (remainder > 0) {
      if (fluid.isNotEmpty && !fluid.isSameFluid(drainedFromWorld))
        setFluid(FStack.empty);
      final newAmount = capacity < fluidAmount + remainder
          ? capacity
          : fluidAmount + remainder;
      setFluid(drainedFromWorld.withAmount(newAmount));
    }
    _pipe.removeFluidFromSpace(simulate: false);
    return result;
  }

  FStack _drainFromTank(int amount, FStack? filter, bool simulate) {
    final contained = fluid;
    if (contained.isEmpty) return FStack.empty;
    if (filter != null &&
        !contained.isSameFluid(filter.withAmount(contained.amount)))
      return FStack.empty;
    final drained = amount < contained.amount ? amount : contained.amount;
    final result = contained.withAmount(drained);
    if (!simulate) {
      final left = contained.amount - drained;
      setFluid(left <= 0 ? FStack.empty : contained.withAmount(left));
    }
    return result;
  }
}
