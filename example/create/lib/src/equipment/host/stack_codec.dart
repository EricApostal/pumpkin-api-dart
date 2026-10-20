// Item stacks to plain values ([TStack]) and plugin NBT, and back. The host exposes the data
// components of a stack as raw bytes (`get-components`), which is enough to keep enchantments,
// damage and custom names of stored items intact.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../../common/stack_tag.dart';
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

  /// The persistence form of a stack: Java's `ItemStack.CODEC` shape, with the plugin's own
  /// extras (see `common/stack_tag.dart`).
  static NbtCompound toNbt(TStack t) => compoundOf(
        JavaStackTag.write(
          id: t.key,
          count: t.count,
          comps: t.comps,
          components: t.rawComponents,
          maxStack: t.maxStack,
          damageable: t.damageable,
        ),
      );

  static TStack fromNbt(NbtCompound c) {
    final t = JavaStackTag.read(valueOfCompound(c));
    if (t == null) return TStack.empty;
    return TStack(
      t.id,
      t.count,
      maxStack: t.maxStack ?? 64,
      damageable: t.damageable ?? false,
      comps: t.comps,
      rawComponents: t.components,
    );
  }

  /// The vanilla-looking stack tag the Create client reads from a block entity update tag:
  /// `{id, count}` and, when a Java save provided them, its components.
  static NbtCompound toClientNbt(TStack t) =>
      compoundOf(JavaStackTag.writeClient(id: t.key, count: t.count, components: t.rawComponents));

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
NbtValue nbtCompoundToValue(NbtCompound c) => valueOfCompound(c);
