// What the smart observer sees of this module: the fluid flowing into a pipe
// (`SmartObserverBlockEntity.tick`, the `FluidTransportBehaviour` branch). The detection rule is
// the pure `pipeDetectsFlow`; the probe resolves the behaviour. Registered with the redstone
// module's `RedstoneObservables` in `onServerLoaded`.
import '../api/observable.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart' show PosToHost;
import '../common/pos.dart';
import 'fluid_runtime.dart';
import 'fluid_transport_behaviour.dart';
import 'pipe_connection.dart';

/// `FluidTransportBehaviour.getFlow(side)` for a pipe: whether a fluid the filter accepts is
/// flowing in (`flow.inbound && flow.complete`).
bool pipeDetectsFlow(Iterable<Flow?> flows, ObserverFilter filter) {
  for (final flow in flows) {
    if (flow == null || !flow.inbound || !flow.complete) continue;
    if (filter.testFluid(flow.fluid.fluid)) return true;
  }
  return false;
}

/// The smart observer's pipe branch.
final class PipeObservableProbe implements ObservableProbe {
  const PipeObservableProbe({this._lookup});

  /// The behaviour lookup (`FluidsRuntime` in the plugin, a fake in the tests).
  final FluidTransportBehaviour? Function(String worldId, Pos pos)? _lookup;

  @override
  bool canObserve(String worldId, Pos pos) => _behaviour(worldId, pos) != null;

  @override
  bool? detect(String worldId, Pos pos, ObserverFilter filter) {
    final behaviour = _behaviour(worldId, pos);
    if (behaviour == null) return null;
    return pipeDetectsFlow([for (final side in Direction.values) behaviour.getFlow(side)], filter);
  }

  @override
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) => null;

  @override
  ThresholdObservation? observation(String worldId, Pos pos) => null;

  FluidTransportBehaviour? _behaviour(String worldId, Pos pos) {
    final lookup = _lookup;
    if (lookup != null) return lookup(worldId, pos);
    final runtime = FluidsRuntime.isLoaded ? FluidsRuntime.instance : null;
    if (runtime == null) return null;
    return runtime.store.at(worldId, pos.toBlockPos())?.getBehaviour<FluidTransportBehaviour>();
  }
}
