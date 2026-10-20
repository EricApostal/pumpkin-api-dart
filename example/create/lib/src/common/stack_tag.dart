// The persistence tag of an item stack, shared by the plugin's stack codecs. Java persists a
// stack with `ItemStack.CODEC`, `{id, count, components?}` (`TransferUtil.saveItem`), so that is
// what the plugin writes as well and a Dart-saved world stays readable by the Create mod.
//
// The plugin only ever holds components as network-encoded bytes (`ItemStack.getComponents`),
// which cannot be turned back into the codec form Java persists: that would need a decoder per
// component and the plugin has encoders only. So the network bytes travel in the private `Comps`
// list next to the Java keys, and a `components` compound read from a Java save is kept
// verbatim. Nothing here interprets the codec form.
//
// Pure (the network NBT model, not the host's `NbtCompound`), so the shape is testable on the
// Dart VM; the host codecs convert with `common/nbt_convert.dart`.
import '../core/nbt.dart';

/// A stack tag as the plugin reads it back: the item and its count, the plugin's component bytes
/// ([comps], network encoding) and the codec-form components of a Java save ([components],
/// uninterpreted; `null` for a tag the plugin wrote itself).
typedef StackTag = ({
  String id,
  int count,
  int? maxStack,
  bool? damageable,
  List<(String, List<int>)> comps,
  NbtValue? components,
});

/// The one persistence form of a stack: Java's `{id, count, components?}` plus the plugin's
/// lossless extras (`Max`, `Dmg`, `Comps`), which Java ignores.
abstract final class JavaStackTag {
  /// The private list the plugin's network-encoded component bytes travel in.
  static const String compsKey = 'Comps';

  /// The Java key of the codec-form components of a Java save.
  static const String componentsKey = 'components';

  /// The persistence tag of a stack: `id` and `count` for Java, the plugin's [comps] bytes as
  /// the private [compsKey] list, [components] written back verbatim, and `Max` / `Dmg` for
  /// [maxStack] and [damageable].
  static NbtValue write({
    required String id,
    required int count,
    List<(String, List<int>)> comps = const [],
    NbtValue? components,
    int? maxStack,
    bool? damageable,
  }) {
    final tag = <String, NbtValue>{
      'id': NbtValue.string(id),
      'count': NbtValue.int32(count),
    };
    if (maxStack != null) tag['Max'] = NbtValue.int32(maxStack);
    if (damageable != null) tag['Dmg'] = NbtValue.byte(damageable ? 1 : 0);
    if (comps.isNotEmpty) {
      tag[compsKey] = NbtValue.list([
        for (final (name, bytes) in comps)
          NbtValue.compound({
            'N': NbtValue.string(name),
            'V': NbtValue.byteArray(bytes),
          }),
      ]);
    }
    if (components != null) tag[componentsKey] = components;
    return NbtValue.compound(tag);
  }

  /// The tag a Create client reads from a block entity update tag (`ItemStack.CODEC`): `id`,
  /// `count` and the preserved codec components.
  static NbtValue writeClient({required String id, required int count, NbtValue? components}) {
    final tag = <String, NbtValue>{
      'id': NbtValue.string(id),
      'count': NbtValue.int32(count),
    };
    if (components != null) tag[componentsKey] = components;
    return NbtValue.compound(tag);
  }

  /// The stack of [tag] — the Java form, the plugin's own form, or a mix — or `null` when the
  /// tag holds no stack (an empty compound, or an `id` without a positive count). The plugin's
  /// own older keys (`Key`, `Count`) are still read: worlds saved before the Java form.
  static StackTag? read(NbtValue? tag) {
    if (tag == null || tag.kind != NbtKind.compound) return null;
    final map = tag.asCompound;
    final id = _string(map['id']) ?? _string(map['Key']);
    // `ItemStack.CODEC` defaults a missing count to 1.
    final count = _int(map['count']) ?? _int(map['Count']) ?? 1;
    if (id == null || count <= 0) return null;
    final comps = <(String, List<int>)>[];
    final list = map[compsKey];
    if (list != null && list.kind == NbtKind.list) {
      for (final e in list.value as List<NbtValue>) {
        if (e.kind != NbtKind.compound) continue;
        final entry = e.asCompound;
        final name = _string(entry['N']);
        final bytes = entry['V'];
        if (name != null && bytes != null && bytes.kind == NbtKind.byteArray) {
          comps.add((name, List<int>.of(bytes.value as List<int>)));
        }
      }
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    final components = map[componentsKey];
    final damage = _int(map['Dmg']);
    return (
      id: id,
      count: count,
      maxStack: _int(map['Max']),
      damageable: damage == null ? null : damage != 0,
      comps: comps,
      components: components != null && components.kind == NbtKind.compound ? components : null,
    );
  }

  static String? _string(NbtValue? v) => v != null && v.kind == NbtKind.string ? v.value as String : null;

  static int? _int(NbtValue? v) => switch (v?.kind) {
    NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => v!.value as int,
    _ => null,
  };
}