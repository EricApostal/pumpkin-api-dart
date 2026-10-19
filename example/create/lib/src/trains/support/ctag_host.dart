// Conversions between [CTag] (pure) and the host's `NbtCompound` / `NbtTree`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../../core/nbt.dart';
import '../util/ctag.dart';

extension CTagToHost on CTag {
  /// The host compound with the same content.
  NbtCompound toHost() => NbtCompound.fromTree(valueToTree(toNbt()));

  /// Copies every entry of this tag into [target] (the host has no merge).
  void mergeInto(NbtCompound target) {
    for (final entry in entries.entries) {
      _put(target, entry.key, entry.value);
    }
  }

  static void _put(NbtCompound target, String key, NbtValue value) {
    switch (value.kind) {
      case NbtKind.end:
        return;
      case NbtKind.byte:
        target.putByte(key, value.value as int);
      case NbtKind.short:
        target.putShort(key, value.value as int);
      case NbtKind.int:
        target.putInt(key, value.value as int);
      case NbtKind.long:
        target.putLong(key, value.value as int);
      case NbtKind.float:
        target.putFloat(key, value.value as double);
      case NbtKind.double:
        target.putDouble(key, value.value as double);
      case NbtKind.byteArray:
        target.putByteArray(key, value.value as List<int>);
      case NbtKind.string:
        target.putString(key, value.value as String);
      case NbtKind.intArray:
        target.putIntArray(key, value.value as List<int>);
      case NbtKind.longArray:
        target.putLongArray(key, value.value as List<int>);
      case NbtKind.list:
        target.putList(key, [
          for (final e in value.value as List<NbtValue>) _hostTag(e),
        ]);
      case NbtKind.compound:
        target.putCompound(key, compoundOf(value));
    }
  }

  /// The generated host tag of [value] (for list elements).
  static Object _hostTag(NbtValue value) {
    if (value.kind == NbtKind.compound) return compoundOf(value);
    final tree = valueToTree(value);
    return tree.tags[tree.root];
  }
}

extension HostToCTag on NbtCompound {
  /// A pure copy of this compound.
  CTag toCTag() => CTag.fromNbt(treeToValue(toTree()));
}
