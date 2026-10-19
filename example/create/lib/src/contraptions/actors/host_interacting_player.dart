// The host-side `InteractingPlayer` the actors hand to the contraption entity and to feedback code.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../core/movement.dart';

/// `InteractingPlayer` over a host [Player].
final class HostInteractingPlayer implements InteractingPlayer {
  HostInteractingPlayer(this.hostPlayer, {this.holdsWrench = false});

  @override
  final Object hostPlayer;

  @override
  final bool holdsWrench;

  Player get _player => hostPlayer as Player;

  @override
  String get uuid => _player.getId().asString;

  @override
  bool get isSneaking => _player.asEntity().isSneaking();

  @override
  bool get isPassenger => _player.asEntity().vehicle != null;

  @override
  bool canInteractWith(Pos pos, double distance) => true;

  @override
  bool get isCreative => _player.isCreative;

  @override
  void playSound(String sound, double pitch, {double volume = 0.3}) {
    _player.customSound(
      sound,
      category: SoundCategory.blocks,
      volume: volume,
      pitch: pitch,
    );
  }
}

/// The pure position of a player (the actors never need more for a message).
Pos playerPos(Player player) {
  final p = player.getPosition();
  return (p.$1.floor(), p.$2.floor(), p.$3.floor());
}
