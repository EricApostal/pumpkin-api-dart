// The `fluids` module: the pipes, pump, valve, tanks, spout, item drain and hose
// pulley, the fluids themselves and the item filling / emptying integration.
// It provides the [SteamEngineBoilerSource] the kinetics module consumes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart' show CreateAdvancements;
import '../api/behaviour/spouting/spouting.dart'
    show AllBlockSpoutingBehaviours;
import '../api/config.dart' show CreateConfigs;
import '../api/decoration.dart' show WhistleBoilerHooks;
import '../api/observable.dart' show RedstoneObservables;
import '../api/kinetics.dart' show KineticNetworkService;
import '../api/wrenchable.dart' show WrenchRegistry;
import '../common/block_entity_item_data_host.dart' show ItemDataStamps;
import '../common/pos.dart';
import '../contraptions/core/movement.dart' show MovementBehaviours;
import '../core/block_entity.dart' show BlockEntityStore;
import '../core/blocks.dart' show CreateBlock;
import '../core/module.dart';
import '../core/registry.dart';
import '../decoration/encasing.dart' show EncasingRegistry;
import '../kinetics/runtime.dart' show SteamEngineBoilerSource;
import '../manifest/registries.g.dart' show kFluids;
import '../processing/recipe/recipe_book.dart';
import 'boiler.dart';
import 'fluid_blocks.dart';
import 'fluid_bottle_hook.dart';
import 'fluid_host.dart';
import 'fluid_item_transfer.dart';
import 'fluid_registration.dart';
import 'fluid_runtime.dart';
import 'fluid_tank.dart';
import 'fluid_tank_movement_behaviour.dart';
import 'fluid_world.dart';
import 'generic_item_fluid.dart';
import 'open_pipe_effects.dart';
import 'pipe_observable_probe.dart';

/// The fluids module. Add `FluidsModule()` to `allModules` after `processing`.
final class FluidsModule extends CreateModule {
  List<CreateBlock> _blocks = const [];
  FluidsRuntime? _runtime;
  bool _hooksRegistered = false;

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
    _hooksRegistered = false;
    // The tanks' and the schematicannon's item data (one shared mechanism): the drop and
    // pick-block stamping and the placement apply.
    ItemDataStamps.install(ctx);
    BoilerHeaters.registerDefaults();
    OpenPipeEffects.registerDefaults();
    AllBlockSpoutingBehaviours.registerDefaults();
    // The tank's fluid level is a client side LerpedFloat; the actor must tick while the
    // contraption stands still (`AllBlocks.FLUID_TANK.onRegister(movementBehaviour(...))`).
    MovementBehaviours.register(
      'create:fluid_tank',
      const FluidTankMovementBehaviour(),
    );
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
    // The whistle asks the tank below it to re-evaluate its boiler when it is placed or
    // removed (`WhistleBlock.updateShape` / `onPlace`).
    ctx.services.provide<WhistleBoilerHooks>(
      _FluidWhistleBoilerHooks(ctx.blockEntities),
    );
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
    if (kinetic != null) {
      kinetic.boilerSource = TankBoilerSource(runtime.blockEntities);
    }

    // The decoration and equipment modules provide these services after this module's
    // `onLoad`, so the hooks are installed once everything is loaded.
    if (!_hooksRegistered) {
      _hooksRegistered = true;
      final encasing = runtime.services.find<EncasingRegistry>();
      if (encasing != null) registerFluidEncasing(encasing);
      final wrench = runtime.services.find<WrenchRegistry>();
      if (wrench != null) {
        registerFluidWrench(wrench);
        registerPumpWrench(wrench);
      }
      registerFluidPipeTransforms();
    }

    // The smart observer sees the fluid flowing into a pipe (`ObservableProbe`); redstone
    // publishes the registry in its `onLoad`.
    runtime.services.find<RedstoneObservables>()?.register(const PipeObservableProbe());
  }

  @override
  void onUnload() {
    _runtime?.dispose();
    _runtime = null;
  }
}

/// `FluidTankBlock.updateBoilerState(state, level, tankPos)` for the steam whistle.
final class _FluidWhistleBoilerHooks implements WhistleBoilerHooks {
  final BlockEntityStore store;

  const _FluidWhistleBoilerHooks(this.store);

  @override
  Future<void> updateBoilerState(World world, Pos tankPos) async {
    final worldId = FluidsRuntime.instance.worlds.touch(world);
    final be = store.at(
      worldId,
      BlockPos(x: tankPos.$1, y: tankPos.$2, z: tankPos.$3),
    );
    if (be is! FluidTankBlockEntity) return;
    be.controllerBe?.updateBoilerState();
  }
}
