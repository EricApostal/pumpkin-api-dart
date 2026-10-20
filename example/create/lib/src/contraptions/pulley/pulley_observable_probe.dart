// The threshold switch's view of a rope pulley (`PulleyBlockEntity implements
// ThresholdSwitchObservable`): the Y level the rope reaches. Registered with the redstone
// module's `RedstoneObservables` in `onServerLoaded`.
import '../../api/observable.dart';
import '../../common/host_bridge.dart' show PosToHost;
import '../../common/pos.dart';
import '../../redstone/support/text.dart' show Txt;
import '../blocks/actuator_runtime.dart';
import 'pulley_block_entity.dart';

/// `PulleyBlockEntity.getCurrentValue/getMinValue/getMaxValue/format`.
final class PulleyObservableProbe implements ObservableProbe {
  const PulleyObservableProbe();

  @override
  bool canObserve(String worldId, Pos pos) => _pulley(worldId, pos) != null;

  @override
  bool? detect(String worldId, Pos pos, ObserverFilter filter) => null;

  @override
  List<String>? loopingPackageAddresses(String worldId, Pos pos, ObserverFilter filter) => null;

  @override
  ThresholdObservation? observation(String worldId, Pos pos) {
    final pulley = _pulley(worldId, pos);
    if (pulley == null) return null;
    final world = ActuatorRuntime.instance.worlds.byId(worldId);
    if (world == null) return null;
    return ThresholdObservation(
      min: world.minY,
      max: pos.$2,
      // `worldPosition.getY() - (int) getInterpolatedOffset(.5f)`.
      current: pos.$2 - pulley.getInterpolatedOffset(.5).truncate(),
      format: (value) => Txt.translate('create.gui.threshold_switch.pulley_y_level', [Txt.literal('$value')]),
    );
  }

  static PulleyBlockEntity? _pulley(String worldId, Pos pos) {
    final runtime = ActuatorRuntime.maybe;
    if (runtime == null) return null;
    return runtime.store.typed<PulleyBlockEntity>(worldId, pos.toBlockPos());
  }
}
