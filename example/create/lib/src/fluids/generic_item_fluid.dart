// `GenericItemFilling`, `GenericItemEmptying`, `FillingBySpout` and the potion bottle conversions
// (pure): what fluid goes into and comes out of items. Items are [ItemSpec]s (key and count); the
// host exposes bucket contents and registered container items, which [ItemFluidRules] describes.
// The potion contents of a bottle item cannot be read or written through the host, so a bottle's
// potion is carried by the fluid data and the bottle item is chosen by its type
// (`minecraft:potion`, `splash_potion`, `lingering_potion`).
import 'fluid_helper.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'potion_data.dart';

/// A stack of items as the fluid code sees it: the registry key and the count.
final class ItemSpec {
  final String key;
  final int count;

  const ItemSpec(this.key, [this.count = 1]);

  static const ItemSpec empty = ItemSpec('minecraft:air', 0);

  bool get isEmpty => key == 'minecraft:air' || count <= 0;
  bool get isNotEmpty => !isEmpty;

  ItemSpec withCount(int c) => c <= 0 ? empty : ItemSpec(key, c);

  /// `ItemStack.shrink(n)`.
  ItemSpec shrink(int n) => withCount(count - n);

  @override
  bool operator ==(Object other) => other is ItemSpec && (isEmpty && other.isEmpty || other.key == key && other.count == count);

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(key, count);

  @override
  String toString() => isEmpty ? 'ItemSpec.empty' : 'ItemSpec($key x$count)';
}

/// A container item registered through the host (`FluidHandlers.registerContainerItem`).
final class ContainerItemRule {
  final int capacity;
  final List<String> allowedFluids;

  const ContainerItemRule(this.capacity, [this.allowedFluids = const []]);

  bool allows(String fluid) => allowedFluids.isEmpty || allowedFluids.contains(FluidKeys.still(fluid));
}

/// What the module knows about the fluid contents of items.
class ItemFluidRules {
  /// The fluid a full bucket holds (`FluidRegistries.fromBucket`), `null` for other items.
  FStack? Function(String itemKey) fluidFromBucket;

  /// The bucket of a fluid (`FluidRegistries.bucketFor`), `null` if it has none.
  String? Function(String fluidKey) bucketFor;

  /// Container items by key (the capacity of an empty one).
  final Map<String, ContainerItemRule> containers = {};

  ItemFluidRules({FStack? Function(String itemKey)? fluidFromBucket, String? Function(String fluidKey)? bucketFor})
    : fluidFromBucket = fluidFromBucket ?? _defaultBucketFluid,
      bucketFor = bucketFor ?? _defaultBucketFor;

  static FStack? _defaultBucketFluid(String key) => switch (key) {
    'minecraft:water_bucket' => const FStack(FluidKeys.water, 1000),
    'minecraft:lava_bucket' => const FStack(FluidKeys.lava, 1000),
    'minecraft:milk_bucket' => const FStack(FluidKeys.milk, 1000),
    'create:honey_bucket' => const FStack(FluidKeys.honey, 1000),
    'create:chocolate_bucket' => const FStack(FluidKeys.chocolate, 1000),
    _ => null,
  };

  static String? _defaultBucketFor(String fluid) => switch (FluidKeys.still(fluid)) {
    FluidKeys.water => 'minecraft:water_bucket',
    FluidKeys.lava => 'minecraft:lava_bucket',
    FluidKeys.milk => 'minecraft:milk_bucket',
    FluidKeys.honey => 'create:honey_bucket',
    FluidKeys.chocolate => 'create:chocolate_bucket',
    _ => null,
  };

  /// `PotionFluidHandler.isPotionItem`: a bottle of any kind.
  bool isPotionItem(String itemKey) =>
      itemKey == 'minecraft:potion' || itemKey == 'minecraft:splash_potion' || itemKey == 'minecraft:lingering_potion';
}

/// `EmptyingRecipe` as the spout and the drain see it.
final class EmptyingResult {
  final FStack fluid;
  final ItemSpec remainder;

  const EmptyingResult(this.fluid, this.remainder);
}

/// `FillingRecipe` as the spout sees it.
final class FillingResult {
  final int requiredAmount;
  final ItemSpec result;

  const FillingResult(this.requiredAmount, this.result);
}

/// The recipes of the processing module (`AllRecipeTypes.FILLING` / `EMPTYING`), found through a
/// service; the default has none.
abstract interface class FluidItemRecipes {
  /// The emptying recipe for one [item], `null` if there is none.
  EmptyingResult? findEmptying(ItemSpec item);

  /// A filling recipe for one [item] that accepts [available], `null` if there is none.
  FillingResult? findFilling(ItemSpec item, FStack available);

  /// Whether some filling recipe takes [item] (with any fluid).
  bool canBeFilled(ItemSpec item);
}

final class NoFluidItemRecipes implements FluidItemRecipes {
  const NoFluidItemRecipes();

  @override
  EmptyingResult? findEmptying(ItemSpec item) => null;

  @override
  FillingResult? findFilling(ItemSpec item, FStack available) => null;

  @override
  bool canBeFilled(ItemSpec item) => false;
}

/// The fluid handler of one item (`ItemFluidHandler`): a bucket, a bottle or a container item.
class ItemFluidHandler implements FluidItemContainer {
  final ItemFluidRules rules;
  String _item;
  FStack _fluid;
  final int _capacity;

  ItemFluidHandler._(this.rules, this._item, this._fluid, this._capacity);

  /// `ItemFluidHandler.of(stack)`: the handler of a single item, `null` if the item holds no fluid.
  static ItemFluidHandler? of(ItemFluidRules rules, ItemSpec item, {FStack contents = FStack.empty}) {
    final key = item.key;
    if (key == 'minecraft:bucket') return ItemFluidHandler._(rules, key, FStack.empty, 1000);
    final bucketFluid = rules.fluidFromBucket(key);
    if (bucketFluid != null) return ItemFluidHandler._(rules, key, bucketFluid, 1000);
    final container = rules.containers[key];
    if (container != null) return ItemFluidHandler._(rules, key, contents, container.capacity);
    if (key == 'minecraft:potion') {
      // A water bottle: 250 mB of water.
      return ItemFluidHandler._(rules, key, const FStack(FluidKeys.water, 250), 250);
    }
    return null;
  }

  @override
  String get containerItem => _item;

  /// The fluid held.
  FStack get contents => _fluid;

  @override
  int get tanks => 1;

  @override
  FStack fluidInTank(int tank) => _fluid;

  @override
  int tankCapacity(int tank) => _capacity;

  bool get _isBucket => _item == 'minecraft:bucket' || rules.fluidFromBucket(_item) != null;

  @override
  bool isFluidValid(int tank, FStack stack) {
    if (_isBucket) return rules.bucketFor(stack.fluid) != null;
    final container = rules.containers[_item];
    if (container != null) return container.allows(stack.fluid);
    return false;
  }

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !isFluidValid(0, resource)) return 0;
    if (_isBucket) {
      // buckets take 1000 or nothing
      if (_fluid.isNotEmpty || resource.amount < 1000) return 0;
      final bucket = rules.bucketFor(resource.fluid);
      if (bucket == null) return 0;
      if (!simulate) {
        _item = bucket;
        _fluid = resource.withAmount(1000);
      }
      return 1000;
    }
    final room = _capacity - _fluid.amount;
    if (_fluid.isNotEmpty && !_fluid.isSameFluid(resource)) return 0;
    final filled = resource.amount < room ? resource.amount : room;
    if (filled <= 0) return 0;
    if (!simulate) _fluid = _fluid.isEmpty ? resource.withAmount(filled) : _fluid.grow(filled);
    return filled;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !resource.isSameFluid(_fluid)) return FStack.empty;
    return drain(resource.amount, simulate: simulate);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) {
    if (_fluid.isEmpty || maxDrain <= 0) return FStack.empty;
    if (_isBucket) {
      // all or nothing
      if (maxDrain < 1000) return FStack.empty;
      final out = _fluid;
      if (!simulate) {
        _item = 'minecraft:bucket';
        _fluid = FStack.empty;
      }
      return out.withAmount(1000);
    }
    if (_item == 'minecraft:potion') {
      if (maxDrain < 250) return FStack.empty;
      final out = _fluid;
      if (!simulate) {
        _item = 'minecraft:glass_bottle';
        _fluid = FStack.empty;
      }
      return out;
    }
    final drained = maxDrain < _fluid.amount ? maxDrain : _fluid.amount;
    final out = _fluid.withAmount(drained);
    if (!simulate) _fluid = _fluid.shrink(drained);
    return out;
  }
}

/// `GenericItemEmptying`.
class GenericItemEmptying {
  final ItemFluidRules rules;
  final FluidItemRecipes recipes;

  GenericItemEmptying(this.rules, [this.recipes = const NoFluidItemRecipes()]);

  /// `canItemBeEmptied(world, stack)`.
  bool canItemBeEmptied(ItemSpec stack) {
    if (rules.isPotionItem(stack.key)) return true;
    if (recipes.findEmptying(stack.withCount(1)) != null) return true;
    final handler = ItemFluidHandler.of(rules, stack.withCount(1));
    if (handler == null) return false;
    return handler.fluidInTank(0).amount > 0;
  }

  /// `emptyItem(level, stack, simulate)`: the fluid that comes out and the item that is left
  /// (empty for none) of one item of [stack]. The new stack is returned as `$3`.
  (FStack fluid, ItemSpec remainder, ItemSpec stack) emptyItem(ItemSpec stack, {required bool simulate}) {
    if (rules.isPotionItem(stack.key)) {
      final fluid = potionItemFluid(stack.key);
      return (fluid, const ItemSpec('minecraft:glass_bottle'), simulate ? stack : stack.shrink(1));
    }

    final recipe = recipes.findEmptying(stack.withCount(1));
    if (recipe != null) return (recipe.fluid, recipe.remainder, simulate ? stack : stack.shrink(1));

    final handler = ItemFluidHandler.of(rules, stack.withCount(1));
    if (handler == null) return (FStack.empty, ItemSpec.empty, stack);
    final fluid = handler.drain(1000, simulate: simulate);
    return (fluid, ItemSpec(handler.containerItem), simulate ? stack : stack.shrink(1));
  }

  /// `PotionFluidHandler.getFluidFromPotionItem`: a bottle holds 250 mB of its fluid.
  static FStack potionItemFluid(String itemKey) {
    final bottle = BottleType.fromItem(itemKey);
    final data = PotionFluidData('minecraft:water', bottle: bottle);
    return PotionFluids.fluidFromPotion(data, 250);
  }
}

/// `GenericItemFilling`.
class GenericItemFilling {
  final ItemFluidRules rules;

  GenericItemFilling(this.rules);

  /// `canItemBeFilled(world, stack)`.
  bool canItemBeFilled(ItemSpec stack) {
    if (stack.key == 'minecraft:glass_bottle') return true;
    if (stack.key == 'minecraft:milk_bucket') return false;
    final handler = ItemFluidHandler.of(rules, stack.withCount(1));
    if (handler == null) return false;
    return handler.fluidInTank(0).amount < handler.tankCapacity(0);
  }

  bool _canFillGlassBottleInternally(FStack available) {
    final fluid = available.fluid;
    return FluidHelper.isWater(fluid) || FluidKeys.still(fluid) == FluidKeys.potion || FluidKeys.still(fluid) == FluidKeys.tea;
  }

  /// `getRequiredAmountForItem(world, stack, availableFluid)`: -1 when the item cannot take the fluid.
  int getRequiredAmountForItem(ItemSpec stack, FStack availableFluid) {
    if (stack.key == 'minecraft:glass_bottle' && _canFillGlassBottleInternally(availableFluid)) {
      return PotionFluids.requiredAmountForFilledBottle();
    }
    if (stack.key == 'minecraft:bucket') {
      final bucket = rules.bucketFor(availableFluid.fluid);
      return bucket == null ? -1 : 1000;
    }
    final handler = ItemFluidHandler.of(rules, stack.withCount(1));
    if (handler == null) return -1;
    final filled = handler.fill(availableFluid, simulate: true);
    return filled == 0 ? -1 : filled;
  }

  /// `fillItem(level, requiredAmount, stack, availableFluid)`: the filled item and what is left of
  /// the stack and of the fluid.
  (ItemSpec result, ItemSpec stack, FStack fluid) fillItem(int requiredAmount, ItemSpec stack, FStack availableFluid) {
    final toFill = availableFluid.withAmount(requiredAmount);
    final leftFluid = availableFluid.shrink(requiredAmount);

    if (stack.key == 'minecraft:glass_bottle' && _canFillGlassBottleInternally(toFill)) {
      final ItemSpec bottle;
      if (FluidHelper.isWater(toFill.fluid)) {
        bottle = const ItemSpec('minecraft:potion');
      } else if (FluidKeys.still(toFill.fluid) == FluidKeys.tea) {
        bottle = const ItemSpec('create:builders_tea');
      } else {
        bottle = ItemSpec(PotionFluids.bottleItemFor(toFill));
      }
      return (bottle, stack.shrink(1), leftFluid);
    }

    final handler = ItemFluidHandler.of(rules, stack.withCount(1));
    if (handler == null) return (ItemSpec.empty, stack, availableFluid);
    handler.fill(toFill, simulate: false);
    return (ItemSpec(handler.containerItem), stack.shrink(1), leftFluid);
  }
}

/// `FillingBySpout`.
class FillingBySpout {
  final GenericItemFilling generic;
  final FluidItemRecipes recipes;

  FillingBySpout(this.generic, [this.recipes = const NoFluidItemRecipes()]);

  /// `canItemBeFilled(world, stack)`.
  bool canItemBeFilled(ItemSpec stack) => recipes.canBeFilled(stack.withCount(1)) || generic.canItemBeFilled(stack);

  /// `getRequiredAmountForItem(world, stack, availableFluid)`.
  int getRequiredAmountForItem(ItemSpec stack, FStack availableFluid) {
    final recipe = recipes.findFilling(stack.withCount(1), availableFluid);
    if (recipe != null) return recipe.requiredAmount;
    return generic.getRequiredAmountForItem(stack, availableFluid);
  }

  /// `fillItem(level, requiredAmount, stack, availableFluid)`.
  (ItemSpec result, ItemSpec stack, FStack fluid) fillItem(int requiredAmount, ItemSpec stack, FStack availableFluid) {
    final recipe = recipes.findFilling(stack.withCount(1), availableFluid.withAmount(requiredAmount));
    if (recipe != null) return (recipe.result, stack.shrink(1), availableFluid.shrink(requiredAmount));
    return generic.fillItem(requiredAmount, stack, availableFluid);
  }
}
