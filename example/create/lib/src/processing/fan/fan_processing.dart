// The fan processing types (`AllFanProcessingTypes`, `FanProcessingTypeRegistry`, `FanProcessing`):
// what an air current does to the items and entities it catches. The four types of this fork are
// splashing, haunting, smoking and blasting; splashing and haunting use Create recipes, smoking and
// blasting the vanilla cooking recipes cached in [FanCookingCache].
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/heat.dart';
import '../recipe/recipe_applier.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../transport/transported_stack.dart';
import 'fan_cooking.dart';

/// `FanProcessingType`.
abstract class FanProcessingType {
  /// `create:<path>`.
  String get key;

  /// `getPriority`: higher runs first.
  int get priority;

  /// `isValidAt`: the block or fluid at [pos] turns the air current into this type.
  bool isValidAt(World world, BlockPos pos);

  /// `canProcess`.
  bool canProcess(PStack stack);

  /// `process`: the results, `null` when no recipe applies.
  List<PStack>? process(PStack stack);

  /// `affectEntity`.
  void affectEntity(Entity entity);
}

// -- Helpers ---------------------------------------------------------------------------------

bool _fluidTag(World world, BlockPos pos, String tag) {
  final fluid = world.getFluidState(pos: pos);
  return fluid != null && Tags.fluid(fluid.fluid, tag);
}

String? _property(World world, BlockPos pos, String name) {
  final state = world.getBlockState(pos: pos);
  for (final (k, v) in state.properties) {
    if (k == name) return v;
  }
  return null;
}

String _blockKey(World world, BlockPos pos) =>
    world.getBlockState(pos: pos).blockName;

bool _campfireUnlit(World world, BlockPos pos) =>
    Tags.block(_blockKey(world, pos), 'minecraft:campfires') &&
    _property(world, pos, 'lit') == 'false';

HeatLevel _heatLevel(World world, BlockPos pos) =>
    HeatLevel.byName(_property(world, pos, 'blaze') ?? '') ?? HeatLevel.none;

/// `DataComponents.DAMAGE_RESISTANT`.
bool _damageResistant(PStack stack) =>
    stack.comps.any((c) => c.$1 == 'damage-resistant');

RecipeMatch? _recipe(CreateRecipeType type, PStack stack) {
  if (!ProcessingRuntime.isLoaded) return null;
  return ProcessingRuntime.instance.recipes.findForInput(type, stack);
}

/// `Entity.fireImmune()`: the host has no flag, so the nether mobs that never burn.
const Set<String> _fireImmune = {
  'blaze',
  'magma-cube',
  'ghast',
  'strider',
  'wither-skeleton',
  'zombified-piglin',
  'wither',
  'ender-dragon',
  'zoglin',
  'sulfur-cube',
};

bool _fireImmuneEntity(Entity entity) {
  // A plugin entity (a Create contraption, seat, package) has no vanilla type: not immune.
  final type = entity.getType();
  return type != null && _fireImmune.contains(type.wireName);
}

// -- The four types --------------------------------------------------------------------------

/// `AllFanProcessingTypes.SplashingType`: water (or a catalyst block) washes items.
final class SplashingType implements FanProcessingType {
  @override
  String get key => 'create:splashing';

  @override
  int get priority => 400;

  @override
  bool isValidAt(World world, BlockPos pos) =>
      _fluidTag(world, pos, 'create:fan_processing_catalysts/splashing') ||
      Tags.block(
        _blockKey(world, pos),
        'create:fan_processing_catalysts/splashing',
      );

  @override
  bool canProcess(PStack stack) =>
      _recipe(CreateRecipeType.splashing, stack) != null;

  @override
  List<PStack>? process(PStack stack) {
    final match = _recipe(CreateRecipeType.splashing, stack);
    if (match == null) return null;
    return applyRecipeOn(
      stack,
      match.recipe,
      ProcessingRuntime.instance.random,
      returnProcessingRemainder: true,
    );
  }

  @override
  void affectEntity(Entity entity) {
    final type = entity.getType();
    if (type == EntityType.enderman ||
        type == EntityType.snowGolem ||
        type == EntityType.blaze) {
      final living = entity.asLiving();
      if (living != null) {
        unawaited(
          living.damageByKey(amount: 2, damageTypeKey: 'minecraft:drown'),
        );
      }
    }
    if (entity.isOnFire()) entity.setFireTicks(ticks: 0);
  }
}

/// `AllFanProcessingTypes.HauntingType`: soul fire and soul campfires haunt items.
final class HauntingType implements FanProcessingType {
  @override
  String get key => 'create:haunting';

  @override
  int get priority => 300;

  @override
  bool isValidAt(World world, BlockPos pos) {
    if (_fluidTag(world, pos, 'create:fan_processing_catalysts/haunting')) {
      return true;
    }
    if (!Tags.block(
      _blockKey(world, pos),
      'create:fan_processing_catalysts/haunting',
    )) {
      return false;
    }
    if (_campfireUnlit(world, pos)) return false;
    final flame = _property(world, pos, 'flame_type');
    return flame == null || flame == 'soul';
  }

  @override
  bool canProcess(PStack stack) =>
      _recipe(CreateRecipeType.haunting, stack) != null;

  @override
  List<PStack>? process(PStack stack) {
    final match = _recipe(CreateRecipeType.haunting, stack);
    if (match == null) return null;
    return applyRecipeOn(
      stack,
      match.recipe,
      ProcessingRuntime.instance.random,
      returnProcessingRemainder: true,
    );
  }

  @override
  void affectEntity(Entity entity) {
    // The host exposes status effects on players only and has no mob conversion, so the
    // blindness / slowness and the horse -> skeleton horse haunting are not applied.
  }
}

/// `AllFanProcessingTypes.SmokingType`: a smouldering blaze burner, a campfire or a fire smokes.
final class SmokingType implements FanProcessingType {
  @override
  String get key => 'create:smoking';

  @override
  int get priority => 200;

  @override
  bool isValidAt(World world, BlockPos pos) {
    if (_fluidTag(world, pos, 'create:fan_processing_catalysts/smoking')) {
      return true;
    }
    if (!Tags.block(
      _blockKey(world, pos),
      'create:fan_processing_catalysts/smoking',
    )) {
      return false;
    }
    if (_campfireUnlit(world, pos)) return false;
    final flame = _property(world, pos, 'flame_type');
    if (flame != null && flame != 'regular') return false;
    final heat = _property(world, pos, 'blaze');
    return heat == null || heat == HeatLevel.smouldering.name;
  }

  @override
  bool canProcess(PStack stack) {
    final cache = FanCookingCache.current;
    if (cache == null || !ProcessingRuntime.isLoaded) return false;
    return FanCookingCache.firstOf(
          cache.smoking,
          stack,
          ProcessingRuntime.instance.recipes.tags,
        ) !=
        null;
  }

  @override
  List<PStack>? process(PStack stack) {
    final cache = FanCookingCache.current;
    if (cache == null || !ProcessingRuntime.isLoaded) return null;
    final entry = FanCookingCache.firstOf(
      cache.smoking,
      stack,
      ProcessingRuntime.instance.recipes.tags,
    );
    if (entry == null) return null;
    return applyResultOn(stack, entry.output);
  }

  @override
  void affectEntity(Entity entity) {
    if (_fireImmuneEntity(entity)) return;
    entity.setFireTicks(ticks: 40);
    final living = entity.asLiving();
    if (living != null) {
      unawaited(
        living.damageByKey(amount: 2, damageTypeKey: 'create:fan_fire'),
      );
    }
  }
}

/// `AllFanProcessingTypes.BlastingType`: lava (or a hot blaze burner) blasts items.
final class BlastingType implements FanProcessingType {
  @override
  String get key => 'create:blasting';

  @override
  int get priority => 100;

  @override
  bool isValidAt(World world, BlockPos pos) {
    if (_fluidTag(world, pos, 'create:fan_processing_catalysts/blasting')) {
      return true;
    }
    if (!Tags.block(
      _blockKey(world, pos),
      'create:fan_processing_catalysts/blasting',
    )) {
      return false;
    }
    final heat = _property(world, pos, 'blaze');
    return heat == null || (_heatLevel(world, pos).isAtLeast(HeatLevel.fading));
  }

  @override
  bool canProcess(PStack stack) {
    final cache = FanCookingCache.current;
    if (cache == null || !ProcessingRuntime.isLoaded) {
      return !_damageResistant(stack);
    }
    final tags = ProcessingRuntime.instance.recipes.tags;
    if (FanCookingCache.firstOf(cache.smelting, stack, tags) != null) {
      return true;
    }
    if (FanCookingCache.firstOf(cache.blasting, stack, tags) != null) {
      return true;
    }
    return !_damageResistant(stack);
  }

  @override
  List<PStack>? process(PStack stack) {
    final cache = FanCookingCache.current;
    if (cache == null || !ProcessingRuntime.isLoaded) return null;
    final tags = ProcessingRuntime.instance.recipes.tags;
    final smelting = FanCookingCache.firstOf(cache.smelting, stack, tags);
    final blasting =
        smelting ?? FanCookingCache.firstOf(cache.blasting, stack, tags);
    if (blasting == null) return null;

    final smoking = FanCookingCache.firstOf(cache.smoking, stack, tags);
    if (smoking != null && smoking.output.key == blasting.output.key) {
      return const [];
    }
    return applyResultOn(stack, blasting.output);
  }

  @override
  void affectEntity(Entity entity) {
    if (_fireImmuneEntity(entity)) return;
    entity.setFireTicks(ticks: 200);
    final living = entity.asLiving();
    if (living != null) {
      unawaited(
        living.damageByKey(amount: 4, damageTypeKey: 'create:fan_lava'),
      );
    }
  }
}

// -- Registry --------------------------------------------------------------------------------

/// `FanProcessingTypeRegistry.SORTED_TYPES`: the types by descending priority.
abstract final class FanProcessingTypes {
  static final List<FanProcessingType> all = [
    SplashingType(),
    HauntingType(),
    SmokingType(),
    BlastingType(),
  ];

  /// `FanProcessingType.parse` / `AllFanProcessingTypes.parseLegacy`.
  static FanProcessingType? byKey(String key) {
    final path = key.contains(':') ? key.substring(key.indexOf(':') + 1) : key;
    for (final t in all) {
      if (t.key == key ||
          t.key == 'create:$path' ||
          t.key.split(':').last == path.toLowerCase()) {
        return t;
      }
    }
    return null;
  }

  /// `FanProcessingType.getAt`: the first valid type at [pos].
  static FanProcessingType? at(World world, BlockPos pos) {
    for (final t in all) {
      if (t.isValidAt(world, pos)) return t;
    }
    return null;
  }
}

/// `FanProcessing`: the item entity and transported item processing.
abstract final class FanProcessing {
  static const String _namespace = 'create';
  static const String _key = 'fan_processing';

  static int get _processingTime => ProcessingRuntime.isLoaded
      ? (ProcessingRuntime
                .instance
                .configs
                ?.server
                .kinetics
                .fanProcessingTime
                .value ??
            150)
      : 150;

  static NbtCompound _read(ItemEntity entity) {
    final tree = entity.asEntity().getCustomData(
      namespace: _namespace,
      key: _key,
    );
    return tree == null ? NbtCompound() : NbtCompound.fromTree(tree);
  }

  static void _write(ItemEntity entity, NbtCompound data) => entity
      .asEntity()
      .setCustomData(namespace: _namespace, key: _key, value: data.toTree());

  /// `FanProcessing.canProcess`.
  static Future<bool> canProcess(
    ItemEntity entity,
    FanProcessingType type,
  ) async {
    if (entity.asEntity().hasCustomData(namespace: _namespace, key: _key)) {
      final data = _read(entity);
      final stored = data.getString('Type');
      if (FanProcessingTypes.byKey(stored ?? '') != type) {
        return type.canProcess(await _stack(entity));
      }
      final time = data.getInt('Time') ?? 0;
      if (time >= 0) return true;
      if (time == -1) return false;
    }
    return type.canProcess(await _stack(entity));
  }

  /// `FanProcessing.applyProcessing(ItemEntity, ...)`.
  static Future<bool> applyProcessing(
    ItemEntity entity,
    FanProcessingType type,
  ) async {
    if (await _decrement(entity, type) != 0) return false;
    final stack = await _stack(entity);
    final stacks = type.process(stack);
    if (stacks == null) return false;
    if (stacks.isEmpty) {
      entity.discard();
      return false;
    }

    final world = entity.asEntity().getWorld();
    final first = await _item(stacks.first);
    if (first == null) return false;
    await entity.setStack(stack: first);
    final velocity = entity.asEntity().velocity;
    for (final additional in stacks.skip(1)) {
      final item = await _item(additional);
      if (item == null) continue;
      await world.dropItem(
        entity.asEntity().getPosition(),
        item,
        velocity: velocity,
      );
    }
    return true;
  }

  /// `FanProcessing.applyProcessing(TransportedItemStack, ...)`.
  static TransportedResult applyProcessingTransported(
    TransportedItemStack transported,
    FanProcessingType type,
  ) {
    if (transported.processedBy != type.key) {
      transported.processedBy = type.key;
      final modifier = ((transported.stack.count - 1) ~/ 16) + 1;
      transported.processingTime = (_processingTime * modifier).toInt() + 1;
      if (!type.canProcess(transported.stack)) transported.processingTime = -1;
      return TransportedResult.doNothing();
    }
    if (transported.processingTime == -1) return TransportedResult.doNothing();
    if (transported.processingTime-- > 0) return TransportedResult.doNothing();

    final stacks = type.process(transported.stack);
    if (stacks == null) return TransportedResult.doNothing();

    final outputs = <TransportedItemStack>[];
    for (final additional in stacks) {
      final copy = transported.getSimilar()..stack = additional;
      outputs.add(copy);
    }
    return TransportedResult.convertToAll(outputs);
  }

  /// `decrementProcessingTime`.
  static Future<int> _decrement(
    ItemEntity entity,
    FanProcessingType type,
  ) async {
    final data = _read(entity);
    final stored = data.getString('Type');
    if (stored == null || FanProcessingTypes.byKey(stored) != type) {
      data.putString('Type', type.key);
      final count = (await _stack(entity)).count;
      final modifier = ((count - 1) ~/ 16) + 1;
      data.putInt('Time', (_processingTime * modifier).toInt() + 1);
    }
    final value = (data.getInt('Time') ?? 0) - 1;
    data.putInt('Time', value);
    _write(entity, data);
    return value;
  }

  static Future<PStack> _stack(ItemEntity entity) =>
      HostStacks.read(entity.getStack());

  static Future<ItemStack?> _item(PStack stack) => HostStacks.write(stack);
}
