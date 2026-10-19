// The `conveyance` module: Create's belts, chain conveyors, chutes, funnels, tunnels, vaults and
// crates - everything that moves item stacks between inventories. The module is split in two
// registration areas so the content can be ported independently:
//  * `belts_registration.dart`: belts, chain conveyors and the belt funnels;
//  * `transport_registration.dart`: chutes, funnels, tunnels, vaults, crates and the depot/ejector.
// See `docs/ARCHITECTURE.md` for the module contract.
import '../core/module.dart';
import '../core/registry.dart';
import 'belts_registration.dart';
import 'transport_registration.dart';

final class ConveyanceModule extends CreateModule {
  @override
  String get name => 'conveyance';

  @override
  void register(CreateRegistry registry) {
    registerBelts(registry);
    registerTransport(registry);
  }

  @override
  void onLoad(CreateContext ctx) {
    loadBelts(ctx);
    loadTransport(ctx);
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    serverBeltsLoaded(runtime);
    serverTransportLoaded(runtime);
  }

  @override
  void onUnload() {
    unloadBelts();
    unloadTransport();
  }
}
