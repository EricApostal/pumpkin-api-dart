// The plugin's saved state: which computers exist, who owns them and what is
// attached to them (`computers.json`).
import '../machine/computer.dart';

/// A monitor or modem attached to a side of a computer.
final class PeripheralSpec {
  /// `monitor` or `modem`.
  final String type;
  final bool advanced;

  /// The size of a monitor in blocks.
  final int width;
  final int height;

  const PeripheralSpec(this.type, {this.advanced = true, this.width = 1, this.height = 1});

  factory PeripheralSpec.fromJson(Map<String, Object?> json) => PeripheralSpec(
    json['type'] is String ? json['type']! as String : 'monitor',
    advanced: json['advanced'] is bool ? json['advanced']! as bool : true,
    width: json['width'] is num ? (json['width']! as num).toInt() : 1,
    height: json['height'] is num ? (json['height']! as num).toInt() : 1,
  );

  Map<String, Object?> toJson() => {
    'type': type,
    'advanced': advanced,
    if (type == 'monitor') ...{'width': width, 'height': height},
  };
}

/// Where a computer stands in the world (a computer block, as opposed to one
/// made with `/cc new`).
final class ComputerLocation {
  /// The world id, for example `minecraft:overworld`.
  final String world;
  final int x;
  final int y;
  final int z;

  const ComputerLocation(this.world, this.x, this.y, this.z);

  factory ComputerLocation.fromJson(Map<String, Object?> json) => ComputerLocation(
    json['world'] is String ? json['world']! as String : 'minecraft:overworld',
    (json['x']! as num).toInt(),
    (json['y']! as num).toInt(),
    (json['z']! as num).toInt(),
  );

  Map<String, Object?> toJson() => {'world': world, 'x': x, 'y': y, 'z': z};

  @override
  bool operator ==(Object other) =>
      other is ComputerLocation && other.world == world && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(world, x, y, z);

  @override
  String toString() => '$world $x $y $z';
}

/// One computer as saved.
final class ComputerRecord {
  final int id;
  final ComputerFamily family;
  String? label;

  /// The UUID of the owner, or `console`.
  final String owner;
  final String ownerName;

  /// Whether the computer was on when the server stopped (it starts again).
  bool on;

  /// The block the computer stands in, `null` for a computer of `/cc new` and
  /// for a computer carried as an item.
  ComputerLocation? location;

  /// Attached peripherals by side name.
  final Map<String, PeripheralSpec> peripherals;

  ComputerRecord({
    required this.id,
    required this.family,
    required this.owner,
    required this.ownerName,
    this.label,
    this.on = false,
    this.location,
    Map<String, PeripheralSpec>? peripherals,
  }) : peripherals = peripherals ?? {};

  factory ComputerRecord.fromJson(Map<String, Object?> json) {
    final peripherals = <String, PeripheralSpec>{};
    final raw = json['peripherals'];
    if (raw is Map<String, Object?>) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map<String, Object?>) {
          peripherals[entry.key] = PeripheralSpec.fromJson(value);
        }
      }
    }
    return ComputerRecord(
      id: (json['id']! as num).toInt(),
      family: json['family'] == 'normal' ? ComputerFamily.normal : ComputerFamily.advanced,
      owner: json['owner'] is String ? json['owner']! as String : 'console',
      ownerName: json['owner_name'] is String ? json['owner_name']! as String : 'console',
      label: json['label'] is String ? json['label'] as String : null,
      on: json['on'] == true,
      location: json['location'] is Map<String, Object?> ? ComputerLocation.fromJson(json['location']! as Map<String, Object?>) : null,
      peripherals: peripherals,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'family': family.name,
    'owner': owner,
    'owner_name': ownerName,
    if (label != null) 'label': label,
    'on': on,
    if (location != null) 'location': location!.toJson(),
    if (peripherals.isNotEmpty)
      'peripherals': {for (final e in peripherals.entries) e.key: e.value.toJson()},
  };
}
