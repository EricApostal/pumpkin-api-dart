// Item and fluid ingredients (pure): the forms the recipe JSON of Create uses
// (`{"item"}`, `{"tag"}`, NeoForge's `block_tag`, `components`, `difference`, ...), matched
// against [PStack] / [PFluid] with a [TagLookup] for the tags.
import '../common/stack.dart';

/// Tag membership, answered by the host (`Tags.item`, ...) or by a map in tests.
abstract interface class TagLookup {
  /// Whether the item [itemKey] is in the item tag [tag] (`c:ingots/brass`, with or without `#`).
  bool itemHasTag(String itemKey, String tag);

  /// Whether the block [blockKey] is in the block tag [tag].
  bool blockHasTag(String blockKey, String tag);

  /// Whether the fluid [fluidKey] is in the fluid tag [tag].
  bool fluidHasTag(String fluidKey, String tag);
}

/// A [TagLookup] over maps (`{'c:ingots/brass': {'create:brass_ingot'}}`), for tests and tools.
final class MapTagLookup implements TagLookup {
  final Map<String, Set<String>> items;
  final Map<String, Set<String>> blocks;
  final Map<String, Set<String>> fluids;

  const MapTagLookup({this.items = const {}, this.blocks = const {}, this.fluids = const {}});

  static String _norm(String tag) => tag.startsWith('#') ? tag.substring(1) : tag;

  @override
  bool itemHasTag(String itemKey, String tag) => items[_norm(tag)]?.contains(itemKey) ?? false;

  @override
  bool blockHasTag(String blockKey, String tag) => blocks[_norm(tag)]?.contains(blockKey) ?? false;

  @override
  bool fluidHasTag(String fluidKey, String tag) => fluids[_norm(tag)]?.contains(fluidKey) ?? false;
}

/// `net.minecraft.world.item.crafting.Ingredient` (with NeoForge's custom ingredient types).
sealed class Ingredient {
  const Ingredient();

  /// `Ingredient.test(stack)`.
  bool test(PStack stack, TagLookup tags);

  /// The item keys and tags this ingredient is made of, for display and the network form.
  /// Compound ingredients flatten.
  List<IngredientEntry> get entries;

  /// A single item.
  const factory Ingredient.item(String key) = ItemIngredient;

  /// An item tag.
  const factory Ingredient.tag(String tag) = TagIngredient;

  /// Any of [children].
  const factory Ingredient.anyOf(List<Ingredient> children) = AnyIngredient;
}

/// One leaf of an ingredient: an item or a tag.
final class IngredientEntry {
  final String? item;
  final String? tag;

  const IngredientEntry.item(String this.item) : tag = null;
  const IngredientEntry.tag(String this.tag) : item = null;
}

final class ItemIngredient extends Ingredient {
  final String key;

  const ItemIngredient(this.key);

  @override
  bool test(PStack stack, TagLookup tags) => stack.isNotEmpty && stack.key == key;

  @override
  List<IngredientEntry> get entries => [IngredientEntry.item(key)];

  @override
  String toString() => 'item:$key';
}

final class TagIngredient extends Ingredient {
  final String tag;

  const TagIngredient(this.tag);

  @override
  bool test(PStack stack, TagLookup tags) => stack.isNotEmpty && tags.itemHasTag(stack.key, tag);

  @override
  List<IngredientEntry> get entries => [IngredientEntry.tag(tag)];

  @override
  String toString() => 'tag:$tag';
}

/// `neoforge:block_tag`: items whose block is in a block tag.
final class BlockTagIngredient extends Ingredient {
  final String tag;

  const BlockTagIngredient(this.tag);

  @override
  bool test(PStack stack, TagLookup tags) => stack.isNotEmpty && tags.blockHasTag(stack.key, tag);

  @override
  List<IngredientEntry> get entries => [IngredientEntry.tag(tag)];

  @override
  String toString() => 'block_tag:$tag';
}

/// An array of ingredients / `neoforge:compound`: matches if any child does.
final class AnyIngredient extends Ingredient {
  final List<Ingredient> children;

  const AnyIngredient(this.children);

  @override
  bool test(PStack stack, TagLookup tags) => children.any((c) => c.test(stack, tags));

  @override
  List<IngredientEntry> get entries => [for (final c in children) ...c.entries];

  @override
  String toString() => 'any$children';
}

/// `neoforge:intersection`.
final class IntersectionIngredient extends Ingredient {
  final List<Ingredient> children;

  const IntersectionIngredient(this.children);

  @override
  bool test(PStack stack, TagLookup tags) => children.every((c) => c.test(stack, tags));

  @override
  List<IngredientEntry> get entries => children.isEmpty ? const [] : children.first.entries;
}

/// `neoforge:difference`: [base] but not [subtracted].
final class DifferenceIngredient extends Ingredient {
  final Ingredient base;
  final Ingredient subtracted;

  const DifferenceIngredient(this.base, this.subtracted);

  @override
  bool test(PStack stack, TagLookup tags) => base.test(stack, tags) && !subtracted.test(stack, tags);

  @override
  List<IngredientEntry> get entries => base.entries;
}

/// `neoforge:components` / `neoforge:nbt` item ingredients: the [items] that carry the
/// required components. The plugin only sees the raw component bytes of a stack, so only the
/// item is compared (documented deviation); the components are kept for the network form.
final class ComponentIngredient extends Ingredient {
  final List<String> items;
  final Map<String, Object?> components;

  const ComponentIngredient(this.items, this.components);

  @override
  bool test(PStack stack, TagLookup tags) => stack.isNotEmpty && items.contains(stack.key);

  @override
  List<IngredientEntry> get entries => [for (final i in items) IngredientEntry.item(i)];
}

/// `SizedFluidIngredient`: a fluid, a fluid tag or a set of fluids with components, and an
/// amount in millibuckets.
final class FluidIngredient {
  /// The fluid keys (`minecraft:water`); empty for a tag ingredient.
  final List<String> fluids;

  /// The fluid tag (`c:milk`), or `null`.
  final String? tag;
  final int amount;

  /// Required components (`neoforge:components`), JSON form.
  final Map<String, Object?> components;

  const FluidIngredient({this.fluids = const [], this.tag, required this.amount, this.components = const {}});

  /// `FluidIngredient.test(stack)` (the amount is not compared).
  bool testFluid(PFluid fluid, TagLookup tags) {
    if (fluid.isEmpty) return false;
    if (tag != null) return tags.fluidHasTag(fluid.key, tag!);
    return fluids.contains(fluid.key);
  }

  /// `SizedFluidIngredient.test(stack)`: the fluid matches and there is enough of it.
  bool test(PFluid fluid, TagLookup tags) => testFluid(fluid, tags) && fluid.amount >= amount;

  /// `getFluids()`: the matching stacks for display, using [tagMembers] to expand a tag.
  List<PFluid> matching(Iterable<String> Function(String tag)? tagMembers) {
    if (tag != null) {
      final members = tagMembers?.call(tag!) ?? const <String>[];
      return [for (final k in members) PFluid(k, amount)];
    }
    return [for (final f in fluids) PFluid(f, amount)];
  }

  @override
  String toString() => 'fluid(${tag != null ? '#$tag' : fluids.join('|')} x$amount)';
}
