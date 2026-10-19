// `SignalBlockEntity` (host): the block entity of the train signal. It shows the state of the
// signal boundary it is attached to (through its `TrackTargetingBehaviour`) to the client and to
// the comparator, and reports the redstone power of the block to the boundary.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/block_entity.dart';
import '../graph/edge_point_type.dart';
import '../support/level.dart';
import '../support/runtime.dart';
import '../track/track_targeting_behaviour.dart';
import 'signal_boundary.dart';
import 'signal_types.dart';

export 'signal_types.dart' show OverlayState, SignalState, SignalType;

class SignalBlockEntity extends CreateBlockEntity {
  static const String type = 'create:track_signal';

  late final TrackTargetingBehaviour<SignalBoundary> edgePoint;

  SignalState _state = SignalState.INVALID;
  OverlayState _overlay = OverlayState.SKIP;
  int _switchToRedAfterTrainEntered = 0;
  bool lastReportedPower = false;

  SignalBlockEntity(super.worldId, super.pos) {
    edgePoint = addBehaviour(TrackTargetingBehaviour<SignalBoundary>(EdgePointType.SIGNAL));
  }

  Pos get _pos => pos.toPos();

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putString('State', _state.name);
    tag.putString('Overlay', _overlay.name);
    tag.putBool('Power', lastReportedPower);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    _state = readEnumByName(tag.getString('State') ?? '', SignalState.values);
    _overlay = readEnumByName(tag.getString('Overlay') ?? '', OverlayState.values);
    lastReportedPower = tag.getBool('Power') ?? false;
  }

  /// `getSignal()`.
  SignalBoundary? getSignal() => edgePoint.getEdgePoint();

  /// `isPowered()`: the comparator output.
  bool isPowered() => _state == SignalState.RED;

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;

    final boundary = getSignal();
    if (boundary == null) {
      enterState(SignalState.INVALID);
      setOverlay(OverlayState.RENDER);
      return;
    }

    final lvl = Lvl(w);
    final props = lvl.info(_pos)?.properties;

    if (props != null && props.containsKey('powered')) {
      final powered = props['powered'] == 'true';
      if (lastReportedPower != powered) {
        lastReportedPower = powered;
        boundary.updateBlockEntityPower(_pos, getReportedPower());
        notifyUpdate();
      }
    }

    if (props != null && props.containsKey('type')) {
      final stateType = SignalType.bySerializedName(props['type']);
      final targetType = boundary.getTypeFor(_pos);
      if (stateType != targetType) {
        spawn(() => lvl.setProps(_pos, {'type': targetType.serializedName}, neighbors: true));
      }
    }

    enterState(boundary.getStateFor(_pos));
    setOverlay(boundary.getOverlayFor(_pos));
  }

  /// `getReportedPower()`.
  bool getReportedPower() => lastReportedPower;

  SignalState getState() => _state;

  OverlayState getOverlay() => _overlay;

  void setOverlay(OverlayState state) {
    if (_overlay == state) return;
    _overlay = state;
    notifyUpdate();
  }

  void enterState(SignalState state) {
    if (_switchToRedAfterTrainEntered > 0) _switchToRedAfterTrainEntered--;
    if (_state == state) return;
    if (state == SignalState.RED && _switchToRedAfterTrainEntered > 0) return;
    _state = state;
    _switchToRedAfterTrainEntered = state == SignalState.GREEN || state == SignalState.YELLOW ? 15 : 0;
    notifyUpdate();
  }

  /// `notifyUpdate()`: save and send to the clients.
  void notifyUpdate() {
    sendData();
    // `setChanged()` updates the comparators next to the block
    final w = world;
    if (w != null) spawn(() => w.updateComparators(pos: pos));
  }
}
