import 'package:dart_mappable/dart_mappable.dart';

import 'clock.dart';
import 'storage.dart';

part 'players.mapper.dart';

/// What the server remembers about a player, so offline players can be found
/// by name (mail, moderation, paying).
@MappableClass()
class PlayerRecord with PlayerRecordMappable {
  final String uuid;
  final String name;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const PlayerRecord({
    required this.uuid,
    required this.name,
    required this.firstSeen,
    required this.lastSeen,
  });
}

@MappableClass()
class PlayerRecords with PlayerRecordsMappable {
  final Map<String, PlayerRecord> players;

  const PlayerRecords({this.players = const {}});
}

/// Every player that ever joined, keyed by UUID, with lookups by name.
/// Provided as a service by the core, used by nearly every module.
final class PlayerDirectory {
  final JsonDocument<PlayerRecords> _doc;
  final Clock _clock;
  final Map<String, String> _byLowerName = {};

  PlayerDirectory(Documents docs, this._clock)
    : _doc = docs.open(
        'players.json',
        decode: PlayerRecordsMapper.fromJson,
        encode: (v) => v.toJson(),
        create: PlayerRecords.new,
      ) {
    for (final record in _doc.value.players.values) {
      _byLowerName[record.name.toLowerCase()] = record.uuid;
    }
  }

  /// Records that [uuid] (currently named [name]) was seen now. Returns
  /// `true` if this is the first time.
  bool touch(String uuid, String name) {
    final now = _clock.now();
    final known = _doc.value.players[uuid];
    final record = PlayerRecord(
      uuid: uuid,
      name: name,
      firstSeen: known?.firstSeen ?? now,
      lastSeen: now,
    );
    if (known != null && known.name.toLowerCase() != name.toLowerCase()) {
      _byLowerName.remove(known.name.toLowerCase());
    }
    _byLowerName[name.toLowerCase()] = uuid;
    _doc.value = PlayerRecords(players: {..._doc.value.players, uuid: record});
    return known == null;
  }

  PlayerRecord? byUuid(String uuid) => _doc.value.players[uuid];

  /// Case-insensitive.
  PlayerRecord? byName(String name) {
    final uuid = _byLowerName[name.toLowerCase()];
    return uuid == null ? null : _doc.value.players[uuid];
  }

  String? nameOf(String uuid) => byUuid(uuid)?.name;

  /// All known names, for tab completion.
  List<String> get names =>
      [for (final r in _doc.value.players.values) r.name]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  int get count => _doc.value.players.length;
}
