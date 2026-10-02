/// Dart API for writing Pumpkin Minecraft server plugins.
///
/// The bindings in `src/bindings.g.dart` are generated from
/// `pumpkin-plugin-wit` with `tool/generate_bindings.sh`.
library;

export 'package:wasm_components/wasm_components.dart'
    show Option, Result, OkResult, ErrorResult;

export 'src/bindings.g.dart' hide definePlugin, PluginExports, Metadata;
export 'src/plugin.dart';
