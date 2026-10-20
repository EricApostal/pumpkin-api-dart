// The `logistics` module: Create's packages and stock logistics on the server (package item and
// entity, packager, repackager, package ports, frogport, postbox, stock link, stock ticker, redstone
// requester, factory gauge, table cloth, list / attribute / package filters). Each folder of this
// directory is a [LogisticsPart]; this class runs them in order. See the library docs of
// `lib/src/api/logistics.dart` for what other modules can use.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/registry.dart';
import 'factory/factory_part.dart';
import 'filter/filter_api.dart';
import 'filter/filter_part.dart';
import 'filter/item_attribute.dart' show ItemAttributeHooks;
import 'filter/logistics_services.dart';
import 'host/runtime.dart';
import 'itemhatch/item_hatch_part.dart';
import 'link/link_part.dart';
import 'logistics_part.dart';
import 'package/package_part.dart';
import 'packager/packager_part.dart';
import 'port/package_port_part.dart';
import 'requester/requester_part.dart';
import 'stock/stock_part.dart';
import 'tablecloth/table_cloth_part.dart';

final class LogisticsModule extends CreateModule {
  /// The parts in registration order. Blocks and block items follow the order of the block
  /// manifest; the package items and filters come after them.
  final List<LogisticsPart> parts = [
    ItemHatchPart(),
    PackagerPart(),
    PortPart(),
    LinkPart(),
    StockPart(),
    RequesterPart(),
    FactoryPart(),
    TableClothPart(),
    PackagePart(),
    FilterPart(),
  ];

  @override
  String get name => 'logistics';

  @override
  void register(CreateRegistry registry) {
    for (final part in parts) {
      part.register(registry);
    }
  }

  @override
  void onLoad(CreateContext ctx) {
    final rt = LgRuntime(ctx);
    Lg.install(rt);
    for (final part in parts) {
      try {
        part.onLoad(ctx, rt);
      } catch (e, s) {
        ctx.log.error(
          'Logistics part ${part.name} failed in onLoad',
          error: e,
          stackTrace: s,
        );
      }
    }

    installLogisticsServices(ctx.services);

    // The networks live in the overworld's saved data; its ticks drive the promise timers.
    ctx.listen(Events.worldLoad, (server, e) {
      if (e.targetWorld.getId() == overworldId) rt.loadGlobal(e.targetWorld);
    });
    ctx.listen(Events.worldTick, (server, e) {
      if (e.targetWorld.getId() != overworldId) return;
      rt.tick++;
      rt.global.tick();
    });
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    final rt = Lg.i;
    for (final world in runtime.server.allWorlds) {
      try {
        if (world.getId() == overworldId) {
          rt.loadGlobal(world);
          break;
        }
      } finally {
        world.dispose();
      }
    }
    for (final part in parts) {
      try {
        part.onServerLoaded(runtime, rt);
      } catch (e, s) {
        runtime.log.error(
          'Logistics part ${part.name} failed in onServerLoaded',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  @override
  void onUnload() {
    for (final part in parts.reversed) {
      try {
        part.onUnload();
      } catch (_) {
        // the plugin is going away
      }
    }
    Lg.clear();
    ItemAttributeHooks.itemInGroup = (_, _) => false;
    ItemFilterApiAdapter.wire = () => null;
  }
}
