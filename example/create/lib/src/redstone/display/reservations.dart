// Line reservations of display targets (pure): `DisplayTarget.reserve` / `isReserved`.
// A multi line target (sign, lectern, display board) is written by several display links; the
// link that wrote line 0 reserves the following lines of its text so another link does not
// overwrite them. Java keeps this in the target block entity's persistent data (`DisplayLink`
// compound, key `Line<n>` -> the link's `BlockPos.asLong`); here it is one store per world.
import 'dart:convert';

import '../../common/common.dart';

/// Reservations of one world, serialisable as JSON.
final class ReservationStore {
  /// Packed target position -> line -> packed link position.
  final Map<int, Map<int, int>> _reserved = {};

  ReservationStore();

  factory ReservationStore.fromJson(String? json) {
    final store = ReservationStore();
    if (json == null || json.isEmpty) return store;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        for (final e in decoded.entries) {
          final target = int.tryParse(e.key);
          final lines = e.value;
          if (target == null || lines is! Map<String, dynamic>) continue;
          for (final l in lines.entries) {
            final line = int.tryParse(l.key);
            final link = l.value;
            if (line != null && link is int) store._reserved.putIfAbsent(target, () => {})[line] = link;
          }
        }
      }
    } on FormatException {
      // an unreadable store starts empty
    }
    return store;
  }

  /// The link that reserved [line] of [target].
  Pos? reservedBy(Pos target, int line) {
    final packed = _reserved[target.asLong]?[line];
    return packed == null ? null : posFromLong(packed);
  }

  /// Reserves [line] for [link], or clears it when [link] is null. Returns whether the store changed.
  bool set(Pos target, int line, Pos? link) {
    final key = target.asLong;
    if (link == null) {
      final lines = _reserved[key];
      if (lines == null || lines.remove(line) == null) return false;
      if (lines.isEmpty) _reserved.remove(key);
      return true;
    }
    final lines = _reserved.putIfAbsent(key, () => {});
    if (lines[line] == link.asLong) return false;
    lines[line] = link.asLong;
    return true;
  }

  bool get isEmpty => _reserved.isEmpty;

  String toJson() => jsonEncode({
    for (final e in _reserved.entries) '${e.key}': {for (final l in e.value.entries) '${l.key}': l.value},
  });
}
