// The item stack of the schematic items as plain data (pure): `SlotStack` for inventories and
// `SchematicStackData`, the `schematic_*` data components of a schematic item.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart' show NbtValue;
import '../core/pos.dart' as core_pos;

/// A stack in a block entity inventory: item, count and the values of the custom (`create:*`)
/// components, which is all of a stack the plugin can read and write.
final class SlotStack {
  final String item;
  final int count;
  final Map<String, Uint8List> components;

  /// The `components` compound of a Java save, kept verbatim (`ItemValue.rawComponents`).
  final NbtValue? rawComponents;

  const SlotStack(this.item, this.count, [this.components = const {}, this.rawComponents]);

  static const SlotStack empty = SlotStack('minecraft:air', 0);

  bool get isEmpty => count <= 0 || item == 'minecraft:air';

  SlotStack withCount(int c) => c <= 0 ? empty : SlotStack(item, c, components, rawComponents);

  SlotStack shrink(int n) => withCount(count - n);

  /// The same item and components (`ItemStack.isSameItemSameComponents`).
  bool sameAs(SlotStack o) {
    if (item != o.item || components.length != o.components.length) return false;
    for (final e in components.entries) {
      final other = o.components[e.key];
      if (other == null || other.length != e.value.length) return false;
      for (var i = 0; i < other.length; i++) {
        if (other[i] != e.value[i]) return false;
      }
    }
    return true;
  }

  @override
  String toString() => isEmpty ? 'empty' : '$count x $item';
}

/// The schematic data components of a schematic item (`AllDataComponents.SCHEMATIC_*`).
final class SchematicStackData {
  static const String deployedKey = 'create:schematic_deployed';
  static const String ownerKey = 'create:schematic_owner';
  static const String fileKey = 'create:schematic_file';
  static const String anchorKey = 'create:schematic_anchor';
  static const String rotationKey = 'create:schematic_rotation';
  static const String mirrorKey = 'create:schematic_mirror';
  static const String boundsKey = 'create:schematic_bounds';
  static const String hashKey = 'create:schematic_hash';

  static const List<String> allKeys = [
    deployedKey,
    ownerKey,
    fileKey,
    anchorKey,
    rotationKey,
    mirrorKey,
    boundsKey,
    hashKey,
  ];

  final bool? deployed;
  final String? owner;
  final String? file;
  final Pos? anchor;
  final BlockRotation rotation;
  final BlockMirror mirror;
  final Pos? bounds;
  final int? hash;

  const SchematicStackData({
    this.deployed,
    this.owner,
    this.file,
    this.anchor,
    this.rotation = BlockRotation.none,
    this.mirror = BlockMirror.none,
    this.bounds,
    this.hash,
  });

  /// `SchematicItem.create(level, schematic, owner)` before the size is written.
  factory SchematicStackData.create(String schematic, String owner, {Pos? bounds}) => SchematicStackData(
    deployed: false,
    owner: owner,
    file: schematic,
    anchor: posZero,
    rotation: BlockRotation.none,
    mirror: BlockMirror.none,
    bounds: bounds,
  );

  /// Whether the stack has `SCHEMATIC_FILE`.
  bool get hasFile => file != null;

  SchematicStackData copyWith({
    bool? deployed,
    Pos? anchor,
    BlockRotation? rotation,
    BlockMirror? mirror,
    Pos? bounds,
    bool clearHash = false,
  }) => SchematicStackData(
    deployed: deployed ?? this.deployed,
    owner: owner,
    file: file,
    anchor: anchor ?? this.anchor,
    rotation: rotation ?? this.rotation,
    mirror: mirror ?? this.mirror,
    bounds: bounds ?? this.bounds,
    hash: clearHash ? null : hash,
  );

  /// Reads the data from the custom components of a stack ([values] by component key).
  factory SchematicStackData.fromComponents(Map<String, List<int>> values) {
    String? str(String k) {
      final v = values[k];
      return v == null ? null : PacketReader(v).readString();
    }

    final deployed = values[deployedKey];
    final anchor = values[anchorKey];
    final rotation = values[rotationKey];
    final mirror = values[mirrorKey];
    final bounds = values[boundsKey];
    final hash = values[hashKey];
    return SchematicStackData(
      deployed: deployed == null ? null : PacketReader(deployed).readBool(),
      owner: str(ownerKey),
      file: str(fileKey),
      anchor: anchor == null ? null : core_pos.unpackPos(PacketReader(anchor).readLong()),
      rotation: rotation == null
          ? BlockRotation.none
          : BlockRotation.values[PacketReader(rotation).readVarInt().clamp(0, 3)],
      mirror: mirror == null ? BlockMirror.none : BlockMirror.values[PacketReader(mirror).readVarInt().clamp(0, 2)],
      bounds: bounds == null
          ? null
          : () {
              final r = PacketReader(bounds);
              return (r.readInt(), r.readInt(), r.readInt());
            }(),
      hash: hash == null ? null : PacketReader(hash).readInt(),
    );
  }

  /// The component values to set on a stack (null entries are removed).
  Map<String, Uint8List?> toComponents() => {
    deployedKey: deployed == null ? null : PacketBuffer.encode((w) => w.writeBool(deployed!)),
    ownerKey: owner == null ? null : PacketBuffer.encode((w) => w.writeString(owner!)),
    fileKey: file == null ? null : PacketBuffer.encode((w) => w.writeString(file!)),
    anchorKey: anchor == null ? null : PacketBuffer.encode((w) => w.writeLong(anchor!.asLong)),
    rotationKey: PacketBuffer.encode((w) => w.writeVarInt(rotation.index)),
    mirrorKey: PacketBuffer.encode((w) => w.writeVarInt(mirror.index)),
    boundsKey: bounds == null
        ? null
        : PacketBuffer.encode((w) {
            w.writeInt(bounds!.$1);
            w.writeInt(bounds!.$2);
            w.writeInt(bounds!.$3);
          }),
    hashKey: hash == null ? null : PacketBuffer.encode((w) => w.writeInt(hash!)),
  };

  @override
  String toString() => 'Schematic($file by $owner, deployed $deployed, anchor $anchor, $rotation, $mirror)';
}

/// The `SchematicannonOptions` data component value (replace mode, skip missing, replace block entities).
Uint8List encodeCannonOptions(int replaceMode, bool skipMissing, bool replaceBlockEntities) => PacketBuffer.encode((w) {
  w.writeInt(replaceMode);
  w.writeBool(skipMissing);
  w.writeBool(replaceBlockEntities);
});

/// Reads `SCHEMATICANNON_OPTIONS`.
({int replaceMode, bool skipMissing, bool replaceBlockEntities}) decodeCannonOptions(List<int> bytes) {
  final r = PacketReader(bytes);
  return (replaceMode: r.readInt(), skipMissing: r.readBool(), replaceBlockEntities: r.readBool());
}
