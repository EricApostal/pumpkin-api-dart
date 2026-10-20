import 'package:hooks/hooks.dart';
import 'package:wasm_tools/hooks.dart';

/// Links the Jolt core module (`native/jolt/jolt.wasm`, built by
/// `native/jolt/build.sh`) into the plugin component.
///
/// The module is checked in, so building the plugin needs no C++ toolchain.
void main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildWasmComponent) return;

  final module = input.packageRoot.resolve('native/jolt/jolt.wasm');
  output.dependencies.add(module);
  output.assets.webAssemblyComponents.addCoreModule(
    WasmCoreModuleAsset(name: 'jolt', file: module),
  );
});
