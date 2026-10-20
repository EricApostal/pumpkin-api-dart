// NBT forms of an [LStack]. The Create client reads `{id, count}` stack tags from block entity
// update tags; the plugin's own saved data keeps the whole stack as JSON next to it.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../model/stack.dart';
import '../model/stack_tags.dart' show pluginStackKey;

/// `TransferUtil.saveItem` for the client (`client` true: only `{id, count}`, what a Create client
/// can read) or for saving (adds the lossless JSON). An empty stack is an empty compound.
NbtCompound stackToNbt(LStack s, {required bool client}) {
  final tag = NbtCompound();
  if (s.isEmpty) return tag;
  tag
    ..putString('id', s.key)
    ..putInt('count', s.count);
  if (!client) tag.putString(pluginStackKey, s.toJson());
  return tag;
}

/// `TransferUtil.parseItem`: the stack of [tag] (the JSON copy when present, else `{id, count}`).
LStack stackFromNbt(NbtCompound? tag, {int maxStack = 64}) {
  if (tag == null) return LStack.empty;
  final json = tag.getString(pluginStackKey);
  if (json != null) {
    try {
      return LStackMapper.fromJson(json);
    } on Object {
      // fall through to the plain form
    }
  }
  final id = tag.getString('id');
  if (id == null) return LStack.empty;
  final count = tag.getInt('count') ?? tag.getInt('Count') ?? 1;
  return count <= 0 ? LStack.empty : LStack(id, count, maxStack: maxStack);
}

/// A list of stacks as NBT (empty slots stay empty compounds, so slot positions survive).
List<Object> stacksToNbt(Iterable<LStack> stacks, {required bool client}) => [for (final s in stacks) stackToNbt(s, client: client)];

List<LStack> stacksFromNbt(List<Object>? list) => [
  for (final e in list ?? const <Object>[]) e is NbtCompound ? stackFromNbt(e) : LStack.empty,
];

/// A UUID string as the 4 ints of `UUIDUtil.CODEC`.
List<int> uuidToInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  int part(int i) => int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16).toSigned(32);
  return [part(0), part(1), part(2), part(3)];
}

String uuidFromInts(List<int> ints) {
  final hex = [for (final i in ints) (i & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
