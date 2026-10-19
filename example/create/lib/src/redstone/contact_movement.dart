// `ContactMovementBehaviour`: a redstone contact on a contraption powers the contact it
// passes over. It also lets an elevator contact announce the floor it reached.
import '../api/util.dart' hide pos;
import '../contraptions/core/movement.dart';
import '../contraptions/elevator/elevator_contraption.dart';
import 'support/level.dart';
import 'support/rs_runtime.dart';

/// `ContactMovementBehaviour` (`content/redstone/contact/ContactMovementBehaviour.java`).
final class ContactMovementBehaviour extends MovementBehaviour {
  const ContactMovementBehaviour();

  static const String redstoneContactKey = 'create:redstone_contact';
  static const String elevatorContactKey = 'create:elevator_contact';

  /// `context.data` key of the contact the contraption powered last.
  static const String lastContactKey = 'lastContact';

  /// The active area is the contact face, pushed 0.65 blocks out.
  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final (x, y, z) = (context.state.dir('facing') ?? Direction.up).unitVec3;
    return (x * 0.65, y * 0.65, z * 0.65);
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    if (context.firstMovement) return;
    deactivateLastVisitedContact(context);

    final visited = context.level.stateAt(pos);
    if (visited.key != redstoneContactKey &&
        visited.key != elevatorContactKey) {
      return;
    }

    // The contact faces the world through the contraption's rotation.
    final (x, y, z) = (context.state.dir('facing') ?? Direction.up).unitVec3;
    final rotated = context.rotation((x, y, z));
    final direction = Direction.nearest(rotated.$1, rotated.$2, rotated.$3);
    if (visited.dir('facing') != direction.opposite) return;

    if (visited.key == redstoneContactKey) {
      final world = Rs.i.worldById(context.worldId);
      if (world != null) {
        await Lvl(world).setProps(pos, {'powered': 'true'}, neighbors: true);
      }
    } else {
      final contraption = context.contraption;
      if (contraption is ElevatorContraption) {
        contraption.broadcastFloorData(context.level, pos);
      }
    }
    context.data.putBlockPos(lastContactKey, pos);
  }

  @override
  void stopMoving(MovementContext context) =>
      deactivateLastVisitedContact(context);

  @override
  void cancelStall(MovementContext context) {
    super.cancelStall(context);
    deactivateLastVisitedContact(context);
  }

  /// `deactivateLastVisitedContact`: the contact the contraption left re-reads its
  /// neighbours after a tick (the same delayed unpressing the block does).
  void deactivateLastVisitedContact(MovementContext context) {
    if (!context.data.contains(lastContactKey)) return;
    final last = context.data.getBlockPos(lastContactKey);
    context.data.remove(lastContactKey);
    if (context.level.stateAt(last).key != redstoneContactKey) return;
    context.level.scheduleBlockTick(last, redstoneContactKey);
  }
}
