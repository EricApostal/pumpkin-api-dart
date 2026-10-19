// `FlowSource`: what sits at the end of a pipe connection (pure): a fluid handler block, another
// pipe, something solid, or an open end (`open_ended_pipe.dart`).
import '../common/data.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';

abstract class FlowSource {
  final BlockFace location;

  FlowSource(this.location);

  /// `provideFluid(extractionPredicate)`: a sample of 1 mB of what the source can give.
  FStack provideFluid(FluidWorld world, bool Function(FStack fluid) extractionPredicate) {
    final tank = provideHandler(world);
    if (tank == null) return FStack.empty;
    final immediate = tank.drain(1, simulate: true);
    if (extractionPredicate(immediate)) return immediate;
    for (var i = 0; i < tank.tanks; i++) {
      final contained = tank.fluidInTank(i);
      if (contained.isEmpty) continue;
      if (!extractionPredicate(contained)) continue;
      return tank.drainFluid(contained.withAmount(1), simulate: true);
    }
    return FStack.empty;
  }

  /// Layer III. Portable fluid interfaces need active attention to prevent them from
  /// disengaging early.
  void keepAlive() {}

  bool get isEndpoint;

  void manageSource(FluidWorld world, PipeNodeView? networkBE) {}

  void whileFlowPresent(FluidWorld world, bool pulling) {}

  /// The handler of the endpoint, `null` if there is none (or it is not an endpoint).
  FluidStorage? provideHandler(FluidWorld world) => null;
}

/// `FlowSource.FluidHandler`: a block with a fluid capability.
class FluidHandlerSource extends FlowSource {
  bool _present = false;

  FluidHandlerSource(super.location);

  @override
  void manageSource(FluidWorld world, PipeNodeView? networkBE) {
    _present = world.hasBlockEntity(location.connectedPos);
  }

  @override
  FluidStorage? provideHandler(FluidWorld world) {
    if (!_present) return null;
    return world.fluidCapability(location.connectedPos, location.oppositeFace);
  }

  @override
  bool get isEndpoint => true;
}

/// `FlowSource.OtherPipe`.
class OtherPipeSource extends FlowSource {
  PipeNodeView? cached;

  OtherPipeSource(super.location);

  @override
  void manageSource(FluidWorld world, PipeNodeView? networkBE) {
    final c = cached;
    if (c != null && !c.isRemoved) return;
    cached = world.pipeAt(location.connectedPos);
  }

  @override
  FStack provideFluid(FluidWorld world, bool Function(FStack fluid) extractionPredicate) {
    final c = cached;
    if (c == null || c.isRemoved) return FStack.empty;
    final provided = c.getProvidedOutwardFluid(location.oppositeFace);
    return extractionPredicate(provided) ? provided : FStack.empty;
  }

  @override
  bool get isEndpoint => false;
}

/// `FlowSource.Blocked`.
class BlockedSource extends FlowSource {
  BlockedSource(super.location);

  @override
  bool get isEndpoint => false;
}
