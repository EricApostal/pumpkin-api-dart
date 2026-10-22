// The `processing` module: Create's processing machines (crushing wheels, millstone,
// mechanical press, mixer, basin, blaze burner, saw, drill, encased fan and the air
// currents, mechanical crafter, deployer, depot, mechanical arm), all their recipe types and
// sequenced assembly. See `docs/ARCHITECTURE.md`, "Processing".
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/registry.dart';
import 'arm/arm_part.dart';
import 'assembly/assembly_operator_block_item.dart';
import 'basin/basin_part.dart';
import 'burner/burner_part.dart';
import 'common/stack.dart';
import 'crafter/crafter_part.dart';
import 'crusher/crusher_part.dart';
import 'depot/depot_part.dart';
import 'deployer/deployer_part.dart';
import 'drill/drill_part.dart';
import 'fan/fan_part.dart';
import 'host/host_recipes.dart';
import 'host/recipe_host.dart';
import 'host/storage_lookup.dart';
import 'host/tags_host.dart';
import 'millstone/millstone_part.dart';
import 'mixer/mixer_part.dart';
import 'press/press_part.dart';
import 'processing_part.dart';
import 'processing_runtime.dart';
import 'processing_settings.dart';
import 'recipe/crafting_recipes.dart';
import 'recipe/ingredient.dart' as ing;
import 'recipe/recipe_book.dart';
import 'recipe/recipe_network.dart';
import 'recipe/recipe_type.dart';
import 'saw/saw_part.dart';
import 'sequenced_items.dart';

final class ProcessingModule extends CreateModule {
  @override
  String get name => 'processing';

  /// The machine families, in registration order (the order of the manifest's blocks).
  final List<ProcessingPart> parts = [
    CrusherPart(),
    MillstonePart(),
    PressPart(),
    MixerPart(),
    BasinPart(),
    BlazeBurnerPart(),
    DepotPart(),
    SawPart(),
    DrillPart(),
    FanPart(),
    CrafterPart(),
    DeployerPart(),
    ArmPart(),
  ];

  ProcessingRuntime? _runtime;
  final HostTagLookup _tags = HostTagLookup();

  @override
  void register(CreateRegistry registry) {
    for (final type in CreateRecipeType.registered) {
      registry.recipeType(type.key);
    }
    registerSequencedAssemblyItems(registry);
    for (final p in parts) {
      p.register(registry);
    }
  }

  @override
  void onLoad(CreateContext ctx) {
    final settings = ctx.config.section(
      'processing',
      ProcessingSettingsMapper.fromMap,
      (v) => v.toMap(),
      const ProcessingSettings(),
    );
    final book = RecipeBook(_tags);
    final rt = ProcessingRuntime(
      settings: settings,
      recipes: book,
      tags: _tags,
      store: ctx.blockEntities,
      worlds: ctx.worlds,
      log: ctx.log,
      services: ctx.services,
    );
    _runtime = rt;
    ctx.services.provide<RecipeBook>(book);
    ctx.services.provide<StorageLookup>(rt.storage);
    ctx.services.provide<ProcessingRuntime>(rt);

    _loadRecipes(ctx, rt);

    CraftingRecipeCache.current ??= CraftingRecipeCache();

    ctx.listen(Events.tagsUpdated, (server, e) => _tags.clear());
    ctx.listen(Events.datapackReload, (server, e) {
      _tags.clear();
      _loadCraftingRecipes(server);
      // The plugin recipe table of the host is append only and survives the reload, so the
      // recipes other components contributed are still there; this picks up a component that
      // registered them after this one loaded.
      _loadHostRecipes(server);
    });

    for (final p in parts) {
      try {
        p.onLoad(ctx, rt);
      } catch (e, s) {
        ctx.log.error(
          'Processing part ${p.name} failed to load',
          error: e,
          stackTrace: s,
        );
      }
    }
    // `AssemblyOperatorBlockItem`: the press, mixer, spout and deployer place two blocks above
    // the belt / basin / depot they were clicked on.
    AssemblyOperatorBlockItem.install(ctx);
    ctx.log.info(
      'Processing: ${parts.length} machine families, ${book.count} recipes.',
    );
  }

  void _loadRecipes(CreateContext ctx, ProcessingRuntime rt) {
    final settings = rt.settings;
    final report = RecipeLoadReport();
    final sources = <String, Map<String, dynamic>>{};
    Iterable<(String, Map<String, dynamic>)> collect() sync* {
      if (settings.loadEmbeddedRecipes) {
        for (final s in RecipeSources.embedded()) {
          sources[s.$1] = s.$2;
          yield s;
        }
      }
      if (settings.loadFolderRecipes) {
        try {
          for (final s in RecipeSources.folder(
            ctx.host.files,
            settings.recipeFolder,
          )) {
            sources[s.$1] = s.$2;
            yield s;
          }
        } on Object catch (e) {
          ctx.log.warn(
            'Could not read the recipe folder ${settings.recipeFolder}: $e',
          );
        }
      }
    }

    loadRecipes(rt.recipes, collect(), report: report);
    if (settings.logInvalidRecipes) {
      for (final e in report.errors.take(50)) {
        ctx.log.warn('Recipe not loaded: $e');
      }
      if (report.errors.length > 50)
        ctx.log.warn(
          '... and ${report.errors.length - 50} more invalid recipes',
        );
    }
    try {
      final manager = ctx.host.getServer().getRecipeManager();
      RecipeNetworkEncoder? encoder;
      if (settings.syncRecipes) {
        final syncedTypes = [
          for (final t in CreateRecipeType.registered) t.key,
        ];
        encoder = RecipeNetworkEncoder(
          RecipeNetworkIds(
            item: (key) =>
                VanillaIds.items.idOf(key) ??
                ctx.ids.of(RegistryKind.items, key),
            fluid: (key) => _fluidId(ctx, settings, key),
            serializer: (key) {
              final i = syncedTypes.indexOf(key);
              return i < 0 ? null : settings.vanillaRecipeSerializerCount + i;
            },
          ),
          // A tag the client does not have makes it drop the whole payload, so a recipe that
          // names one is left out (`Tags` queries the host's tags, which are what the client got).
          (item: Tags.itemExists, fluid: Tags.fluidExists),
        );
      }
      registerRecipesWithHost(
        manager,
        rt.recipes,
        report,
        encoder: encoder,
        sources: sources,
      );
    } on Object catch (e, s) {
      ctx.log.error(
        'Registering the recipes with the host failed',
        error: e,
        stackTrace: s,
      );
    }
    ctx.log.info('Recipes: $report');
  }

  static int? _fluidId(
    CreateContext ctx,
    ProcessingSettings settings,
    String key,
  ) {
    const vanilla = [
      'minecraft:empty',
      'minecraft:flowing_water',
      'minecraft:water',
      'minecraft:flowing_lava',
      'minecraft:lava',
    ];
    final v = vanilla.indexOf(key);
    if (v >= 0) return v;
    final own = ctx.ids.of(RegistryKind.fluids, key);
    return own;
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    final rt = _runtime;
    if (rt == null) return;
    // The press and the mixer also run vanilla crafting recipes (`matchStaticFilters`).
    _loadCraftingRecipes(runtime.server);
    // The `create:*` recipes other components contributed (Aeronautics' envelopes, Simulated's
    // machines): their own data pack is invisible to this component, so they come back out of
    // the host's plugin recipe table. Every plugin has finished loading by now.
    _loadHostRecipes(runtime.server);
    for (final p in parts) {
      try {
        p.onServerLoaded(runtime, rt);
      } catch (e, s) {
        runtime.log.error(
          'Processing part ${p.name} failed in onServerLoaded',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  /// The ids of the recipes [_loadHostRecipes] added, so a second call does not duplicate them.
  final Set<String> _hostRecipeIds = {};

  /// Merges the `create:*` recipes other components registered with the host into the book.
  ///
  /// The host's table is query only for the plugin that registered a recipe, and it carries the
  /// source JSON in `extra` — see `loadHostRecipes`.
  void _loadHostRecipes(Server server) {
    final rt = _runtime;
    if (rt == null) return;
    try {
      final report = loadHostRecipes(server.getRecipeManager(), rt.recipes, _hostRecipeIds);
      if (report.added > 0 || report.errors.isNotEmpty) {
        rt.log.info('Recipes contributed by other plugins: $report');
      }
      for (final e in report.errors.take(20)) {
        rt.log.warn('Recipe from another plugin not loaded: $e');
      }
    } on Object catch (e) {
      rt.log.warn('Could not read the recipes of the other plugins: $e');
    }
  }

  /// Reads the vanilla crafting recipes the basin machines can run: the shaped table holds the
  /// compressible squares of the press, the shapeless table the recipes of the mixer.
  void _loadCraftingRecipes(Server server) {
    final cache = CraftingRecipeCache.current;
    if (cache == null) return;
    try {
      final manager = server.getRecipeManager();
      cache.shaped = _craftingRecipes(manager, 'minecraft:crafting_shaped', shaped: true);
      cache.shapeless = _craftingRecipes(manager, 'minecraft:crafting_shapeless', shaped: false);
    } on Object {
      // A recipe manager that cannot be read leaves the machines without crafting recipes.
    }
  }

  static List<CraftingRecipeEntry> _craftingRecipes(
    RecipeManager manager,
    String type, {
    required bool shaped,
  }) {
    final out = <CraftingRecipeEntry>[];
    for (final recipe in manager.findRecipes(recipeType: type)) {
      if (recipe.ingredients.isEmpty || recipe.results.isEmpty) continue;
      final ingredients = <ing.Ingredient>[];
      var complete = true;
      for (final sized in recipe.ingredients) {
        final ingredient = _ingredient(sized.ingredient);
        if (ingredient == null) {
          complete = false;
          break;
        }
        ingredients.add(ingredient);
      }
      if (!complete) continue;
      final result = recipe.results.first;
      out.add(
        CraftingRecipeEntry(
          // Vanilla crafting recipes have no id in the host's tables.
          id: recipe.id ?? '$type/${out.length}',
          shaped: shaped,
          ingredients: ingredients,
          result: PStack(result.item, result.count),
        ),
      );
    }
    return out;
  }

  /// The host ingredient as the pure one; `null` for a form the plugin does not model.
  static ing.Ingredient? _ingredient(Ingredient ingredient) =>
      switch (ingredient) {
        IngredientItem(:final value) => ing.Ingredient.item(value),
        IngredientTag(:final value) => ing.Ingredient.tag(
          value.startsWith('#') ? value.substring(1) : value,
        ),
        IngredientOneOf(:final value) => ing.Ingredient.anyOf([
          for (final v in value) ing.Ingredient.item(v),
        ]),
      };

  @override
  void onUnload() {
    CraftingRecipeCache.current = null;
    for (final p in parts.reversed) {
      try {
        p.onUnload();
      } catch (_) {
        // unloading must not stop the others
      }
    }
    _runtime?.dispose();
    _runtime = null;
  }
}
