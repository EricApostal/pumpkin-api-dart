// The mechanical saw part of the processing module: the block and its block entity, the cutting
// recipes (Create cutting plus vanilla stonecutting) and the contraption actor.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../contraptions/core/movement.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../support/kinetics_bridge.dart';
import '../common/stack.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../recipe/ingredient.dart' as ing;
import 'saw_block.dart';
import 'saw_movement.dart';
import 'saw_recipes.dart';
import 'saw_spec.dart';

/// The mechanical saw.
final class SawPart extends ProcessingPart {
  @override
  String get name => 'saw';

  @override
  void register(CreateRegistry registry) {
    final spec = sawSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:saw',
        validBlocks: [spec.block.key],
        create: SawBlockEntity.new,
      ),
    );
    registry.block(spec.block);
    SawRecipeCache.current ??= SawRecipeCache();
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:mechanical_saw',
      const SawBlockDef(),
    );
    MovementBehaviours.register(
      'create:mechanical_saw',
      const SawMovementBehaviour(),
    );
    ctx.listen(Events.datapackReload, (server, e) => _loadStonecutting(server));
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) =>
      _loadStonecutting(runtime.server);

  @override
  void onUnload() => SawRecipeCache.current = null;

  /// Reads the vanilla stonecutting recipes the saw may use (`recipes.allowStonecuttingOnSaw`).
  void _loadStonecutting(Server server) {
    final cache = SawRecipeCache.current;
    if (cache == null) return;
    final recipes = <StonecuttingRecipe>[];
    try {
      final manager = server.getRecipeManager();
      for (final recipe in manager.findRecipes(
        recipeType: 'minecraft:stonecutting',
      )) {
        if (recipe.ingredients.isEmpty || recipe.results.isEmpty) continue;
        final ingredient = _convert(recipe.ingredients.first.ingredient);
        if (ingredient == null) continue;
        final out = recipe.results.first;
        recipes.add(
          StonecuttingRecipe(
            recipe.id ?? 'minecraft:stonecutting/${recipes.length}',
            ingredient,
            PStack(out.item, out.count),
          ),
        );
      }
    } on Object {
      // a recipe manager that cannot be read leaves the saw with the Create recipes only
      return;
    }
    cache.stonecutting = recipes;
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
