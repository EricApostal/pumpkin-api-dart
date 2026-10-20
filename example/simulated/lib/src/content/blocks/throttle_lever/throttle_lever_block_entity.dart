// The block entity of the throttle lever: a redstone source the player drags
// between 0 and 15.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.throttle_lever.ThrottleLeverBlockEntity
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/core/block_entity.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../util/host_calls.dart' show ignoredCall;

import 'throttle_lever_logic.dart';

/// `ThrottleLeverBlockEntity`.
final class ThrottleLeverBlockEntity extends CreateBlockEntity {
  /// The block entity type key.
  static const String type = 'simulated:throttle_lever';

  /// The block key.
  static const String block = 'simulated:throttle_lever';

  ThrottleLeverBlockEntity(super.worldId, super.pos);

  /// The lever state.
  final ThrottleLeverLogic logic = ThrottleLeverLogic();

  BState state = BState(block);

  @override
  void tick() {
    final w = world;
    if (w != null && !removed) {
      state = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
      logic.inverted = state.flag('inverted');
    }

    if (logic.tick()) {
      // The lever moved: the neighbours see the new signal. The output is kept
      // by the host in memory, so it is written again after every restart.
      final w2 = world;
      if (w2 != null) {
        ignoredCall(
          w2.setRedstoneOutput(pos, weak: logic.outputSignal, strong: logic.outputSignal),
        );
      }
    }
    super.tick();
  }

  /// `changeState(back)`.
  void changeState({bool back = false}) {
    if (logic.changeState(back: back)) sendData();
  }

  /// `setSignal(signal)`: the client dragged the lever.
  void setSignal(int signal) {
    logic.setSignal(signal);
    sendData();
  }

  /// `getState()`.
  int get signal => logic.state;

  /// The lever value in `[0, 1]`.
  double get throttle => logic.throttle;

  /// `getSignal(state, level, pos, side)`: the raw state, as a redstone level.
  int redstoneSignal() => logic.state;

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    logic.read(tag.getInt('State') ?? 0, tag.getInt('ChangeTimer') ?? 0, inverted: logic.inverted);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('State', logic.state);
    tag.putInt('ChangeTimer', logic.lastChange);
  }

}
