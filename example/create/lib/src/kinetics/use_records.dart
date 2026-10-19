// Remembers the latest block use of each player so a placement can recover the
// clicked face and the item (`BlockPlaceContext`), which the host's placed
// event does not carry.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'geometry.dart';

/// The last right click of a player: where and with what item, so a placement
/// can recover the clicked face and the item (`BlockPlaceContext`).
final class UseRecord {
  final BlockPos clicked;
  final Dir face;
  final bool sneaking;
  final String itemKey;

  /// Where the click hit the block, `0..1` per axis.
  final (double, double, double) cursor;
  final BlockPos placedAt;

  UseRecord(this.clicked, this.face, this.sneaking, this.itemKey, [this.cursor = (0.5, 0.5, 0.5)])
    : placedAt = BlockPos(x: clicked.x + face.dx, y: clicked.y + face.dy, z: clicked.z + face.dz);
}

/// Remembers the latest block use of each player.
final class UseRecords {
  final Map<String, UseRecord> _byPlayer = {};

  void put(String player, UseRecord r) => _byPlayer[player] = r;

  /// The record of [player] if it can have produced a block at [pos].
  UseRecord? matching(String player, BlockPos pos) {
    final r = _byPlayer[player];
    if (r == null) return null;
    final atFace = r.placedAt.x == pos.x && r.placedAt.y == pos.y && r.placedAt.z == pos.z;
    final atClicked = r.clicked.x == pos.x && r.clicked.y == pos.y && r.clicked.z == pos.z;
    return (atFace || atClicked) ? r : null;
  }

  void forget(String player) => _byPlayer.remove(player);
}
