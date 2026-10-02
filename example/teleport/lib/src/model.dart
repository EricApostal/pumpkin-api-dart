/// The state and rules of the teleport plugin, without any dependency on the
/// server so that it can be tested on the Dart VM.
library;

/// A place a player can be sent to.
final class Location {
  /// The world's name, like `minecraft:overworld`.
  final String world;
  final double x;
  final double y;
  final double z;
  final double yaw;
  final double pitch;

  const Location({
    required this.world,
    required this.x,
    required this.y,
    required this.z,
    this.yaw = 0,
    this.pitch = 0,
  });

  factory Location.fromJson(Map<String, Object?> json) => Location(
    world: json['world'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    yaw: (json['yaw'] as num? ?? 0).toDouble(),
    pitch: (json['pitch'] as num? ?? 0).toDouble(),
  );

  Map<String, Object?> toJson() => {
    'world': world,
    'x': x,
    'y': y,
    'z': z,
    'yaw': yaw,
    'pitch': pitch,
  };

  /// A short description like `overworld 10, 64, -3`.
  String describe() {
    final name = world.startsWith('minecraft:') ? world.substring(10) : world;
    return '$name ${x.floor()}, ${y.floor()}, ${z.floor()}';
  }
}

/// Settings from `config.json`. Missing values use the defaults.
final class TeleportConfig {
  /// How many homes a player may have.
  final int maxHomes;

  /// How long a teleport request stays open.
  final Duration requestTimeout;

  /// The pause a player has to wait between teleports.
  final Duration cooldown;

  const TeleportConfig({
    this.maxHomes = 3,
    this.requestTimeout = const Duration(seconds: 60),
    this.cooldown = const Duration(seconds: 5),
  });

  factory TeleportConfig.fromJson(Map<String, Object?> json) {
    const defaults = TeleportConfig();
    return TeleportConfig(
      maxHomes: (json['maxHomes'] as num?)?.toInt() ?? defaults.maxHomes,
      requestTimeout: Duration(
        seconds:
            (json['requestTimeoutSeconds'] as num?)?.toInt() ??
            defaults.requestTimeout.inSeconds,
      ),
      cooldown: Duration(
        seconds:
            (json['cooldownSeconds'] as num?)?.toInt() ??
            defaults.cooldown.inSeconds,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'maxHomes': maxHomes,
    'requestTimeoutSeconds': requestTimeout.inSeconds,
    'cooldownSeconds': cooldown.inSeconds,
  };
}

final _validName = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Whether [name] can be used for a home or a warp.
bool isValidName(String name) => _validName.hasMatch(name);

/// Names are case insensitive.
String normalizeName(String name) => name.toLowerCase();

/// Every player's homes, by player UUID.
final class HomeBook {
  final Map<String, Map<String, Location>> _homes;

  HomeBook([Map<String, Map<String, Location>>? homes]) : _homes = homes ?? {};

  factory HomeBook.fromJson(Map<String, Object?> json) {
    final homes = <String, Map<String, Location>>{};
    for (final MapEntry(key: uuid, value: entry) in json.entries) {
      final byName = <String, Location>{};
      final raw = (entry as Map<String, Object?>)['homes'] as Map<String, Object?>;
      for (final MapEntry(key: name, value: location) in raw.entries) {
        byName[name] = Location.fromJson(location as Map<String, Object?>);
      }
      homes[uuid] = byName;
    }
    return HomeBook(homes);
  }

  /// Serialized with the players' [names] (last seen), to make the file
  /// readable.
  Map<String, Object?> toJson(Map<String, String> names) => {
    for (final MapEntry(key: uuid, value: byName) in _homes.entries)
      if (byName.isNotEmpty)
        uuid: {
          'name': names[uuid] ?? '',
          'homes': {
            for (final MapEntry(key: name, value: location) in byName.entries)
              name: location.toJson(),
          },
        },
  };

  /// The player's homes, by name.
  Map<String, Location> of(String uuid) =>
      Map.unmodifiable(_homes[uuid] ?? const {});

  Location? get(String uuid, String name) => _homes[uuid]?[normalizeName(name)];

  int count(String uuid) => _homes[uuid]?.length ?? 0;

  bool has(String uuid, String name) =>
      _homes[uuid]?.containsKey(normalizeName(name)) ?? false;

  void set(String uuid, String name, Location location) {
    (_homes[uuid] ??= {})[normalizeName(name)] = location;
  }

  bool remove(String uuid, String name) =>
      _homes[uuid]?.remove(normalizeName(name)) != null;
}

/// The server's warps.
final class WarpBook {
  final Map<String, Location> _warps;

  WarpBook([Map<String, Location>? warps]) : _warps = warps ?? {};

  factory WarpBook.fromJson(Map<String, Object?> json) => WarpBook({
    for (final MapEntry(key: name, value: location) in json.entries)
      name: Location.fromJson(location as Map<String, Object?>),
  });

  Map<String, Object?> toJson() => {
    for (final MapEntry(key: name, value: location) in _warps.entries)
      name: location.toJson(),
  };

  List<String> get names => (_warps.keys.toList()..sort());

  Location? get(String name) => _warps[normalizeName(name)];

  void set(String name, Location location) =>
      _warps[normalizeName(name)] = location;

  bool remove(String name) => _warps.remove(normalizeName(name)) != null;
}

/// Which way a request sends people.
enum TpaKind {
  /// The requester goes to the target.
  to,

  /// The target comes to the requester.
  here,
}

/// A pending teleport request.
final class TpaRequest {
  final String fromUuid;
  final String fromName;
  final String toUuid;
  final TpaKind kind;
  final DateTime expires;

  TpaRequest({
    required this.fromUuid,
    required this.fromName,
    required this.toUuid,
    required this.kind,
    required this.expires,
  });
}

/// The open teleport requests. A player has at most one outgoing request.
final class TpaRequests {
  final DateTime Function() _now;
  final Duration timeout;
  final List<TpaRequest> _requests = [];

  TpaRequests({required this.timeout, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Opens a request, replacing the sender's previous one.
  TpaRequest create({
    required String fromUuid,
    required String fromName,
    required String toUuid,
    required TpaKind kind,
  }) {
    _prune();
    _requests.removeWhere((r) => r.fromUuid == fromUuid);
    final request = TpaRequest(
      fromUuid: fromUuid,
      fromName: fromName,
      toUuid: toUuid,
      kind: kind,
      expires: _now().add(timeout),
    );
    _requests.add(request);
    return request;
  }

  /// The requests waiting for [toUuid], newest first.
  List<TpaRequest> incoming(String toUuid) {
    _prune();
    return [
      for (final request in _requests.reversed)
        if (request.toUuid == toUuid) request,
    ];
  }

  /// The request the player [toUuid] would answer: the one from [fromName] if
  /// given, otherwise the newest.
  TpaRequest? pending(String toUuid, {String? fromName}) {
    for (final request in incoming(toUuid)) {
      if (fromName == null ||
          request.fromName.toLowerCase() == fromName.toLowerCase()) {
        return request;
      }
    }
    return null;
  }

  /// The request [fromUuid] has open, if any.
  TpaRequest? outgoing(String fromUuid) {
    _prune();
    for (final request in _requests) {
      if (request.fromUuid == fromUuid) return request;
    }
    return null;
  }

  void remove(TpaRequest request) => _requests.remove(request);

  /// Drops every request involving [uuid], like when they leave.
  void removeAllFor(String uuid) => _requests.removeWhere(
    (r) => r.fromUuid == uuid || r.toUuid == uuid,
  );

  void _prune() {
    final now = _now();
    _requests.removeWhere((r) => !r.expires.isAfter(now));
  }
}

/// The pause between a player's teleports.
final class Cooldowns {
  final DateTime Function() _now;
  final Map<String, DateTime> _last = {};

  Cooldowns({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// How much longer [uuid] has to wait, or `null` if they can teleport.
  Duration? remaining(String uuid, Duration cooldown) {
    final last = _last[uuid];
    if (last == null) return null;
    final left = last.add(cooldown).difference(_now());
    return left > Duration.zero ? left : null;
  }

  /// Records that [uuid] just teleported.
  void mark(String uuid) => _last[uuid] = _now();
}
