// A part of the logistics module: one folder of `lib/src/logistics/` (packager, ports, filters,
// table cloth, ...). The module runs the parts in the order of its list; a part declares its
// content in `register` (phase 1, no host calls), wires listeners and services in `onLoad`.
import '../core/module.dart';
import '../core/registry.dart';
import 'host/runtime.dart';

abstract class LogisticsPart {
  String get name;

  /// Phase 1: blocks, items, block entity types, entity types.
  void register(CreateRegistry registry) {}

  /// Phase 2: the registries are applied; [rt] is ready. Listen, provide services, install packets.
  void onLoad(CreateContext ctx, LgRuntime rt) {}

  /// Phase 3: the server finished loading.
  void onServerLoaded(CreateRuntime runtime, LgRuntime rt) {}

  void onUnload() {}
}
