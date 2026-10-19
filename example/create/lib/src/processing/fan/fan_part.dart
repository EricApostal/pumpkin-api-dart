// The encased fan part of the processing module: the fan and its nozzle, the air current and the
// four fan processing types with their recipes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../support/kinetics_bridge.dart';
import '../common/stack.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../recipe/ingredient.dart' as ing;
import 'encased_fan_block.dart';
import 'fan_cooking.dart';
import 'nozzle_block.dart';

/// The encased fan, the nozzle and the air currents.
final class FanPart extends ProcessingPart {
  @override
  String get name => 'fan';

  @override
  void register(CreateRegistry registry) {
    final fan = encasedFanSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:encased_fan',
        validBlocks: [fan.block.key],
        create: EncasedFanBlockEntity.new,
      ),
    );
    registry.block(fan.block);

    final nozzle = nozzleBlock();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:nozzle',
        validBlocks: [nozzle.key],
        create: NozzleBlockEntity.new,
      ),
    );
    registry.block(nozzle);

    FanCookingCache.current ??= FanCookingCache();
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:encased_fan',
      const FacingBlockDef(shaftAtFront: false),
    );
    ctx.listen(Events.datapackReload, (server, e) => _loadCooking(server));
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) =>
      _loadCooking(runtime.server);

  @override
  void onUnload() => FanCookingCache.current = null;

  /// Reads the vanilla cooking recipes of the smoking and blasting types.
  void _loadCooking(Server server) {
    final cache = FanCookingCache.current;
    if (cache == null) return;
    try {
      final manager = server.getRecipeManager();
      cache.smelting = _load(manager, 'minecraft:smelting');
      cache.blasting = _load(manager, 'minecraft:blasting');
      cache.smoking = _load(manager, 'minecraft:smoking');
    } on Object {
      // a recipe manager that cannot be read leaves the types without vanilla recipes
    }
  }

  static List<CookingEntry> _load(RecipeManager manager, String type) {
    final out = <CookingEntry>[];
    for (final recipe in manager.findRecipes(recipeType: type)) {
      if (recipe.ingredients.isEmpty || recipe.results.isEmpty) continue;
      final ingredient = _convert(recipe.ingredients.first.ingredient);
      if (ingredient == null) continue;
      final result = recipe.results.first;
      out.add(
        CookingEntry(
          recipe.id ?? '$type/${out.length}',
          ingredient,
          PStack(result.item, result.count),
        ),
      );
    }
    return out;
  }

  static ing.Ingredient? _convert(Ingredient ingredient) =>
      switch (ingredient) {
        IngredientItem(:final value) => ing.Ingredient.item(value),
        IngredientTag(:final value) => ing.Ingredient.tag(value),
        IngredientOneOf(:final value) => ing.Ingredient.anyOf([
          for (final v in value) ing.Ingredient.item(v),
        ]),
      };
}
