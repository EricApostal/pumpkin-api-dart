// What other modules tell the smart observer and the threshold switch about their block
// entities (`ObservableProbe`), kept free of the host bindings so the pure detection logic and
// its tests can use it.
import '../common/pos.dart';
import '../redstone/support/text.dart' show Txt;

/// Something the smart observer / threshold switch can look at besides item and fluid containers
/// (belts and depots with `TransportedItemStackHandlerBehaviour`, pipes with
/// `FluidTransportBehaviour`, chain conveyors, funnels). Register with
/// [RedstoneObservables.register] in `onServerLoaded`.
abstract interface class ObservableProbe {
  /// Whether the block entity at [pos] is something this probe observes (placement uses it to pick the
  /// observer's direction).
  bool canObserve(String worldId, Pos pos);

  /// `SmartObserverBlockEntity.tick` detection: `null` if the probe does not handle [pos]; else
  /// whether an item or fluid accepted by the filter is passing now.
  bool? detect(String worldId, Pos pos, ObserverFilter filter);

  /// Packages looping on a chain conveyor at [pos] that pass the filter (`getLoopingPackages`):
  /// their addresses; `null` if the probe does not handle [pos].
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) => null;

  /// `ThresholdSwitchObservable` of the block entity at [pos]: `null` if it is not observable.
  ThresholdObservation? observation(String worldId, Pos pos) => null;
}

/// The filter an observer applies (`FilteringBehaviour.test`).
abstract interface class ObserverFilter {
  bool get isEmpty;
  bool testItem(String itemKey);
  bool testFluid(String fluidKey);
}

/// `ThresholdSwitchObservable`: a value a threshold switch can watch (a pulley's rope length).
final class ThresholdObservation {
  final int min;
  final int max;
  final int current;
  final Txt Function(int value) format;

  const ThresholdObservation({required this.min, required this.max, required this.current, required this.format});
}

/// The service that collects the [ObservableProbe]s.
abstract interface class RedstoneObservables {
  void register(ObservableProbe probe);
}
