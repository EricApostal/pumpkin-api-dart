import 'package:hooks/hooks.dart';
import 'package:meta/meta.dart';

@internal
const name = 'custom/wasm-component';

@internal
const coreModuleName = 'custom/wasm-core-module';

/// A protocol extension allowing build hooks in packages to declare
/// dependencies on WebAssembly components and to export Dart methods.
final class WasmComponentExtension extends ProtocolExtension {
  @override
  void setupBuildInput(BuildInputBuilder input) {
    input.config.addBuildAssetTypes(const [name, coreModuleName]);
  }
}

extension HookConfigWasm on HookConfig {
  /// Whether WebAssembly components can be used by the Dart app being built.
  bool get buildWasmComponent => buildAssetTypes.contains(name);
}

/// Extension on [BuildOutputAssetsBuilder] to add [WasmComponentAsset]s.
extension BuildOutputAssetsBuilderWasm on BuildOutputAssetsBuilder {
  /// Provides access to emitting code assets.
  ///
  /// Should only be used if [HookConfigWasm.buildWasmComponent] is true.
  BuildOutputWasmComponentAssetBuilder get webAssemblyComponents {
    return BuildOutputWasmComponentAssetBuilder._(this);
  }
}

/// Extension on [BuildOutputAssetsBuilder] to add [WasmComponentAsset]s.
final class BuildOutputWasmComponentAssetBuilder {
  final BuildOutputAssetsBuilder _output;

  BuildOutputWasmComponentAssetBuilder._(this._output);

  void add(WasmComponentAsset asset) {
    _output.addEncodedAsset(asset.encode());
  }

  void addCoreModule(WasmCoreModuleAsset asset) {
    _output.addEncodedAsset(asset.encode());
  }
}

/// A pre-compiled core WebAssembly module that is linked into the component
/// next to the compiled Dart module.
///
/// The module has its own linear memory. Dart reaches it by declaring imports
/// from the module [name] (`@pragma('wasm:import', '<name>.<export>')`,
/// including `<name>.memory` as a `Memory`).
///
/// The only import the module may have is `host.call`, a function
/// `(i32, i32, i32, i32) -> i32` that is routed to the Dart function annotated
/// with `@pragma('wasm:export', 'host_call')`. The Dart program must not call
/// into the module before its `main` has returned, since the routing is only
/// complete after the program is instantiated.
final class WasmCoreModuleAsset {
  /// The name Dart imports the module's exports from.
  final String name;

  /// The `.wasm` file of the module.
  final Uri file;

  const WasmCoreModuleAsset({required this.name, required this.file});

  EncodedAsset encode() {
    return EncodedAsset(coreModuleName, {
      'name': name,
      'file': file.toFilePath(),
    });
  }
}

final class WasmComponentAsset {
  /// The WIT context, as serialized by `wasm-tools component wit -j`.
  final Map<String, Object?> encoded;

  const WasmComponentAsset({required this.encoded});

  /// Encodes this into an [EncodedAsset] that can be added to
  /// [BuildOutputAssetsBuilder].
  EncodedAsset encode() {
    return EncodedAsset(name, encoded);
  }
}
