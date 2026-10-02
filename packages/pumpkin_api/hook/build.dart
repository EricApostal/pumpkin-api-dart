import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:wasm_tools/hooks.dart';

/// Tells the component compiler about the Pumpkin plugin ABI (the `plugin`
/// world of `pumpkin-plugin-wit`), so plugin authors only need to depend on
/// `package:pumpkin_api`.
void main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildWasmComponent) return;

  final abi = input.packageRoot.resolve('hook/wasm_abi.json');
  output.dependencies.add(abi);
  output.assets.webAssemblyComponents.add(
    WasmComponentAsset(
      encoded:
          json.decode(File.fromUri(abi).readAsStringSync())
              as Map<String, Object?>,
    ),
  );
});
