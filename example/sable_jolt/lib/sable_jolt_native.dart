/// The wasm half of `sable_jolt`: the `jolt.*` imports and the module's memory.
///
/// Import this from a plugin entry point (`bin/main.dart`); it pulls in
/// `dart:_wasm` and only links inside a component that declares the core module
/// (`hook/build.dart`). Tests use `sable_jolt.dart` and drive the module through
/// their own [JoltAbi].
library;

import 'src/jolt/abi.dart';
import 'src/jolt/native.dart';
import 'src/jolt/pipeline.dart';

export 'sable_jolt.dart';
export 'src/jolt/native.dart' show WasmJoltAbi, WasmJoltMemory;

/// A pipeline backed by the linked Jolt core module.
///
/// The module's reactor start (`_initialize`) runs on the first construction;
/// the ADR requires that no module call happens before the Dart program is
/// instantiated, so create this from `Plugin.onLoad`, not from a top-level
/// initializer.
JoltPhysicsPipeline createJoltPipeline() {
  final abi = WasmJoltAbi();
  return JoltPhysicsPipeline(abi: abi, memory: const WasmJoltMemory());
}
