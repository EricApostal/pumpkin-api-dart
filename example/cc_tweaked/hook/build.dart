import 'package:hooks/hooks.dart';
import 'package:wasm_tools/hooks.dart';

/// Links the C Lua module (`native/lua/build.sh`) into the component.
void main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildWasmComponent) return;

  final module = input.packageRoot.resolve('native/lua/lua.wasm');
  output.dependencies.add(module);
  output.assets.webAssemblyComponents.addCoreModule(
    WasmCoreModuleAsset(name: 'lua', file: module),
  );
});
