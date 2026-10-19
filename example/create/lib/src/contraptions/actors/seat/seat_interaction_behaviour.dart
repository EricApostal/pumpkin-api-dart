// `SeatInteractionBehaviour`: an entity that touches a seat on a contraption sits down.
import 'package:pumpkin_api/pumpkin_api.dart' show Entity;

import '../../../common/common.dart';
import '../../core/contraption.dart';
import '../../core/movement.dart';
import 'seat_entity.dart';

/// `SeatInteractionBehaviour`.
final class SeatInteractionBehaviour extends MovingInteractionBehaviour {
  const SeatInteractionBehaviour();

  @override
  bool handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) => false;

  @override
  void handleEntityCollision(
    CollidingEntity entity,
    Pos localPos,
    Contraption contraption,
  ) {
    final host = entity.hostEntity;
    if (host is! Entity) return;
    final index = contraption.getSeats().indexOf(localPos);
    if (index == -1) return;
    if (!canBePickedUp(host)) return;
    contraption.entity?.addSittingPassenger(host, index);
  }
}
