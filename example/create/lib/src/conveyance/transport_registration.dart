// Registration hooks for the item-transport half of the conveyance module: chutes, funnels,
// tunnels, vaults, crates and the depot/ejector. `conveyance_module.dart` calls these in its
// phases; the item-transport area fills them in.
import '../api/wrenchable.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../processing/depot/api.dart';
import 'runtime.dart';
import 'transport/chute/chute_blocks.dart';
import 'transport/crate/creative_crate_block.dart';
import 'transport/depot/depot_api_bridge.dart';
import 'transport/depot/depot_blocks.dart';
import 'transport/depot/ejector_block_entity.dart';
import 'transport/funnel/funnel_blocks.dart';
import 'transport/tunnel/tunnel_blocks.dart';
import 'transport/vault/item_vault_block.dart';

/// Whether this area created the [ConveyanceRuntime] (it is disposed here only then; the belt
/// half may have created it first).
bool _ownsRuntime = false;

/// Phase 1: blocks, block entity types, items.
void registerTransport(CreateRegistry registry) {
  registerChutes(registry);
  registerFunnels(registry);
  registerTunnels(registry);
  registerVault(registry);
  registerCrates(registry);
  registerDepot(registry);
}

/// Phase 2: services, event subscriptions, payload handlers.
void loadTransport(CreateContext ctx) {
  if (!ConveyanceRuntime.loaded) {
    ConveyanceRuntime(ctx);
    _ownsRuntime = true;
  }
  // The ejector takes part in the kinetic network.
  ConveyanceRuntime.i.kinetics?.registerKineticBlock('create:weighted_ejector', const EjectorKineticDef());
}

/// Phase 3: the server finished loading.
void serverTransportLoaded(CreateRuntime runtime) {
  if (!ConveyanceRuntime.loaded) return;
  final ctx = ConveyanceRuntime.i.ctx;

  final wrench = ctx.services.find<WrenchRegistry>();
  if (wrench != null) {
    registerChuteWrench(wrench);
    registerFunnelWrench(wrench);
    registerTunnelWrench(wrench);
    registerVaultWrench(wrench);
    registerCrateWrench(wrench);
    registerDepotWrench(wrench);
  }

  final depotApi = ctx.services.find<DepotApi>();
  if (depotApi != null) registerDepotApi(depotApi);
}

/// Plugin unload.
void unloadTransport() {
  if (_ownsRuntime && ConveyanceRuntime.loaded) ConveyanceRuntime.i.dispose();
  _ownsRuntime = false;
}
