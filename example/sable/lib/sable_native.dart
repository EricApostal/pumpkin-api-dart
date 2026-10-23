/// The wasm half of the Jolt solver: the `jolt.*` imports and the module's
/// memory.
///
/// Import this from a plugin entry point (`bin/main.dart`); it pulls in
/// `dart:_wasm` and only links inside a component that declares the core module
/// (`hook/build.dart`). The pure model (`src/physics/jolt.dart`) stays free of
/// it and therefore loads on the Dart VM in tests.
library;

import 'src/physics/jolt.dart';
import 'src/physics/jolt/native.dart';
import 'src/physics/jolt/pipeline.dart';

export 'src/physics/jolt.dart';
export 'src/physics/jolt/native.dart' show WasmJoltAbi, WasmJoltMemory;

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