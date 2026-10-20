// Registration hooks for the belt half of the conveyance module: belts, chain conveyors and the
// belt funnels. `conveyance_module.dart` calls these in its phases; the belt area fills them in.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/kinetics.dart' show KineticNetworkService, KState;
import '../api/payloads.dart' show PayloadBus;
import '../api/schematics.dart'
    show SchematicBeltHooks, SchematicHooks, safeBlockEntityData;
import '../api/wrenchable.dart'
    show CallbackWrenchable, WrenchRegistry, WrenchResult;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/blocks.dart';
import '../core/module.dart';
import '../core/registry.dart';
import 'belt/belt_block.dart';
import 'belt/belt_block_entity.dart';
import 'belt/belt_connector_item.dart';
import 'belt/belt_connector_item.dart' as belt_connector;
import 'belt/belt_geometry.dart';
import 'chain/chain_conveyor_block.dart';
import 'chain/chain_conveyor_block_entity.dart';
import 'chain/chain_conveyor_logic.dart' show getChainCost;
import 'chain/chain_conveyor_networking.dart';
import 'chain/chain_conveyor_port.dart';
import 'runtime.dart';

CreateBlock? _beltBlock;
CreateBlock? _chainConveyorBlock;

/// The schematic hooks this module installed, cleared on unload.
SchematicHooks? _schematicHooks;

/// Phase 1: blocks, block entity types, items.
void registerBelts(CreateRegistry registry) {
  final belt = buildBeltBlock();
  final chain = buildChainConveyorBlock();
  _beltBlock = belt;
  _chainConveyorBlock = chain;

  registry.block(belt);
  registry.block(chain);

  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:belt',
      validBlocks: const ['create:belt'],
      create: (worldId, pos) => BeltBlockEntity(worldId, pos),
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:chain_conveyor',
      validBlocks: const ['create:chain_conveyor'],
      create: (worldId, pos) => ChainConveyorBlockEntity(worldId, pos),
    ),
  );

  // The belt itself has no block item; the connector item places it between two shafts.
  registry.item(const ItemRegistration(key: beltConnectorKey));
}

/// Phase 2: services, event subscriptions, kinetic block rules, payload handlers.
void loadBelts(CreateContext ctx) {
  final rt = ConveyanceRuntime(ctx);
  final belt = _beltBlock;
  final chain = _chainConveyorBlock;
  if (belt != null) rt.blocks[belt.key] = belt;
  if (chain != null) rt.blocks[chain.key] = chain;

  final kinetics = ctx.services.find<KineticNetworkService>();
  if (kinetics != null) {
    kinetics.registerKineticBlock('create:belt', const BeltBlockDef());
    kinetics.registerKineticBlock(
      'create:chain_conveyor',
      const ChainConveyorBlockDef(),
    );
  } else {
    ctx.log.warn(
      'No kinetic network: belts and chain conveyors will not turn.',
    );
  }

  ctx.services.provide<ChainConveyorPortRegistry>(ChainConveyorPortRegistry());

  final bus = ctx.services.find<PayloadBus>();
  if (bus != null) {
    installChainConveyorPackets(rt, bus);
  } else {
    ctx.log.warn(
      'No payload bus: chain conveyor connections and packages are not handled.',
    );
  }

  // `ChainConveyorBlockEntity.transform`: connections follow a contraption that moves the
  // conveyor.
  registerChainConveyorTransform();

  // The belt connector places a belt between two shafts (`BeltConnectorItem.useOn`).
  ctx.host.intercept(Events.itemUseFirst, (server, e) async {
    if (e.useResult != ItemUseFirstResult.pass) return e;
    final handled = await useBeltConnector(rt, e);
    return handled ? e.copyWith(useResult: ItemUseFirstResult.success) : e;
  });

  // `ServerChainConveyorHandler.tick`: the riding TTLs are global, tick them once per server tick.
  ctx.listen(Events.worldTick, (server, e) {
    if (e.targetWorld.getId() != 'minecraft:overworld') return;
    ServerChainConveyorHandler.tick(rt);
  });
}

/// Phase 3: the server finished loading.
void serverBeltsLoaded(CreateRuntime runtime) {
  // `ChainConveyorBlockEntity.writeSafe`: a printed conveyor keeps its chains.
  final hooks = runtime.services.find<SchematicHooks>();
  if (hooks != null) {
    hooks.safeNbtWriters['create:chain_conveyor'] = (state, nbt) =>
        safeBlockEntityData(state, nbt, extraKeys: const ['Connections']);
  } else {
    runtime.log.warn(
      'No schematic hooks: printed chain conveyors lose their connections.',
    );
  }

  // `LaunchedBelt`: a schematic cannon places the shaft and asks for the belt run between it and
  // the far pulley (`BeltConnectorItem.createBelts` / `BeltBlockEntity.setCasingType`).
  if (hooks != null) {
    _schematicHooks = hooks;
    hooks.beltHooks = _BeltSchematicHooks(
      ConveyanceRuntime.loaded ? ConveyanceRuntime.i : null,
    );
  }

  final wrench = runtime.services.find<WrenchRegistry>();
  if (wrench == null) {
    runtime.log.warn(
      'No wrench registry: belts and chain conveyors cannot be wrenched.',
    );
    return;
  }

  wrench.register(
    'create:belt',
    CallbackWrenchable(
      onWrenchedOverride: (c) async {
        if (!ConveyanceRuntime.loaded) return WrenchResult.pass;
        final rt = ConveyanceRuntime.i;
        final worldId = rt.ctx.worlds.touch(c.world);
        final pos = c.pos.toPos();
        final be = rt.typedAt<BeltBlockEntity>(worldId, pos);
        if (be == null) return WrenchResult.pass;

        // A cased belt loses its casing; a pulley becomes a middle segment and drops the shaft.
        if (be.casing != BeltCasing.none) {
          be.setCasingType(BeltCasing.none);
          return WrenchResult.success;
        }
        final state = rt.stateAt(worldId, pos);
        if (state.beltPart == BeltPart.pulley) {
          await rt.kinetics?.switchToBlockState(
            worldId,
            pos.toBlockPos(),
            KState(
              'create:belt',
              state.setValue('part', BeltPart.middle.name).props,
            ),
          );
          if (!c.player.isCreative) {
            final shaft = ItemStack.create(
              registryKey: 'create:shaft',
              count: 1,
            );
            final left = await c.player.give(shaft);
            if (left != null)
              await c.world.dropItem(c.player.getPosition(), left);
          }
          return WrenchResult.success;
        }
        return WrenchResult.pass;
      },
    ),
  );

  wrench.register(
    'create:chain_conveyor',
    CallbackWrenchable(
      onSneakOverride: (c) async {
        if (!ConveyanceRuntime.loaded) return WrenchResult.pass;
        final rt = ConveyanceRuntime.i;
        final worldId = rt.ctx.worlds.touch(c.world);
        final be = rt.typedAt<ChainConveyorBlockEntity>(worldId, c.pos.toPos());
        if (be == null) return WrenchResult.pass;
        be.cancelDrops = true;
        if (!c.player.isCreative) {
          for (final target in be.connections) {
            var cost = getChainCost(target);
            while (cost > 0) {
              final count = cost < 64 ? cost : 64;
              final stack = ItemStack.create(
                registryKey: 'minecraft:iron_chain',
                count: count,
              );
              final left = await c.player.give(stack);
              if (left != null)
                await c.world.dropItem(c.player.getPosition(), left);
              cost -= 64;
            }
          }
        }
        return wrench.defaultDismantle(c);
      },
    ),
  );
}

/// Plugin unload.
void unloadBelts() {
  _schematicHooks?.beltHooks = null;
  _schematicHooks = null;
  ServerChainConveyorHandler.hangingPlayers.clear();
  if (ConveyanceRuntime.loaded) ConveyanceRuntime.i.dispose();
}

/// `SchematicBeltHooks` over the belts of this module.
final class _BeltSchematicHooks implements SchematicBeltHooks {
  _BeltSchematicHooks(this.rt);

  final ConveyanceRuntime? rt;

  @override
  Future<void> createBelts(String worldId, Pos start, Pos end) async {
    final rt = this.rt;
    if (rt == null) return;
    final world = rt.ctx.worlds.byId(worldId);
    if (world == null) return;
    await belt_connector.createBelts(rt, world, worldId, start, end);
  }

  /// `BeltBlockEntity.setCasingType`: 1 is andesite, 2 brass.
  @override
  Future<void> setCasing(String worldId, Pos pos, int casing) async {
    final be = rt?.typedAt<BeltBlockEntity>(worldId, pos);
    be?.setCasingType(
      casing == 2 ? BeltCasing.brass : BeltCasing.andesite,
    );
  }
}
