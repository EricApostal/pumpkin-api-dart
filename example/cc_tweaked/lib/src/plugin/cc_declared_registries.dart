// The registry list of CC: Tweaked's NeoForge declaration, as the declaration
// types (`NeoForgeRegistryAddition`, which need `pumpkin_api` — wasm-only).
//
// The keys themselves are `CcRegistries.declaredRegistryKeys` (binding-free, so the
// VM test can hold them against what the plugin registers): every host-numbered
// registry the plugin puts content in, plus `computercraft:recipe_function`, the mod
// registry the host does not know.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../protocol/registries.dart';

/// The registries the declaration names, for `Context.declareNeoForge`.
///
/// The entries of a host-numbered registry are the host's own (its dynamic registry,
/// in registration order) and [NeoForgeRegistryAddition.entries] is ignored for it;
/// the one mod registry the host does not know needs the whole list
/// (`CcRegistries.recipeFunctions`).
List<NeoForgeRegistryAddition> ccDeclaredRegistries() => [
  for (final key in CcRegistries.declaredRegistryKeys)
    NeoForgeRegistryAddition(
      key,
      key == CcRegistries.recipeFunctionRegistry
          ? CcRegistries.recipeFunctions
          : const [],
    ),
];