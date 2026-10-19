// Players outside of event callbacks: the payload bus keeps the online players (kept
// resources, see docs/lifetimes.md of pumpkin_api), block entities look them up by uuid.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'rs_runtime.dart';

/// The online player with [uuid] (canonical text), or `null`.
Player? onlinePlayer(String uuid) {
  final bus = Rs.i.bus;
  if (bus == null) return null;
  for (final p in bus.roster.players) {
    try {
      if (p.getId().asString == uuid) return p;
    } on Object {
      // a handle that went invalid
    }
  }
  return null;
}

/// `player.getEyePosition()`.
(double, double, double) eyePosition(Player player) {
  final (x, y, z) = player.getPosition();
  return (x, y + player.asEntity().getEyeHeight(), z);
}

/// The namespace of the data this module keeps on players.
const String playerDataNamespace = 'create';
