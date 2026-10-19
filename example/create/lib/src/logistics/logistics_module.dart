// The `logistics` module: Create's packages and stock logistics on the server (package item and
// entity, packager, repackager, package ports, frogport, postbox, stock link, stock ticker, redstone
// requester, factory gauge, table cloth, list / attribute / package filters). Each folder of this
// directory is a [LogisticsPart]; this class runs them in order. See the library docs of
// `lib/src/api/logistics.dart` for what other modules can use.
import '../core/module.dart';
import '../core/registry.dart';
import 'factory/factory_part.dart';
import 'filter/filter_part.dart';
import 'host/runtime.dart';
import 'logistics_part.dart';
import 'tablecloth/table_cloth_part.dart';

final class LogisticsModule extends CreateModule {
  /// The parts in registration order (blocks follow the order of the block manifest).
  final List<LogisticsPart> parts = [
    FactoryPart(),
    TableClothPart(),
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
        ctx.log.error('Logistics part ${part.name} failed in onLoad', error: e, stackTrace: s);
      }
    }
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    final rt = Lg.i;
    for (final part in parts) {
      try {
        part.onServerLoaded(runtime, rt);
      } catch (e, s) {
        runtime.log.error('Logistics part ${part.name} failed in onServerLoaded', error: e, stackTrace: s);
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
  }
}
