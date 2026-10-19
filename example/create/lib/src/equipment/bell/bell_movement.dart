// `HauntedBellMovementBehaviour`: a haunted bell on a contraption sends a soul pulse to every new
// block it visits, then recharges so a fast contraption pulses at most every 65 ticks.
//
// Java reference: `content/equipment/bell/HauntedBellMovementBehaviour.java`.
import '../../common/common.dart';
import '../../contraptions/actors/actor_runtime.dart';
import '../../contraptions/behaviours/bell_movement_behaviour.dart';
import '../../contraptions/core/movement.dart';
import '../host/env.dart' hide Vec3;
import 'bell_host.dart';

final class HauntedBellMovementBehaviour extends MovementBehaviour {
  /// `HauntedBellMovementBehaviour.DISTANCE`.
  static const int distance = 3;

  final EquipmentEnv env;

  HauntedBellMovementBehaviour(this.env);

  /// `tick`: only the recharge countdown; the base bell's "moved" ring is not called.
  @override
  Future<void> tick(MovementContext context) async {
    final recharge = _recharge(context);
    if (recharge > 0) context.temporaryData = recharge - 1;
  }

  /// `visitNewPosition`: one pulse per block entered while the recharge is zero.
  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    if (_recharge(context) != 0) return;
    final world = actors?.worldOf(context);
    if (world == null) return;
    env.bus.sendToTrackingAt('create:soul_pulse', world.getId(), pos, {
      'pos': pos,
      'distance': distance,
      'canOverlap': false,
    });
    context.temporaryData = CreateBellEntity.hauntedRechargeTicks;
    BellMovementBehaviour.playSound(context);
  }

  /// `writeExtraData`: the countdown is saved with the contraption.
  @override
  void writeExtraData(MovementContext context) {
    context.blockEntityData?.putInt('Recharge', _recharge(context));
  }

  /// Inherited from `BellMovementBehaviour`: rings when the contraption reverses.
  @override
  void onSpeedChanged(MovementContext context, Vec3 oldMotion, Vec3 motion) {
    final dot = oldMotion.dot(motion);
    if (dot <= 0 && context.relativeMotion.length != 0 || context.firstMovement) {
      BellMovementBehaviour.playSound(context);
    }
  }

  /// Inherited from `BellMovementBehaviour`: rings when the contraption stops.
  @override
  void stopMoving(MovementContext context) {
    if (context.position != null && isActive(context)) {
      BellMovementBehaviour.playSound(context);
    }
  }

  /// `getRecharge`: the saved countdown is loaded into `temporaryData` once per contraption run.
  int _recharge(MovementContext context) {
    final data = context.temporaryData;
    if (data is int) return data;
    final stored = context.blockEntityData?.getInt('Recharge') ?? 0;
    context.temporaryData = stored;
    return stored;
  }
}
