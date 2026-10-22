// The pure rules of the blueprint grid and its ghost slots: the ingredient filters
// `BlueprintItem.assignCompleteRecipe` writes into the nine grid cells, the crafting match of
// `BlueprintEntity.calculateCraftingResult` and the shift-click of `GhostItemMenu.quickMoveStack`.
// Kept out of `blueprint_host.dart` (which needs the host bindings) so it is testable on the VM,
// like `blueprint_geometry.dart`.
//
// The grid cells are protocol stacks ([TStack], `StackCodec`): the ingredients come in as item keys
// and tags (the host's `Ingredient` type stays in the host glue) and the filter model
// (`FilterItemStack`) is handed the [LStack] form of a cell.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketBuffer, VanillaIds;

import '../../common/ghost_menu_layout.dart';
import '../../common/ghost_quick_move.dart';
import '../../core/nbt.dart';
import '../../logistics/filter/filter_item_stack.dart';
import '../../logistics/filter/item_attribute.dart' show InTagAttribute, ItemAttributeEntry;
import '../../logistics/model/package.dart' show PackageComponents;
import '../../logistics/model/stack.dart';
import '../../logistics/model/stack_wire.dart';
import '../../protocol/item_stack.dart' show ItemIdResolver;
import '../toolbox/toolbox_model.dart';

/// The prefix `StackCodec` puts on a Create data component of a protocol stack; a vanilla
/// component keeps the wire name of its type.
const String _customPrefix = 'custom:';

// ---------------------------------------------------------------------------------------
// Ingredient filters (`BlueprintItem.convertIngredientToFilter`, `BlueprintItem.java:74-150`)
// ---------------------------------------------------------------------------------------

/// The [LStack] value of a protocol stack, the form the filter model wants.
///
/// [FilterItemStack] and [LStack] name a data component by its registry key
/// (`minecraft:custom_data`, `create:filter_items`), while the protocol form keeps the wire name
/// of a vanilla component ([StackCodec.read]) and prefixes a Create component with `custom:`. A
/// component name this process cannot place (a vanilla component the wire layer does not know) is
/// dropped, as `StackWire.fromData` drops an id it cannot name.
LStack blueprintStackValue(TStack t) {
  if (t.comps.isEmpty) {
    return LStack(t.key, t.count, maxStack: t.maxStack, damageable: t.damageable);
  }
  final comps = <String, String>{};
  for (final (name, bytes) in t.comps) {
    final key = blueprintComponentKey(name);
    if (key == null) continue;
    comps[key] = base64Encode(bytes);
  }
  return LStack(
    t.key,
    t.count,
    maxStack: t.maxStack,
    damageable: t.damageable,
    comps: Map.fromEntries(comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
  );
}

/// The registry key behind a protocol component name (see [blueprintStackValue]), `null` for a
/// name the vanilla component registry does not know.
String? blueprintComponentKey(String name) {
  if (name.startsWith(_customPrefix)) return name.substring(_customPrefix.length);
  final key = 'minecraft:${name.replaceAll('-', '_')}';
  return VanillaIds.dataComponentTypes.idOf(key) == null ? null : key;
}

/// The grid cell of one item ingredient: `new ItemStack(item)` (`convertIItemListToFilter`).
TStack blueprintItemStack(String item) => TStack(_namespaced(item), 1);

/// The grid cell of an item tag: a `create:attribute_filter` holding one `in_tag` attribute that
/// is not inverted, in `AttributeFilterWhitelistMode.WHITELIST_DISJ` (`convertIItemListToFilter`).
///
/// Java sets `AllDataComponents.ATTRIBUTE_FILTER_MATCHED_ATTRIBUTES`, whose stream codec is a
/// registry dispatch on `create:item_attribute_type`. The host cannot check that payload (see
/// [FilterComponents.privateAttributes]), so the entry is written the way the filter screens write
/// it: into the private `minecraft:custom_data` key that [AttributeFilterItemStack] reads back.
/// Java sets no `filter_items_respect_nbt` on an attribute filter.
TStack blueprintTagStack(String tag) {
  final entry = ItemAttributeEntry(InTagAttribute(_tagKey(tag)), false);
  final attributes = NetworkNbt.encode(
    NbtValue.compound({
      FilterComponents.privateAttributes: NbtValue.string(jsonEncode([entry.toMap()])),
    }),
  );
  return TStack(
    FilterItemKeys.attribute,
    1,
    comps: [
      (
        '$_customPrefix${FilterComponents.whitelistMode}',
        [AttributeFilterWhitelistMode.whitelistDisj.index],
      ),
      ('custom-data', attributes),
    ],
  );
}

/// The grid cell of an ingredient with several alternatives (`convertIngredientToFilter`): the
/// alternatives become a `create:filter` whose `create:filter_items` holds all of them; a single
/// alternative resolves on its own and more than 18 (or none) leave the cell empty
/// (`acceptedItems.size() > 18`).
///
/// [ids] is the item id table of the host, so the `create:filter_items` value holds the ids it can
/// read back. Java's last branch, a custom (nested) sub-ingredient in a sub-filter that respects
/// NBT, has no ingredient to map here: the wire API flattens an ingredient to items and tags.
TStack blueprintAlternativesStack(List<String> items, {required ItemIdResolver ids}) {
  if (items.isEmpty || items.length > 18) return TStack.empty;
  if (items.length == 1) return blueprintItemStack(items.single);
  return _listFilterStack([for (final item in items) blueprintItemStack(item)], ids);
}

/// The item id of an ingredient entry (the `minecraft:` namespace when it has none).
String _namespaced(String key) => key.contains(':') ? key : 'minecraft:$key';

/// `TagKey.location()`: the tag id without a leading `#`, namespaced like [_namespaced].
String _tagKey(String tag) => _namespaced(tag.startsWith('#') ? tag.substring(1) : tag);

/// The `create:filter` of several alternatives: every alternative in `create:filter_items`. The
/// filter item's handler has 18 slots and Java encodes all of them
/// (`ItemHelper.containerContentsFromHandler`), the empty ones as absent stacks.
TStack _listFilterStack(List<TStack> alternatives, ItemIdResolver ids) {
  return TStack(
    FilterItemKeys.list,
    1,
    comps: [
      ('$_customPrefix${FilterComponents.filterItems}', _filterItemsValue(alternatives, ids)),
    ],
  );
}

/// `ItemContainerContents.STREAM_CODEC` of the filter slots (`StackWire.writeContents`).
List<int> _filterItemsValue(List<TStack> alternatives, ItemIdResolver ids) {
  final wire = StackWire(items: ids, componentIdOf: (_) => null, componentNameOf: (_) => null);
  final slots = [
    for (var i = 0; i < 18; i++)
      i < alternatives.length ? blueprintStackValue(alternatives[i]) : LStack.empty,
  ];
  return PacketBuffer.encode((w) => wire.writeContents(w, slots));
}

// ---------------------------------------------------------------------------------------
// Crafting (`BlueprintEntity.calculateCraftingResult`, `BlueprintEntity.java:429-460`)
// ---------------------------------------------------------------------------------------

/// Whether [candidate] passes the grid slot [filter]:
/// `FilterItemStack.of(slot).test(level, stack)`, the two-argument overload, so `matchNBT` is
/// `false` at the top level (`FilterItemStack.java:68-77`).
///
/// [wire] decodes the ghost slots of a list filter and brings the package components into their
/// logical form: without it (the logistics module is not loaded) such a filter matches nothing as
/// a whitelist and everything as a blacklist, like an unreadable component. An *empty* filter
/// matches everything, exactly like `FilterItemStack`; the crafting loop handles an empty grid slot
/// before it ever gets here, the way Java does.
bool blueprintFilterTest(TStack filter, TStack candidate, {StackWire? wire}) => FilterItemStack.of(
  _filterValue(filter, wire),
  wire: wire,
).test(_filterValue(candidate, wire), matchNbt: false);

/// The [LStack] the filter model compares, with the four package components in the logical form
/// [LStack] uses (`StackIo.wireToLogical`): the grid keeps the raw host bytes
/// ([blueprintStackValue]), because they are what the ghost slots write back, but the address a
/// package filter matches by is a string ([PackageItem.getAddress]).
LStack _filterValue(TStack t, StackWire? wire) {
  final value = blueprintStackValue(t);
  if (wire == null || value.comps.isEmpty) return value;
  var out = value;
  for (final name in PackageComponents.logical) {
    final bytes = out.compBytes(name);
    if (bytes == null) continue;
    final logical = wire.wireToLogical(name, bytes);
    if (logical != null) out = out.withComp(name, logical);
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Shift-click (`GhostItemMenu.quickMoveStack`, `GhostItemMenu.java:103-124`)
// ---------------------------------------------------------------------------------------

/// `GhostItemMenu.quickMoveStack` of the blueprint's 11 ghost slots (`allowRepeats() == true`,
/// `BlueprintMenu.java:49-51`): a shift-click on a mirror slot (`0..35`) copies one item of
/// [source] into the first empty ghost slot, a shift-click on a ghost slot removes one item from
/// it. Returns the ghost slot that changed, `-1` when the click leaves the grid alone.
///
/// The decision is [ghostQuickMove]; the copy keeps the whole stack with a count of one
/// (`stackToInsert.copy()` then `setCount(1)`), components included, and the extraction of a slot
/// that held more than one item only lowers its count.
int applyBlueprintQuickMove(List<TStack> items, {required int menuSlot, required TStack source}) {
  final move = ghostQuickMove(
    menuSlot: menuSlot,
    source: blueprintStackValue(source),
    ghostSlots: GhostMenu.blueprint.ghostSlots,
    ghostEmpty: (i) => items[i].isEmpty,
  );
  if (move.isNone) return -1;
  final current = items[move.ghost];
  items[move.ghost] = move.take
      ? (current.count > 1 ? current.copyWithCount(current.count - 1) : TStack.empty)
      : source.copyWithCount(1);
  return move.ghost;
}