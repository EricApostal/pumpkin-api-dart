// What the smart observer sees of the items on this module's belts and depots
// (`TransportedItemStackHandlerBehaviour`): the detection rule is the pure
// `observable_detection.dart`, this probe only resolves the block entities. Kept free of the
// host bindings so the rule is testable on the VM; registered with the redstone module's
// `RedstoneObservables` in `onServerLoaded`.
import '../api/observable.dart';
import '../common/pos.dart';
import 'behaviours/belt_interfaces.dart';
import 'observable_detection.dart';

/// The block entity lookup of a probe (`ConveyanceRuntime.beAt` in the plugin).
typedef ProbeLookup = Object? Function(String worldId, Pos pos);

/// `SmartObserverBlockEntity.tick`'s item detection: the `TransportedItemStackHandlerBehaviour`
/// of a belt segment or a depot.
final class BeltObservableProbe implements ObservableProbe {
  const BeltObservableProbe({required this._lookup, this.alsoObserves});

  final ProbeLookup _lookup;

  /// `SmartObserverBlock.getStateForPlacement` also snaps to a funnel, which is not a
  /// [TransportedItemStackHandler]; the module passes the check.
  final bool Function(Object be)? alsoObserves;

  @override
  bool canObserve(String worldId, Pos pos) {
    final be = _lookup(worldId, pos);
    if (be == null) return false;
    return be is TransportedItemStackHandler || (alsoObserves?.call(be) ?? false);
  }

  @override
  bool? detect(String worldId, Pos pos, ObserverFilter filter) {
    final be = _lookup(worldId, pos);
    if (be is! TransportedItemStackHandler) return null;
    return beltDetects(be, filter);
  }

  @override
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) => null;

  @override
  ThresholdObservation? observation(String worldId, Pos pos) => null;
}
