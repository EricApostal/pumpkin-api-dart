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

  /// `flipped`: the direction of the chain conveyor (`getSpeed() < 0`), set by `setup`.
  final bool flipped;

  const PackagePortTarget(
    this.type,
    this.relativePos, {
    this.chainPos = 0,
    this.connection,
    this.flipped = false,
  });

  /// `setup`: a copy with [flipped] set from the chain conveyor's direction.
  PackagePortTarget withFlipped(bool value) => PackagePortTarget(
    type,
    relativePos,
    chainPos: chainPos,
    connection: connection,
    flipped: value,
  );

  /// A copy with another target position, chain position, connection or direction. The
  /// reversed-motion jump of `ChainConveyorFrogportTarget.register` rewrites all four at once.
  PackagePortTarget copyWith({
    Pos? relativePos,
    double? chainPos,
    Pos? connection,
    bool? flipped,
  }) => PackagePortTarget(
    type,
    relativePos ?? this.relativePos,
    chainPos: chainPos ?? this.chainPos,
    connection: connection ?? this.connection,
    flipped: flipped ?? this.flipped,
  );

  /// The private JSON form, using the field names of the Java codec (`type`, `relative_pos` and,
  /// for a chain conveyor, `chain_pos`, `connection`, `flipped`).
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'create:${type.id}',
      'relative_pos': [relativePos.$1, relativePos.$2, relativePos.$3],
    };
    if (type == PackagePortTargetType.chainConveyor) {
      map['chain_pos'] = chainPos;
      final c = connection;
      if (c != null) map['connection'] = [c.$1, c.$2, c.$3];
      map['flipped'] = flipped;
    }
    return map;
  }

  static PackagePortTarget? fromMap(Object? value) {
    if (value is! Map) return null;
    final rawType = value['type'] as String? ?? '';
    final type = PackagePortTargetType.byId(
      rawType.startsWith('create:') ? rawType.substring(7) : rawType,
    );
    // The old private form used camelCase keys; keep reading it.
    final pos = value['relative_pos'] ?? value['relativePos'];
    if (type == null || pos is! List || pos.length != 3) return null;
    final connection = value['connection'];
    return PackagePortTarget(
      type,
      (pos[0] as int, pos[1] as int, pos[2] as int),
      chainPos:
          ((value['chain_pos'] ?? value['chainPos']) as num?)?.toDouble() ?? 0,
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
