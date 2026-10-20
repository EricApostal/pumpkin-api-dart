// The `conveyance` module: Create's belts, chain conveyors, chutes, funnels, tunnels, vaults and
// crates - everything that moves item stacks between inventories. The module is split in two
// registration areas so the content can be ported independently:
//  * `belts_registration.dart`: belts, chain conveyors and the belt funnels;
//  * `transport_registration.dart`: chutes, funnels, tunnels, vaults, crates and the depot/ejector.
// See `docs/ARCHITECTURE.md` for the module contract.
import '../api/filter_api.dart' show ItemFilterApi;
import '../api/redstone.dart' show RedstoneObservables;
import '../api/trains.dart' show StationDepotFactory;
import '../core/module.dart';
import '../core/registry.dart';
import 'belts_registration.dart';
import 'chain_observable_probe.dart';
import 'items/filter_match.dart' as filter_match;
import 'observable_probes.dart';
import 'runtime.dart';
import 'transport/depot/station_depot.dart';
import 'transport/funnel/funnel_block_entity.dart';
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
    // The filter slots match their item through the logistics module's `ItemFilterApi`
    // (`FilterItemStack`); without that module a filter item matches nothing.
    filter_match.itemFilterApi = () => ctx.services.find<ItemFilterApi>();
    // The station's schedule slot is a `DepotBehaviour`; the depot behaviour is this module's,
    // so the station's slot comes from here (`StationBlockEntity.getAutoSchedule`).
    ctx.services.provide<StationDepotFactory>(const StationDepotFactoryImpl());
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    serverBeltsLoaded(runtime);
    serverTransportLoaded(runtime);
    // The smart observer sees the items on belts and depots and the packages looping on a chain
    // conveyor (`ObservableProbe`); redstone publishes the registry in its `onLoad`.
    final observables = runtime.services.find<RedstoneObservables>();
    observables?.register(
      BeltObservableProbe(
        lookup: (worldId, pos) => ConveyanceRuntime.i.beAt(worldId, pos),
        alsoObserves: (be) => be is FunnelBlockEntity,
      ),
    );
    observables?.register(const ChainConveyorObservableProbe());
  }

  @override
  void onUnload() {
    unloadBelts();
    unloadTransport();
    filter_match.itemFilterApi = () => null;
  }
}
