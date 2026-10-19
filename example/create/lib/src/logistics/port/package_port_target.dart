// `PackagePortTarget` (pure): where a package port sends its packages (a chain conveyor or a
// train station). The target blocks belong to other modules; the port only keeps the target
// description and reports whether the target can currently take a package.
import '../../common/pos.dart';

/// `PackagePortTargetType` (`AllPackagePortTargetTypes`).
enum PackagePortTargetType {
  chainConveyor('chain_conveyor'),
  trainStation('train_station');

  const PackagePortTargetType(this.id);

  final String id;

  static PackagePortTargetType? byId(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// `PackagePortTarget`.
final class PackagePortTarget {
  final PackagePortTargetType type;

  /// `relativePos`: the target position relative to the port.
  final Pos relativePos;

  /// Chain conveyor: where on the chain and which connection (`null`: the loop).
  final double chainPos;
  final Pos? connection;
  final bool flipped;

  const PackagePortTarget(
    this.type,
    this.relativePos, {
    this.chainPos = 0,
    this.connection,
    this.flipped = false,
  });

  Map<String, dynamic> toMap() => {
    'type': type.id,
    'relativePos': [relativePos.$1, relativePos.$2, relativePos.$3],
    'chainPos': chainPos,
    'connection': connection == null
        ? null
        : [connection!.$1, connection!.$2, connection!.$3],
    'flipped': flipped,
  };

  static PackagePortTarget? fromMap(Object? value) {
    if (value is! Map) return null;
    final type = PackagePortTargetType.byId(value['type'] as String? ?? '');
    final pos = value['relativePos'];
    if (type == null || pos is! List || pos.length != 3) return null;
    final connection = value['connection'];
    return PackagePortTarget(
      type,
      (pos[0] as int, pos[1] as int, pos[2] as int),
      chainPos: (value['chainPos'] as num?)?.toDouble() ?? 0,
      connection: connection is List && connection.length == 3
          ? (connection[0] as int, connection[1] as int, connection[2] as int)
          : null,
      flipped: value['flipped'] == true,
    );
  }

  /// `canSupport(portBlockKey)`: frogports reach chain conveyors, postboxes train stations.
  bool canSupport(String portBlockKey) => switch (type) {
    PackagePortTargetType.chainConveyor =>
      portBlockKey == 'create:package_frogport',
    PackagePortTargetType.trainStation => portBlockKey.contains('_postbox'),
  };
}
