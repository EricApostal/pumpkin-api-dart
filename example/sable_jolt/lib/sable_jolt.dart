/// The pure Dart half of `sable_jolt`: the `PhysicsPipeline` implementation,
/// its voxel model and the buoyancy port.
///
/// Nothing here imports `dart:_wasm`, so this barrel is loadable by
/// `package:test`. The wasm binding of the Jolt core module lives in
/// `sable_jolt_native.dart`.
library;

export 'src/jolt/abi.dart';
export 'src/jolt/pipeline.dart';
export 'src/jolt/voxel.dart';
export 'src/physics/buoyancy.dart';
