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
import 'crafter/crafter_part.dart';
import 'crusher/crusher_part.dart';
import 'depot/depot_part.dart';
import 'deployer/deployer_part.dart';
import 'drill/drill_part.dart';
import 'fan/fan_part.dart';
import 'host/recipe_host.dart';
import 'host/storage_lookup.dart';
import 'host/tags_host.dart';
import 'millstone/millstone_part.dart';
import 'mixer/mixer_part.dart';
import 'press/press_part.dart';
import 'processing_part.dart';
import 'processing_runtime.dart';
import 'processing_settings.dart';
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

    ctx.listen(Events.tagsUpdated, (server, e) => _tags.clear());
    ctx.listen(Events.datapackReload, (server, e) => _tags.clear());

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

  @override
  void onUnload() {
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
