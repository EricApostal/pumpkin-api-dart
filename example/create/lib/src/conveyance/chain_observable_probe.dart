// What the smart observer sees of a chain conveyor: the packages looping on it
// (`ChainConveyorBlockEntity.getLoopingPackages`). Registered with the redstone module's
// `RedstoneObservables` in `onServerLoaded`.
import '../api/observable.dart';
import '../common/pos.dart';
import 'chain/chain_conveyor_block_entity.dart';
import 'observable_detection.dart';
import 'runtime.dart';

/// `SmartObserverBlockEntity.tick`'s chain conveyor branch.
final class ChainConveyorObservableProbe implements ObservableProbe {
  const ChainConveyorObservableProbe();

  static ChainConveyorBlockEntity? _be(String worldId, Pos pos) =>
      ConveyanceRuntime.loaded ? ConveyanceRuntime.i.beAt(worldId, pos) as ChainConveyorBlockEntity? : null;

  @override
  bool canObserve(String worldId, Pos pos) => _be(worldId, pos) != null;

  @override
  bool? detect(String worldId, Pos pos, ObserverFilter filter) {
    final be = _be(worldId, pos);
    if (be == null) return null;
    return chainLoopingAddresses(be.loopingPackages.map((box) => box.item), filter).isNotEmpty;
  }

  @override
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) {
    final be = _be(worldId, pos);
    if (be == null) return null;
    return chainLoopingAddresses(be.loopingPackages.map((box) => box.item), filter);
  }

  @override
  ThresholdObservation? observation(String worldId, Pos pos) => null;
}
