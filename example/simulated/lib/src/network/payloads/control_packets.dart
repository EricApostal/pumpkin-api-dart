// The control-surface payloads: steering wheel, throttle lever, plunger
// launcher.
//
// `plunger_launcher_shoot` carries the hand as `CatnipStreamCodecs.HAND`, which
// is a **boolean**: true is the main hand. The two control packets carry a
// block position last, which is easy to get wrong — the wheel sends the flag and
// the angle *before* the position.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.SteeringWheelPacket
//       …packets.ThrottleLeverSignalPacket
//       …packets.PlungerLauncherShootPacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;


import '../sim_packet.dart';

/// `simulated:steering_wheel_update` — the wheel is being turned or released.
final class SteeringWheelPacket implements SimPacket {
  static const String type = 'simulated:steering_wheel_update';

  final bool shouldStop;
  final double targetAngle;
  final Pos pos;

  const SteeringWheelPacket(this.shouldStop, this.targetAngle, this.pos);

  @override
  String get id => type;

  static final SimCodec<SteeringWheelPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBool(p.shouldStop)
      ..writeFloat(p.targetAngle)
      ..writeBlockPos(p.pos),
    (r) => SteeringWheelPacket(r.readBool(), r.readFloat(), r.readBlockPos()),
  );
}

/// `simulated:throttle_lever_signal` — the lever moved to [signal].
final class ThrottleLeverSignalPacket implements SimPacket {
  static const String type = 'simulated:throttle_lever_signal';

  final Pos pos;
  final int signal;

  const ThrottleLeverSignalPacket(this.pos, this.signal);

  @override
  String get id => type;

  static final SimCodec<ThrottleLeverSignalPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.pos)
      ..writeInt(p.signal),
    (r) => ThrottleLeverSignalPacket(r.readBlockPos(), r.readInt()),
  );
}

/// `simulated:plunger_launcher_shoot` — the launcher fired from [mainHand].
final class PlungerLauncherShootPacket implements SimPacket {
  static const String type = 'simulated:plunger_launcher_shoot';

  final bool mainHand;

  const PlungerLauncherShootPacket(this.mainHand);

  @override
  String get id => type;

  static final SimCodec<PlungerLauncherShootPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) => w.writeBool(p.mainHand),
    (r) => PlungerLauncherShootPacket(r.readBool()),
  );
}
