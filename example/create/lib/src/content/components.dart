// The 57 data components of `AllDataComponents` with the network encoding of
// their `networkSynchronized` stream codec, written as the prefix-op codec the
// host needs (`custom-components.wit`). Pure: no host bindings.
//
// The wire format is exactly the one of the Java `StreamCodec` (26.3):
//  * `BlockPos.STREAM_CODEC` is one long (`BlockPos.asLong`)
//  * `ByteBufCodecs.INT/FLOAT/BOOL`: 4 bytes / 4 bytes / 1 byte; `VAR_INT`: VarInt
//  * `CatnipStreamCodecBuilders.ofEnum` and `idMapper`: VarInt
//  * `list(...)`: VarInt count then the elements
//  * `Component` (`ComponentSerialization.STREAM_CODEC`): a network NBT tag
//  * `ItemStack.OPTIONAL_STREAM_CODEC`: the play stack encoding (count 0 = empty)
//  * `ItemContainerContents` (26.3): list of optional `ItemStackTemplate`
//    (VarInt item id, VarInt count, data component patch)
//  * `StreamCodec.unit`: no bytes
//
// The same descriptions also build the wire readers (`ItemComponents`): a payload
// that carries an item stack can only be decoded when the length of every
// component value in the stack's patch is known, so [registerComponentReaders]
// registers one copier per component once the host assigned its id.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../api/registry/create_registries.dart';
import '../protocol/item_stack.dart';

/// Registration data of one component.
final class CreateComponent {
  /// The path in the `create` namespace.
  final String path;
  final ComponentCodec codec;

  /// Whether the Java codec is only an approximation (see [note]).
  final bool approximate;
  final String? note;

  const CreateComponent(this.path, this.codec, {this.approximate = false, this.note});

  String get key => 'create:$path';
}

// ---- building blocks ---------------------------------------------------------

const ComponentCodec _varInt = ComponentCodec.varInt;
const ComponentCodec _flag = ComponentCodec.flag;
const ComponentCodec _int = ComponentCodec.int32;
const ComponentCodec _float = ComponentCodec.float32;
const ComponentCodec _double = ComponentCodec.float64;
const ComponentCodec _long = ComponentCodec.long;
const ComponentCodec _text = ComponentCodec.text;
const ComponentCodec _nbt = ComponentCodec.nbt;
const ComponentCodec _uuid = ComponentCodec.uuid;
const ComponentCodec _stack = ComponentCodec.stack;

ComponentCodec _seq(List<ComponentCodec> parts) => ComponentCodec.sequence(parts);
ComponentCodec _list(ComponentCodec e) => ComponentCodec.repeated(e);
ComponentCodec _opt(ComponentCodec e) => ComponentCodec.optional(e);

/// `BlockPos.STREAM_CODEC`.
const ComponentCodec blockPosCodec = _long;

/// `CatnipStreamCodecs.VEC3`: three doubles.
final ComponentCodec vec3Codec = _seq([_double, _double, _double]);

/// `CatnipStreamCodecs.VEC3I`: three ints.
final ComponentCodec vec3iCodec = _seq([_int, _int, _int]);

/// `ItemContainerContents.STREAM_CODEC` of 26.3.
final ComponentCodec itemContainerContentsCodec = _list(_opt(_seq([_varInt, _varInt, ComponentCodec.componentPatch])));

/// `StreamCodec.unit(...)`: zero bytes.
final ComponentCodec unitCodec = _seq(const []);

/// `ClipboardEntry.STREAM_CODEC`: checked, text component, icon stack, amount.
final ComponentCodec clipboardEntryCodec = _seq([_flag, _nbt, _stack, _int]);

/// `CatnipStreamCodecBuilders.list(list(ClipboardEntry))`.
final ComponentCodec clipboardPagesCodec = _list(_list(clipboardEntryCodec));

/// `PackageOrder.STREAM_CODEC`: list of `BigItemStack` (stack, VarInt count).
final ComponentCodec packageOrderCodec = _list(_seq([_stack, _varInt]));

/// `PackageOrderWithCrafts.STREAM_CODEC`: the order and a list of crafting entries (order, VarInt count).
final ComponentCodec packageOrderWithCraftsCodec = _seq([
  packageOrderCodec,
  _list(_seq([packageOrderCodec, _varInt])),
]);

/// The components in `AllDataComponents` registration order.
final List<CreateComponent> createComponents = [
  CreateComponent('banktank_air', _varInt),
  CreateComponent('belt_first_shaft', blockPosCodec),
  CreateComponent('inferred_from_recipe', _flag),
  CreateComponent('placement_pattern', _varInt),
  CreateComponent('shaper_brush', _varInt),
  CreateComponent('shaper_brush_params', blockPosCodec),
  CreateComponent('shaper_placement_options', _varInt),
  CreateComponent('shaper_tool', _varInt),
  CreateComponent('shaper_block_used', _varInt),
  CreateComponent('shaper_swap', _flag),
  CreateComponent('shaper_block_data', _nbt),
  CreateComponent('filter_items', itemContainerContentsCodec),
  CreateComponent('filter_items_respect_nbt', _flag),
  CreateComponent('filter_items_blacklist', _flag),
  CreateComponent('attribute_filter_whitelist_mode', _varInt),
  // `ItemAttribute.STREAM_CODEC` is a registry dispatch (VarInt type id, then a per-type payload)
  // that the prefix ops cannot express. This describes the 18 payload-free attribute types
  // (id, inverted); entries of the other 10 types (in_tag, added_by, has_enchant, ...) fail the
  // host's value check. Needs a `dispatch` op in the host (see the report).
  CreateComponent(
    'attribute_filter_matched_attributes',
    _list(_seq([_varInt, _flag])),
    approximate: true,
    note: 'ItemAttribute is a registry dispatch codec; only payload-free attribute types are measurable',
  ),
  CreateComponent(
    'clipboard_content',
    _seq([_varInt, clipboardPagesCodec, _flag, _varInt, _opt(_nbt)]),
  ),
  CreateComponent('track_connecting_from', _seq([blockPosCodec, vec3Codec, vec3Codec, vec3Codec])),
  CreateComponent('track_extend_curve', _flag),
  CreateComponent('track_targeting_item_selected_pos', blockPosCodec),
  CreateComponent('track_targeting_item_selected_direction', _flag),
  CreateComponent('track_targeting_item_bezier', _seq([blockPosCodec, _int])),
  CreateComponent('schematic_deployed', _flag),
  CreateComponent('schematic_owner', _text),
  CreateComponent('schematic_file', _text),
  CreateComponent('schematic_anchor', blockPosCodec),
  CreateComponent('schematic_rotation', _varInt),
  CreateComponent('schematic_mirror', _varInt),
  CreateComponent('schematic_bounds', vec3iCodec),
  CreateComponent('schematic_hash', _int),
  CreateComponent('chromatic_compound_collecting_light', _int),
  CreateComponent('sand_paper_polishing', _stack),
  CreateComponent('sand_paper_jei', unitCodec),
  CreateComponent('minecart_contraption_data', _nbt),
  CreateComponent('linked_controller_items', itemContainerContentsCodec),
  // ToolboxInventory: ItemSlots (map int -> stack, int size), then list(optional stack).
  CreateComponent('toolbox_inventory', _seq([_list(_seq([_int, _stack])), _int, _list(_stack)])),
  CreateComponent('toolbox_uuid', _uuid),
  CreateComponent('sequenced_assembly', _seq([_text, _int, _float])),
  CreateComponent('train_schedule', _nbt),
  CreateComponent('symmetry_wand', _seq([_int, vec3Codec, _text, _flag])),
  CreateComponent('symmetry_wand_enable', _flag),
  CreateComponent('symmetry_wand_simulate', _flag),
  CreateComponent('potion_fluid_bottle_type', _varInt),
  CreateComponent('schematicannon_options', _seq([_int, _flag, _flag])),
  CreateComponent('auto_request_data', _seq([packageOrderWithCraftsCodec, _text, blockPosCodec, _text, _flag])),
  CreateComponent('shopping_list', _seq([_list(_seq([_int, blockPosCodec])), _uuid, _uuid])),
  CreateComponent('shopping_list_address', _text),
  CreateComponent('package_address', _text),
  CreateComponent('package_contents', itemContainerContentsCodec),
  CreateComponent(
    'package_order_data',
    _seq([_int, _int, _flag, _int, _flag, _opt(packageOrderWithCraftsCodec)]),
  ),
  CreateComponent('package_order_context', packageOrderWithCraftsCodec),
  CreateComponent('click_to_link_data', _seq([blockPosCodec, _text])),
  CreateComponent('clipboard_type', _varInt),
  CreateComponent('clipboard_pages', clipboardPagesCodec),
  CreateComponent('clipboard_read_only', unitCodec),
  CreateComponent('clipboard_copied_values', _nbt),
  CreateComponent('clipboard_previously_opened_page', _int),
];

// ---- wire readers ----------------------------------------------------------------------------

/// `create:attribute_filter_matched_attributes`: the one component whose codec
/// description in [createComponents] is an approximation.
const String _attributeFilterComponent = 'create:attribute_filter_matched_attributes';

/// Registers the wire reader (`ItemComponents`) of every component in
/// [createComponents] by the id [idOf] answers for its key; components the host
/// did not register are skipped.
///
/// [attributeTypeId] resolves the host ids of the `create:item_attribute_type`
/// entries, which the one dispatch component needs. [warn] receives a message
/// when a component cannot be delimited exactly: its payloads are then dropped
/// (as before), never misread.
void registerComponentReaders(
  int? Function(String key) idOf, {
  int? Function(String key)? attributeTypeId,
  void Function(String message)? warn,
}) {
  for (final c in createComponents) {
    final id = idOf(c.key);
    if (id == null) continue;
    if (c.approximate) {
      if (c.key == _attributeFilterComponent) {
        ItemComponents.register(id, attributeFilterCopier(attributeTypeId: attributeTypeId));
        continue;
      }
      warn?.call(
        'No exact wire reader for ${c.key}: the codec description is an approximation, so a '
        'payload carrying that component is dropped instead of risking a wrong length',
      );
      continue;
    }
    ItemComponents.register(id, copierForCodec(c.codec));
  }
}

/// The `ItemAttribute` types with no payload (`SingletonItemAttribute.Type`,
/// `AllItemAttributeTypes.java:60-77`).
const List<String> _payloadFreeAttributeTypes = [
  'placeable',
  'consumable',
  'fluid_container',
  'enchanted',
  'max_enchanted',
  'renamed',
  'damaged',
  'badly_damaged',
  'not_stackable',
  'equipable',
  'furnace_fuel',
  'washable',
  'hauntable',
  'crushable',
  'smeltable',
  'smokable',
  'blastable',
  'compostable',
];

/// `ByteBufCodecs.STRING_UTF8` / `Identifier.STREAM_CODEC`: a VarInt length and
/// that many UTF-8 bytes.
void _copyText(PacketReader r, PacketWriter w) => w.writeByteArray(r.readByteArray());

/// `ByteBufCodecs.INT`: four bytes.
void _copyInt(PacketReader r, PacketWriter w) => w.writeInt(r.readInt());

/// `ByteBufCodecs.registry(...)` / `idMapper` / `ofEnum`: a VarInt id.
void _copyVarInt(PacketReader r, PacketWriter w) => w.writeVarInt(r.readVarInt());

/// `CatnipStreamCodecBuilders.nullable(Identifier.STREAM_CODEC)`.
void _copyNullableText(PacketReader r, PacketWriter w) {
  final present = r.readBool();
  w.writeBool(present);
  if (present) _copyText(r, w);
}

/// `CatnipStreamCodecBuilders.nullable(CatnipStreamCodecs.FLUID)`.
void _copyNullableVarInt(PacketReader r, PacketWriter w) {
  final present = r.readBool();
  w.writeBool(present);
  if (present) _copyVarInt(r, w);
}

/// The value codec of one `create:item_attribute_type` entry, or null when the
/// type is not known.
ComponentCopier? attributePayloadCopier(String type) => switch (type) {
  // InTagAttribute (tag id), AddedByAttribute, ItemNameAttribute, BookAuthorAttribute.
  'in_tag' || 'added_by' || 'has_name' || 'book_author' => _copyText,
  // InItemGroupAttribute (nullable creative tab id).
  'in_item_group' => _copyNullableText,
  // EnchantAttribute (enchantment holder id), ShulkerFillLevelAttribute (enum
  // ordinal), ColorAttribute (DyeColor id).
  'has_enchant' || 'shulker_fill_level' || 'has_color' => _copyVarInt,
  // FluidContentsAttribute (nullable fluid id).
  'has_fluid' => _copyNullableVarInt,
  // BookCopyAttribute (generation).
  'book_copy' => _copyInt,
  _ => _payloadFreeAttributeTypes.contains(type) ? ItemComponents.copyNothing : null,
};

/// The reader of `create:attribute_filter_matched_attributes`:
/// `ItemAttribute.STREAM_CODEC` (`ItemAttribute.java:29`) is a registry dispatch
/// on `create:item_attribute_type`, a VarInt type id and then that type's own
/// stream codec (`AllItemAttributeTypes.java:60-79`).
///
/// [attributeTypeId] maps an entry key (`create:in_tag`) to the host id; without
/// it the ids are the manifest registration order (the order the plugin declares
/// the synced registry in), which is what the host assigns.
ComponentCopier attributeFilterCopier({int? Function(String key)? attributeTypeId}) {
  final byId = <int, ComponentCopier>{};
  final entries = CreateBuiltInRegistries.entries[CreateRegistries.itemAttributeType] ?? const <String>[];
  for (var index = 0; index < entries.length; index++) {
    final key = entries[index];
    final payload = attributePayloadCopier(key.substring(key.indexOf(':') + 1));
    if (payload == null) continue;
    byId[attributeTypeId?.call(key) ?? index] = payload;
  }
  return (r, w) {
    final id = r.readVarInt();
    w.writeVarInt(id);
    final payload = byId[id];
    if (payload == null) throw PacketException('Item attribute type $id has no wire reader');
    payload(r, w);
  };
}
