// Item and fluid stacks on the wire (pure). Verified against Minecraft 26.3 /
// NeoForge 26.3 (`ItemStack.OPTIONAL_STREAM_CODEC`, `DataComponentPatch.STREAM_CODEC`,
// `FluidStack.OPTIONAL_STREAM_CODEC`):
//
//   item stack   := varint count (<= 0: empty, nothing follows)
//                   varint item registry id
//                   patch
//   patch        := varint addedCount, varint removedCount,
//                   addedCount x (varint componentTypeId, value in the component's codec),
//                   removedCount x varint componentTypeId
//   fluid stack  := varint amount (<= 0: empty), varint fluid registry id, patch
//
// The value of a component can only be delimited by knowing its codec, so a patch
// is decoded structurally into `(id, raw value bytes)` pairs through the table in
// [ItemComponents]. A component id without an entry makes the stack (and so the
// payload) undecodable: the payload is dropped. The table covers the common
// vanilla components; modules add Create's own (`create:*`) components with
// [ItemComponents.register] once the host assigned their ids.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../core/byte_buf.dart';
import 'wire_values.dart';

/// Copies the bytes of one component value from [r] to [w] (it only needs to
/// consume the right number of bytes; copying is how the raw bytes are kept).
typedef ComponentCopier = void Function(PacketReader r, PacketWriter w);

/// The largest item count accepted when reading (Minecraft's maximum stack size is 99).
const int maxWireItemCount = 99;

/// The data component codecs known to the wire layer, by numeric type id.
abstract final class ItemComponents {
  static final Map<int, ComponentCopier> _byId = {};
  static bool _vanilla = false;

  /// Registers how to read the value of component type [typeId]
  /// (`ctx.ids` / the host's data component registry id). Replaces an earlier entry.
  static void register(int typeId, ComponentCopier copier) => _byId[typeId] = copier;

  /// Like [register] with a vanilla component name (`minecraft:damage`), resolved
  /// through `VanillaIds.dataComponentTypes`. Returns false if the name is unknown.
  static bool registerVanilla(String name, ComponentCopier copier) {
    final id = VanillaIds.dataComponentTypes.idOf(name);
    if (id == null) return false;
    _byId[id] = copier;
    return true;
  }

  /// The copier for [typeId], or null.
  static ComponentCopier? of(int typeId) {
    _installVanilla();
    return _byId[typeId];
  }

  // Frequently needed shapes, public so modules can register their components.
  static void copyNothing(PacketReader r, PacketWriter w) {}
  static void copyVarInt(PacketReader r, PacketWriter w) => w.writeVarInt(r.readVarInt());
  static void copyBool(PacketReader r, PacketWriter w) => w.writeBool(r.readBool());
  static void copyFloat(PacketReader r, PacketWriter w) => w.writeFloat(r.readFloat());
  static void copyString(PacketReader r, PacketWriter w) => w.writeString(r.readString());
  static void copyNbt(PacketReader r, PacketWriter w) => w.writeNbt(r.readNbt());

  static void _installVanilla() {
    if (_vanilla) return;
    _vanilla = true;
    void reg(String name, ComponentCopier c) {
      final id = VanillaIds.dataComponentTypes.idOf(name);
      if (id != null) _byId.putIfAbsent(id, () => c);
    }

    for (final n in ['custom_data', 'bucket_entity_data', 'custom_name', 'item_name']) {
      reg(n, copyNbt); // CustomData = COMPOUND_TAG, Component = NBT tag
    }
    for (final n in [
      'max_stack_size',
      'max_damage',
      'damage',
      'repair_cost',
      'additional_trade_cost',
      'rarity',
      'map_id',
      'dye',
      'base_color',
    ]) {
      reg(n, copyVarInt);
    }
    for (final n in ['unbreakable', 'creative_slot_lock', 'glider', 'waxed', 'intangible_projectile']) {
      reg(n, copyNothing);
    }
    for (final n in ['item_model', 'tooltip_style', 'note_block_sound']) {
      reg(n, copyString);
    }
    reg('enchantment_glint_override', copyBool);
    for (final n in ['minimum_attack_charge', 'potion_duration_scale']) {
      reg(n, copyFloat);
    }
  }
}

/// Builds the [ComponentCopier] of a component whose value is described by
/// [codec] (the same description the host receives at registration): it reads
/// exactly one value of the codec from the reader and writes the same value to
/// the writer, so the raw bytes of the value are kept without decoding them
/// into a model.
///
/// Every [CodecOpKind] is supported; `stack` and `component-patch` recurse
/// through [ItemStackData] and [ItemComponentPatch], so a nested stack's own
/// `create:*` components are read with their registered copiers too.
///
/// Throws [ArgumentError] for an empty description and [StateError] for one
/// that is not a single well-formed root, which would leave bytes behind (a
/// wrong length would corrupt every later field of the payload).
ComponentCopier copierForCodec(ComponentCodec codec) {
  final ops = codec.ops;
  if (ops.isEmpty) throw ArgumentError.value(codec, 'codec', 'has no ops');
  return (r, w) {
    final end = _copyNode(ops, 0, r, w);
    if (end != ops.length) {
      throw StateError('Malformed component codec: ${ops.length} ops, the root ends at $end');
    }
  };
}

/// Copies the value of the node at [index]; returns the index after the node
/// (and its children).
int _copyNode(List<ComponentCodecOp> ops, int index, PacketReader r, PacketWriter w) {
  final op = ops[index];
  switch (op.kind) {
    case CodecOpKind.varInt:
      w.writeVarInt(r.readVarInt());
    case CodecOpKind.varLong:
      w.writeVarLong(r.readVarLong());
    case CodecOpKind.flag || CodecOpKind.byte:
      w.writeByte(r.readUnsignedByte());
    case CodecOpKind.short:
      w.writeShort(r.readShort());
    case CodecOpKind.int32:
      w.writeInt(r.readInt());
    case CodecOpKind.long:
      w.writeLong(r.readLong());
    case CodecOpKind.float32:
      w.writeFloat(r.readFloat());
    case CodecOpKind.float64:
      w.writeDouble(r.readDouble());
    case CodecOpKind.text || CodecOpKind.byteArray:
      // Copy the bytes rather than re-encoding a string: the length is the same
      // and invalid UTF-8 in a value must not make the whole payload undecodable.
      w.writeByteArray(r.readByteArray());
    case CodecOpKind.uuid:
      w.writeUuid(r.readUuid());
    case CodecOpKind.fixedBytes:
      w.writeBytes(r.readBytes(op.argument));
    case CodecOpKind.nbt:
      w.writeNbt(r.readNbt());
    case CodecOpKind.stack:
      ItemStackData.read(r).write(w);
    case CodecOpKind.componentPatch:
      ItemComponentPatch.read(r).write(w);
    case CodecOpKind.optional:
      final present = r.readBool();
      w.writeBool(present);
      if (present) return _copyNode(ops, index + 1, r, w);
      return _nodeEnd(ops, index + 1);
    case CodecOpKind.repeated:
      final count = r.readVarInt();
      if (count < 0) throw PacketException('Negative count $count');
      w.writeVarInt(count);
      for (var i = 0; i < count; i++) {
        _copyNode(ops, index + 1, r, w);
      }
      return _nodeEnd(ops, index + 1);
    case CodecOpKind.sequence:
      var next = index + 1;
      for (var i = 0; i < op.argument; i++) {
        next = _copyNode(ops, next, r, w);
      }
      return next;
  }
  return index + 1;
}

/// The index after the node at [index], without reading anything.
int _nodeEnd(List<ComponentCodecOp> ops, int index) {
  final op = ops[index];
  switch (op.kind) {
    case CodecOpKind.optional || CodecOpKind.repeated:
      return _nodeEnd(ops, index + 1);
    case CodecOpKind.sequence:
      var next = index + 1;
      for (var i = 0; i < op.argument; i++) {
        next = _nodeEnd(ops, next);
      }
      return next;
    default:
      return index + 1;
  }
}

/// Thrown when a data component cannot be delimited because nobody registered its codec.
final class UnsupportedComponentException extends PacketException {
  final int typeId;

  UnsupportedComponentException(this.typeId)
    : super('Data component type $typeId has no wire reader (register it with ItemComponents.register)');
}

/// A `DataComponentPatch`: components added (with their raw value bytes) and removed.
final class ItemComponentPatch {
  /// `(type id, value bytes in the component's own codec)`, in wire order.
  final List<(int, Uint8List)> added;
  final List<int> removed;

  const ItemComponentPatch({this.added = const [], this.removed = const []});

  static const ItemComponentPatch empty = ItemComponentPatch();

  bool get isEmpty => added.isEmpty && removed.isEmpty;

  factory ItemComponentPatch.read(PacketReader r) {
    final addedCount = r.readVarInt();
    final removedCount = r.readVarInt();
    if (addedCount < 0 || removedCount < 0 || addedCount > 4096 || removedCount > 4096) {
      throw PacketException('Implausible component patch size $addedCount/$removedCount');
    }
    if (addedCount == 0 && removedCount == 0) return empty;
    final added = <(int, Uint8List)>[];
    for (var i = 0; i < addedCount; i++) {
      final id = r.readVarInt();
      final copier = ItemComponents.of(id) ?? (throw UnsupportedComponentException(id));
      added.add((id, PacketBuffer.encode((w) => copier(r, w))));
    }
    return ItemComponentPatch(added: added, removed: [for (var i = 0; i < removedCount; i++) r.readVarInt()]);
  }

  void write(PacketWriter w) {
    w.writeVarInt(added.length);
    w.writeVarInt(removed.length);
    for (final (id, bytes) in added) {
      w.writeVarInt(id);
      w.writeBytes(bytes);
    }
    removed.forEach(w.writeVarInt);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemComponentPatch && deepEquals(added.map((e) => [e.$1, e.$2]).toList(), other.added.map((e) => [e.$1, e.$2]).toList()) && deepEquals(removed, other.removed);

  @override
  int get hashCode => Object.hash(added.length, Object.hashAll(removed));
}

/// Maps item keys to the numeric registry ids on the wire and back.
final class ItemIdResolver {
  final int? Function(String key) _idOf;
  final String? Function(int id) _keyOf;

  const ItemIdResolver._(this._idOf, this._keyOf);

  /// Vanilla ids from `VanillaIds.items`; custom items through [custom]
  /// (`(key) => ctx.ids.of(RegistryKind.items, key)`) and [customKeys].
  factory ItemIdResolver.vanilla({int? Function(String key)? custom, String? Function(int id)? customKey}) =>
      ItemIdResolver._(
        (key) => VanillaIds.items.idOf(key) ?? custom?.call(key),
        (id) => VanillaIds.items.keyOf(id) ?? customKey?.call(id),
      );

  int? idOf(String key) => _idOf(key);
  String? keyOf(int id) => _keyOf(id);
}

/// An item stack as it is on the wire: item id, count and component patch.
/// Empty stacks are [ItemStackData.empty] (count 0).
final class ItemStackData {
  final int itemId;
  final int count;
  final ItemComponentPatch patch;

  const ItemStackData(this.itemId, this.count, [this.patch = ItemComponentPatch.empty]);

  static const ItemStackData empty = ItemStackData(0, 0);

  bool get isEmpty => count <= 0;

  /// A stack of [key] ([ids] resolves it). Throws an [ArgumentError] for unknown items.
  factory ItemStackData.of(String key, ItemIdResolver ids, {int count = 1}) {
    final id = ids.idOf(key) ?? (throw ArgumentError.value(key, 'key', 'is not a known item'));
    return ItemStackData(id, count);
  }

  ItemStackData withCount(int count) => ItemStackData(itemId, count, patch);

  /// Reads `ItemStack.OPTIONAL_STREAM_CODEC`; with [allowEmpty] false an empty
  /// stack is an error (`ItemStack.STREAM_CODEC`).
  static ItemStackData read(PacketReader r, {bool allowEmpty = true}) {
    final count = r.readVarInt();
    if (count <= 0) {
      if (!allowEmpty) throw const PacketException('Empty ItemStack not allowed');
      return empty;
    }
    if (count > maxWireItemCount) throw PacketException('Item count $count is larger than $maxWireItemCount');
    final id = r.readVarInt();
    if (id < 0) throw PacketException('Negative item id $id');
    return ItemStackData(id, count, ItemComponentPatch.read(r));
  }

  void write(PacketWriter w, {bool allowEmpty = true}) {
    if (isEmpty) {
      if (!allowEmpty) throw const PacketException('Empty ItemStack not allowed');
      w.writeVarInt(0);
      return;
    }
    w.writeVarInt(count);
    w.writeVarInt(itemId);
    patch.write(w);
  }

  Uint8List encode({bool allowEmpty = true}) => PacketBuffer.encode((w) => write(w, allowEmpty: allowEmpty));

  static ItemStackData decode(List<int> bytes, {bool allowEmpty = true}) =>
      PacketBuffer.decode(bytes, (r) => read(r, allowEmpty: allowEmpty));

  @override
  bool operator ==(Object other) =>
      other is ItemStackData && (isEmpty && other.isEmpty || other.itemId == itemId && other.count == count && other.patch == patch);

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(itemId, count, patch);

  @override
  String toString() => isEmpty ? 'ItemStackData.empty' : 'ItemStackData(id $itemId x$count${patch.isEmpty ? '' : ', ${patch.added.length}+/${patch.removed.length}- components'})';
}

/// A fluid stack as it is on the wire (`FluidStack.OPTIONAL_STREAM_CODEC`).
final class FluidStackData {
  final int fluidId;
  final int amount;
  final ItemComponentPatch patch;

  const FluidStackData(this.fluidId, this.amount, [this.patch = ItemComponentPatch.empty]);

  static const FluidStackData empty = FluidStackData(0, 0);

  bool get isEmpty => amount <= 0;

  static FluidStackData read(PacketReader r, {bool allowEmpty = true}) {
    final amount = r.readVarInt();
    if (amount <= 0) {
      if (!allowEmpty) throw const PacketException('Empty FluidStack not allowed');
      return empty;
    }
    final id = r.readVarInt();
    if (id < 0) throw PacketException('Negative fluid id $id');
    return FluidStackData(id, amount, ItemComponentPatch.read(r));
  }

  void write(PacketWriter w, {bool allowEmpty = true}) {
    if (isEmpty) {
      if (!allowEmpty) throw const PacketException('Empty FluidStack not allowed');
      w.writeVarInt(0);
      return;
    }
    w.writeVarInt(amount);
    w.writeVarInt(fluidId);
    patch.write(w);
  }

  @override
  bool operator ==(Object other) =>
      other is FluidStackData && (isEmpty && other.isEmpty || other.fluidId == fluidId && other.amount == amount && other.patch == patch);

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(fluidId, amount, patch);

  @override
  String toString() => isEmpty ? 'FluidStackData.empty' : 'FluidStackData(id $fluidId, $amount mB)';
}
