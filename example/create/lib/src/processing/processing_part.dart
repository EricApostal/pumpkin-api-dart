// A part of the processing module: one machine family (crusher, press, mixer, ...). The
// module (`processing_module.dart`) lists the parts and forwards the lifecycle to them.
import '../core/module.dart';
import '../core/registry.dart';
import 'processing_runtime.dart';

/// One machine family of the processing module, in `lib/src/processing/<dir>/`.
abstract class ProcessingPart {
  /// Lowercase unique name (`crusher`); also the key of `core.modules`-style switches in logs.
  String get name;

  /// Phase 1: declare blocks, items, block entity types, tags. No host calls.
  void register(CreateRegistry registry) {}

  /// Phase 2 (registries applied; the [ProcessingRuntime] and the recipe book exist): listen to
  /// events, provide services, register kinetic block rules.
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {}

  /// Phase 3 (server loaded): bind to services of modules that load later.
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {}

  /// The plugin unloads.
  void onUnload() {}
}
