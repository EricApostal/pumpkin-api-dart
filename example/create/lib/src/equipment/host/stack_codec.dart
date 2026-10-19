// Item stacks to plain values ([TStack]) and plugin NBT, and back. The host exposes the data
// components of a stack as raw bytes (`get-components`), which is enough to keep enchantments,
// damage and custom names of stored items intact.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/nbt.dart';
import '../toolbox/toolbox_model.dart';

/// The custom (`create:*`) data components that make a stack different from another of the same
/// item (the vanilla `getComponents` does not list custom components).
const List<String> kStateComponents = [
  'create:banktank_air',
  'create:filter_items',
  'create:filter_items_respect_nbt',
  'create:filter_items_blacklist',
  'create:attribute_filter_whitelist_mode',
  'create:attribute_filter_matched_attributes',
  'create:clipboard_content',
  'create:toolbox_inventory',
  'create:toolbox_uuid',
  'create:symmetry_wand',
  'create:symmetry_wand_enable',
  'create:placement_pattern',
  'create:shaper_brush',
  'create:shaper_brush_params',
  'create:shaper_placement_options',
  'create:shaper_tool',
  'create:shaper_block_used',
  'create:shaper_block_data',
  'create:belt_first_shaft',
  'create:schematic_file',
  'create:schematic_owner',
  'create:schematic_anchor',
  'create:schematic_rotation',
  'create:schematic_mirror',
  'create:schematic_bounds',
  'create:schematic_hash',
  'create:schematic_deployed',
  'create:linked_controller_items',
  'create:minecart_contraption_data',
  'create:sequenced_assembly',
  'create:train_schedule',
  'create:sand_paper_polishing',
];

abstract final class StackCodec {
  /// Prefix of the component names that are custom components.
  static const customPrefix = 'custom:';

  /// Reads [stack] into a value (the stack handle is not consumed).
  static Future<TStack> read(ItemStack? stack) async {
    if (stack == null) return TStack.empty;
    final count = await stack.getCount();
    if (count <= 0) return TStack.empty;
    final key = await stack.getRegistryKey();
    final max = await stack.getMaxCount();
    final comps = <(String, List<int>)>[];
    var maxDamage = 0;
    for (final c in await stack.getComponents()) {
      comps.add((c.component.wireName, List<int>.of(c.value)));
      if (c.component == DataComponent.maxDamage) maxDamage = _varInt(c.value);
    }
    for (final k in kStateComponents) {
      List<int>? v;
      try {
        v = stack.customComponent(k);
      } on Object {
        v = null;
      }
      if (v != null) comps.add(('$customPrefix$k', List<int>.of(v)));
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return TStack(key, count, maxStack: max, damageable: maxDamage > 0, comps: comps);
  }

  /// A new host stack for [t] with its components (the caller owns it).
  static Future<ItemStack?> write(TStack t) async {
    if (t.isEmpty) return null;
    final s = ItemStack.create(registryKey: t.key, count: t.count);
    for (final (name, bytes) in t.comps) {
      if (name.startsWith(customPrefix)) {
        try {
          s.setCustomComponent(name.substring(customPrefix.length), bytes);
        } on Object {
          // a custom component the host rejects is dropped
        }
        continue;
      }
      final c = DataComponent.fromWireName(name);
      if (c == null) continue;
      try {
        await s.setComponent(component: c, value: bytes);
      } on Object {
        // a component the host cannot set is dropped
      }
    }
    return s;
  }

  // -- plugin NBT ----------------------------------------------------------------------

  /// The private persistence form of a stack (`Key`, `Count`, `Max`, `Dmg`, `Comps`).
  static NbtCompound toNbt(TStack t) {
    final c = NbtCompound()
      ..putString('Key', t.key)
      ..putInt('Count', t.count)
      ..putInt('Max', t.maxStack)
      ..putBool('Dmg', t.damageable);
    final list = <Object>[
      for (final (name, bytes) in t.comps)
        NbtCompound()
          ..putString('N', name)
          ..putByteArray('V', bytes),
    ];
    c.putList('Comps', list);
    return c;
  }

  static TStack fromNbt(NbtCompound c) {
    final key = c.getString('Key');
    final count = c.getInt('Count') ?? 0;
    if (key == null || count <= 0) return TStack.empty;
    final comps = <(String, List<int>)>[];
    for (final e in c.getList('Comps') ?? const <Object>[]) {
      if (e is NbtCompound) {
        final n = e.getString('N');
        final v = e.getByteArray('V');
        if (n != null && v != null) comps.add((n, v));
      }
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return TStack(
      key,
      count,
      maxStack: c.getInt('Max') ?? 64,
      damageable: c.getBool('Dmg') ?? false,
      comps: comps,
    );
  }

  /// The vanilla-looking stack tag the Create client reads from a block entity update tag:
  /// `{id, count}` (components are not representable here).
  static NbtCompound toClientNbt(TStack t) => NbtCompound()
    ..putString('id', t.key)
    ..putInt('count', t.count);

  static int _varInt(List<int> bytes) {
    var value = 0;
    var shift = 0;
    for (final b in bytes) {
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return value;
  }
}

/// Converts the host's NBT compound into the pure network NBT model (for payload fields and
/// menu extra data).
NbtValue nbtCompoundToValue(NbtCompound c) => _treeToValue(c.toTree());

NbtValue _treeToValue(NbtTree tree) => _tagToValue(tree, tree.root, 0);

NbtValue _tagToValue(NbtTree tree, int index, int depth) {
  final tag = tree.tags[index];
  switch (tag) {
    case NbtTagByte(:final value):
      return NbtValue.byte(value);
    case NbtTagShort(:final value):
      return NbtValue.short(value);
    case NbtTagInt(:final value):
      return NbtValue.int32(value);
    case NbtTagLong(:final value):
      return NbtValue.long(value);
    case NbtTagFloat(:final value):
      return NbtValue.float(value);
    case NbtTagDouble(:final value):
      return NbtValue.double64(value);
    case NbtTagStringTag(:final value):
      return NbtValue.string(value);
    case NbtTagByteArray(:final value):
      return NbtValue.byteArray(value);
    case NbtTagIntArray(:final value):
      return NbtValue.intArray(value);
    case NbtTagLongArray(:final value):
      return NbtValue.longArray(value);
    case NbtTagListTag(:final value):
      return NbtValue.list([for (final i in value) _tagToValue(tree, i, depth + 1)]);
    case NbtTagCompound(:final value):
      return NbtValue.compound({for (final e in value) e.key: _tagToValue(tree, e.value, depth + 1)});
  }
}
