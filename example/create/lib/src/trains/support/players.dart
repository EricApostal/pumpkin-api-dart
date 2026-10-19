// Players outside of event callbacks: the payload bus keeps the online players (kept
// resources, see docs/lifetimes.md of pumpkin_api); trains look them up by uuid.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'runtime.dart';

/// The online player with [uuid] (canonical text), or `null`.
Player? onlinePlayer(String uuid) {
  final bus = Tr.i.bus;
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

/// All online players (kept handles; do not dispose them).
Iterable<Player> onlinePlayers() => Tr.i.bus?.roster.players ?? const [];
