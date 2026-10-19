// Conversions between the pure NBT model (`NbtValue`, used by payloads and binary NBT) and the
// host's `NbtCompound` / `NbtTree`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/nbt.dart';

/// The pure value of [tree] (its root).
NbtValue treeToValue(NbtTree tree) => _read(tree, tree.root, 0);

NbtValue _read(NbtTree tree, int index, int depth) {
  if (depth > 128) throw const FormatException('NBT is nested too deeply');
  final tag = tree.tags[index];
  return switch (tag) {
    NbtTagByte(:final value) => NbtValue.byte(value),
    NbtTagShort(:final value) => NbtValue.short(value),
    NbtTagInt(:final value) => NbtValue.int32(value),
    NbtTagLong(:final value) => NbtValue.long(value),
    NbtTagFloat(:final value) => NbtValue.float(value),
    NbtTagDouble(:final value) => NbtValue.double64(value),
    NbtTagByteArray(:final value) => NbtValue.byteArray(value),
    NbtTagStringTag(:final value) => NbtValue.string(value),
    NbtTagListTag(:final value) => NbtValue.list([for (final i in value) _read(tree, i, depth + 1)]),
    NbtTagCompound(:final value) => NbtValue.compound({for (final e in value) e.key: _read(tree, e.value, depth + 1)}),
    NbtTagIntArray(:final value) => NbtValue.intArray(value),
    NbtTagLongArray(:final value) => NbtValue.longArray(value),
  };
}

/// The host tree of [value].
NbtTree valueToTree(NbtValue value) {
  final tags = <NbtTag>[];
  final root = _add(value, tags);
  return NbtTree(root: root, tags: tags);
}

int _add(NbtValue v, List<NbtTag> tags) {
  switch (v.kind) {
    case NbtKind.end:
      throw ArgumentError('TAG_End cannot be a value');
    case NbtKind.byte:
      tags.add(NbtTagByte(v.value as int));
    case NbtKind.short:
      tags.add(NbtTagShort(v.value as int));
    case NbtKind.int:
      tags.add(NbtTagInt(v.value as int));
    case NbtKind.long:
      tags.add(NbtTagLong(v.value as int));
    case NbtKind.float:
      tags.add(NbtTagFloat(v.value as double));
    case NbtKind.double:
      tags.add(NbtTagDouble(v.value as double));
    case NbtKind.byteArray:
      tags.add(NbtTagByteArray(v.value as List<int>));
    case NbtKind.string:
      tags.add(NbtTagStringTag(v.value as String));
    case NbtKind.intArray:
      tags.add(NbtTagIntArray(v.value as List<int>));
    case NbtKind.longArray:
      tags.add(NbtTagLongArray(v.value as List<int>));
    case NbtKind.list:
      final indices = [for (final e in v.value as List<NbtValue>) _add(e, tags)];
      tags.add(NbtTagListTag(indices));
    case NbtKind.compound:
      final entries = [
        for (final e in (v.value as Map<String, NbtValue>).entries) NbtEntry(key: e.key, value: _add(e.value, tags)),
      ];
      tags.add(NbtTagCompound(entries));
  }
  return tags.length - 1;
}

/// The host compound of a compound [value].
NbtCompound compoundOf(NbtValue value) => NbtCompound.fromTree(valueToTree(value));

/// The pure value of a host compound.
NbtValue valueOfCompound(NbtCompound compound) => treeToValue(compound.toTree());
