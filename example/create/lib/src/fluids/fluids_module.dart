// The `fluids` module: the pipes, pump, valve, tanks, spout, item drain and hose
// pulley, the fluids themselves and the item filling / emptying integration.
// It provides the [SteamEngineBoilerSource] the kinetics module consumes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart' show CreateAdvancements;
import '../api/config.dart' show CreateConfigs;
import '../api/kinetics.dart' show KineticNetworkService;
import '../core/blocks.dart' show CreateBlock;
import '../core/module.dart';
import '../core/registry.dart';
import '../kinetics/runtime.dart' show SteamEngineBoilerSource;
import '../manifest/registries.g.dart' show kFluids;
import '../processing/recipe/recipe_book.dart';
import 'boiler.dart';
import 'fluid_blocks.dart';
import 'fluid_bottle_hook.dart';
import 'fluid_host.dart';
import 'fluid_item_transfer.dart';
import 'fluid_runtime.dart';
import 'fluid_tank.dart';
import 'fluid_world.dart';
import 'generic_item_fluid.dart';

/// The fluids module. Add `FluidsModule()` to `allModules` after `processing`.
final class FluidsModule extends CreateModule {
  List<CreateBlock> _blocks = const [];
  FluidsRuntime? _runtime;

  @override
  String get name => 'fluids';

  @override
  void register(CreateRegistry registry) {
    _blocks = [
      ...buildFluidBlocks(),
      pumpBlock(),
      valveBlock(),
      hosePulleyBlock(),
    ];
    for (final block in _blocks) {
      registry.block(block);
    }
    for (final type in buildFluidBlockEntityTypes()) {
      registry.blockEntityType(type);
    }
    registerFluidItems(registry);
    registerFluids(registry);
  }

  @override
  void onLoad(CreateContext ctx) {
    BoilerHeaters.registerDefaults();
    final configs = ctx.services.find<CreateConfigs>();
    final book = ctx.services.find<RecipeBook>();
    final runtime = FluidsRuntime(
      config: configs == null
          ? const DefaultFluidsConfig()
          : ConfigsFluidsConfig(configs),
      store: ctx.blockEntities,
      worlds: ctx.worlds,
      log: ctx.log,
      rules: hostItemFluidRules(),
      recipes: book == null
          ? const NoFluidItemRecipes()
          : RecipeFluidItemRecipes(book),
      advancements: ctx.services.find<CreateAdvancements>(),
      serverProvider: () {
        try {
          return ctx.host.getServer();
        } on Object {
          return null;
        }
      },
    );
    _runtime = runtime;

    // The boiler efficiency the steam engine reads.
    final boiler = TankBoilerSource(ctx.blockEntities);
    ctx.services.provide<SteamEngineBoilerSource>(boiler);
    final kinetic = ctx.services.find<KineticNetworkService>();
    if (kinetic != null) {
      for (final entry in fluidKineticDefs.entries) {
        kinetic.registerKineticBlock(entry.key, entry.value);
      }
      kinetic.boilerSource = boiler;
    }

    FluidBottleItemHook.install(ctx);
    ctx.listen(Events.worldUnload, (server, e) {
      if (!e.cancelled) runtime.forgetWorld(e.targetWorld.getId());
    });

    ctx.log.info('Fluids: ${_blocks.length} blocks, ${kFluids.length} fluids.');
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    final kinetic = runtime.services.find<KineticNetworkService>();
    if (kinetic != null)
      kinetic.boilerSource = TankBoilerSource(runtime.blockEntities);
  }

  @override
  void onUnload() {
    _runtime?.dispose();
    _runtime = null;
  }
}
